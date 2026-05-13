#!/usr/bin/env elixir

# Checks for bracket index access on lists: list[0], items[1], etc.
#
# Lists in Elixir don't implement the Access behaviour. list[0] returns nil
# instead of raising, hiding bugs silently. Use Enum.at/2 or hd/1 instead.
# Source: reviewing/elixir-gotchas.md §3.1
#
# Checks:
# 1. Variables with list-like names accessed via bracket + integer index
# 2. Common patterns: items[0], results[1], rows[0], entries[n], list[0]

defmodule ListAccessChecker do
  @lib_root "lib"

  @list_name_patterns ~w(
    items results rows entries records elements values
    users orders products events messages notifications
    children nodes siblings matches lines words tokens
    chunks batches pages parts segments pieces
    list lists data files paths names tags errors
  )

  def run do
    issues =
      [@lib_root, "test"]
      |> Enum.flat_map(fn root ->
        if File.dir?(root) do
          Path.join(root, "**/*.{ex,exs}")
          |> Path.wildcard()
        else
          []
        end
      end)
      |> Enum.reject(&skip_file?/1)
      |> Enum.flat_map(&check_file/1)

    if issues == [] do
      IO.puts("✅ No list bracket access found")
    else
      Enum.each(issues, &print_issue/1)
      IO.puts("\nTotal: #{length(issues)} issue(s)")
      IO.puts("  Lists don't implement Access — use Enum.at/2, hd/1, or pattern matching")
      System.halt(1)
    end
  end

  defp skip_file?(file) do
    String.contains?(file, "/migrations/") or
      String.contains?(file, "/priv/")
  end

  defp check_file(file) do
    relative = Path.relative_to_cwd(file)
    content = File.read!(file)

    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      trimmed = String.trim(line)

      cond do
        String.starts_with?(trimmed, "#") -> []
        in_string_context?(trimmed) -> []
        String.contains?(line, "list-access:allow") -> []

        true ->
          check_line_for_list_access(trimmed, line_num, relative, line)
      end
    end)
  end

  defp check_line_for_list_access(trimmed, line_num, file, line) do
    # Pattern: variable_name[integer] where variable is a common list name
    list_names_pattern = @list_name_patterns |> Enum.join("|")
    regex = ~r/\b(#{list_names_pattern})\[(\d+)\]/

    case Regex.run(regex, trimmed) do
      [_match, var_name, _index] ->
        [{:list_access, file, line_num,
          "`#{var_name}` looks like a list — bracket access returns nil instead of raising. Use Enum.at/2",
          line}]
      _ ->
        # Also catch the generic pattern: any_var[0] where it's clearly numeric
        generic = ~r/\b([a-z_]\w*)\[0\]/
        case Regex.run(generic, trimmed) do
          [_match, var_name] ->
            # Skip known map/keyword access patterns
            if map_like_name?(var_name) do
              []
            else
              [{:list_access, file, line_num,
                "`#{var_name}[0]` — if this is a list, bracket access silently returns nil. Use hd/1 or Enum.at/2",
                line}]
            end
          _ -> []
        end
    end
  end

  defp map_like_name?(name) do
    name in ~w(
      map maps config opts options params attrs assigns
      socket conn meta metadata headers query response
      env settings state acc payload body json
    )
  end

  defp in_string_context?(line) do
    # Skip lines that are predominantly strings (rough heuristic)
    quote_count = line |> String.graphemes() |> Enum.count(&(&1 == "\""))
    quote_count >= 2
  end

  defp print_issue({:list_access, file, line_num, message, line}) do
    IO.puts("  ❌ [LIST-BRACKET-ACCESS] #{file}:#{line_num}")
    IO.puts("    #{String.trim(line)}")
    IO.puts("    → #{message}")
  end
end

ListAccessChecker.run()
