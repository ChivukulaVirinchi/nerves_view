#!/usr/bin/env elixir

# Generic architectural boundary checker for any Elixir/Phoenix project.
#
# Checks:
# 1. Web layer (LiveViews, controllers, components) doesn't call Repo directly
#    — all data access should go through context modules.
#
# Skips: migration files, test files, seeds.

defmodule ArchitectureBoundaryChecker do
  @lib_root "lib"

  def run do
    web_root = find_web_root()

    if is_nil(web_root) do
      IO.puts("✅ No *_web directory found — skipping architecture checks")
      System.halt(0)
    end

    repo_issues = check_repo_in_web(web_root)

    if repo_issues == [] do
      IO.puts("✅ No boundary violations found")
    else
      Enum.each(repo_issues, &print_issue/1)
      IO.puts("Total: #{length(repo_issues)} violation(s)")
      System.halt(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Dynamic project detection
  # ---------------------------------------------------------------------------

  defp find_web_root do
    if File.dir?(@lib_root) do
      case File.ls!(@lib_root) |> Enum.find(&String.ends_with?(&1, "_web")) do
        nil -> nil
        dir -> Path.join(@lib_root, dir)
      end
    else
      nil
    end
  end

  # ---------------------------------------------------------------------------
  # Repo calls in the web layer
  # ---------------------------------------------------------------------------

  defp check_repo_in_web(web_root) do
    issues =
      web_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&skip_file?/1)
      |> Enum.flat_map(&check_file_for_repo/1)

    if issues == [] do
      IO.puts("✅ Repo boundary: clean (web layer calls contexts only)")
    end

    issues
  end

  # Skip migration files, test files, and seeds
  defp skip_file?(file) do
    String.contains?(file, "/migrations/") or
      String.contains?(file, "/priv/") or
      String.contains?(file, "_test.exs") or
      String.contains?(file, "/test/") or
      String.contains?(file, "seeds.exs")
  end

  defp check_file_for_repo(file) do
    relative = Path.relative_to_cwd(file)
    content = File.read!(file)
    doc_line_set = docstring_lines(content)

    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      trimmed = String.trim(line)

      cond do
        # Skip comments
        String.starts_with?(trimmed, "#") -> []
        # Skip module docs / doc strings
        String.starts_with?(trimmed, "@moduledoc") -> []
        String.starts_with?(trimmed, "@doc") -> []
        String.starts_with?(trimmed, "\"\"\"") -> []
        # Skip lines inside heredoc docstrings
        MapSet.member?(doc_line_set, line_num) -> []
        # Catch Repo.one, Repo.all, Repo.get, Repo.insert, etc.
        Regex.match?(~r/\bRepo\.(get|get!|get_by|get_by!|one|one!|all|insert|insert!|update|update!|delete|delete!|aggregate|exists\?|preload|transaction)\b/, trimmed) ->
          [{:repo_boundary, relative, line_num,
            "Web layer calls Repo directly (use a context function instead)", line}]
        true -> []
      end
    end)
  end

  # Returns a MapSet of line numbers that are inside @moduledoc/@doc heredoc blocks
  defp docstring_lines(content) do
    lines = String.split(content, "\n")

    {doc_lines, _} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({MapSet.new(), nil}, fn {line, line_num}, {acc, state} ->
        trimmed = String.trim(line)

        case state do
          nil ->
            if Regex.match?(~r/^@(moduledoc|doc)\s+~[sS]?"""/, trimmed) or
                 Regex.match?(~r/^@(moduledoc|doc)\s+"""/, trimmed) do
              {MapSet.put(acc, line_num), :in_doc}
            else
              {acc, nil}
            end

          :in_doc ->
            if trimmed == ~S(""") or String.ends_with?(trimmed, ~S(""")) do
              {MapSet.put(acc, line_num), nil}
            else
              {MapSet.put(acc, line_num), :in_doc}
            end
        end
      end)

    doc_lines
  end

  # --- Output ---

  defp print_issue({:repo_boundary, file, line_num, message, line}) do
    IO.puts("  ❌ [REPO-IN-WEB] #{file}:#{line_num}")
    IO.puts("    #{String.trim(line)}")
    IO.puts("    → #{message}\n")
  end
end

ArchitectureBoundaryChecker.run()
