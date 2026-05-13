#!/usr/bin/env elixir

# Checks public functions for missing @spec annotations.
#
# @spec enables Dialyzer type checking and documents the function contract.
# Source: implementing/SKILL.md §1 #14, reviewing/quality-gates.md §3.6
#
# Checks:
# 1. Public def without a preceding @spec
#
# Skips: test files, migrations, mix.exs, Phoenix-generated boilerplate,
#        callback implementations (@impl true), and defdelegate.

defmodule SpecChecker do
  @lib_root "lib"

  def run do
    issues =
      @lib_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&skip_file?/1)
      |> Enum.flat_map(&check_file/1)

    if issues == [] do
      IO.puts("✅ All public functions have @spec")
    else
      Enum.each(issues, &print_issue/1)
      IO.puts("\nTotal: #{length(issues)} public function(s) missing @spec")
      IO.puts("  Note: This is a SUGGEST-level check. Add # spec:allow to suppress individual functions.")
      System.halt(1)
    end
  end

  defp skip_file?(file) do
    String.contains?(file, "_test.exs") or
      String.contains?(file, "/test/") or
      String.contains?(file, "/migrations/") or
      String.contains?(file, "/priv/") or
      String.ends_with?(file, "mix.exs") or
      String.ends_with?(file, "application.ex") or
      String.ends_with?(file, "repo.ex") or
      String.ends_with?(file, "endpoint.ex") or
      String.ends_with?(file, "telemetry.ex") or
      String.ends_with?(file, "gettext.ex") or
      String.ends_with?(file, "router.ex") or
      String.ends_with?(file, "mailer.ex")
  end

  defp check_file(file) do
    relative = Path.relative_to_cwd(file)
    content = File.read!(file)
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> find_unspecced_functions(relative, lines)
  end

  defp find_unspecced_functions(indexed_lines, file, all_lines) do
    indexed_lines
    |> Enum.flat_map(fn {line, line_num} ->
      trimmed = String.trim(line)

      cond do
        String.starts_with?(trimmed, "#") -> []

        # Match public function definitions (not defp, defmacro, defmacrop, defdelegate, defguard)
        Regex.match?(~r/^\s*def\s+[a-z_]\w*[\(\s]/, line) or
            Regex.match?(~r/^\s*def\s+[a-z_]\w*\s*,/, line) ->

          func_name = extract_function_name(trimmed)

          cond do
            # Skip Phoenix/Plug callbacks that are always @impl
            func_name in ~w(init call mount render handle_event handle_info handle_params
                           handle_async handle_call handle_cast terminate code_change
                           child_spec start_link perform) ->
              []

            # Skip if preceded by @impl
            has_impl_above?(all_lines, line_num) -> []

            # Skip if preceded by @spec
            has_spec_above?(all_lines, line_num, func_name) -> []

            # Skip if has suppression comment
            has_suppression?(all_lines, line_num) -> []

            true ->
              [{:missing_spec, file, line_num,
                "Public function `#{func_name}` has no @spec",
                line}]
          end

        true -> []
      end
    end)
  end

  defp extract_function_name(line) do
    case Regex.run(~r/def\s+([a-z_]\w*[\?\!]?)/, line) do
      [_, name] -> name
      _ -> "unknown"
    end
  end

  # Look up to 5 lines above for @spec with the same function name
  defp has_spec_above?(lines, line_num, func_name) do
    start = max(0, line_num - 6)
    above = Enum.slice(lines, start, line_num - start - 1)

    Enum.any?(above, fn l ->
      Regex.match?(~r/@spec\s+#{Regex.escape(func_name)}\b/, l)
    end)
  end

  # Look up to 3 lines above for @impl
  defp has_impl_above?(lines, line_num) do
    start = max(0, line_num - 4)
    above = Enum.slice(lines, start, line_num - start - 1)

    Enum.any?(above, fn l ->
      trimmed = String.trim(l)
      Regex.match?(~r/^@impl\b/, trimmed)
    end)
  end

  defp has_suppression?(lines, line_num) do
    start = max(0, line_num - 3)
    above = Enum.slice(lines, start, line_num - start - 1)

    Enum.any?(above, fn l ->
      String.contains?(l, "spec:allow")
    end)
  end

  defp print_issue({:missing_spec, file, line_num, message, line}) do
    IO.puts("  ⚠️  [MISSING-SPEC] #{file}:#{line_num}")
    IO.puts("    #{String.trim(line)}")
    IO.puts("    → #{message}")
  end
end

SpecChecker.run()
