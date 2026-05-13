#!/usr/bin/env elixir

# Checks for overly complex `with` expressions (7+ arrow clauses).
#
# Long `with` chains signal a function doing too much — extract steps into
# named private functions or use Ecto.Multi for DB operations.
# Source: implementing/critical-patterns.md §5.10.4
#
# Checks:
# 1. with expressions containing 7 or more <- arrows

defmodule WithComplexityChecker do
  @lib_root "lib"
  @max_arrows 6

  def run do
    issues =
      @lib_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&skip_file?/1)
      |> Enum.flat_map(&check_file/1)

    if issues == [] do
      IO.puts("✅ No overly complex `with` expressions found (threshold: >#{@max_arrows} arrows)")
    else
      Enum.each(issues, &print_issue/1)
      IO.puts("\nTotal: #{length(issues)} complex `with` expression(s)")
      System.halt(1)
    end
  end

  defp skip_file?(file) do
    String.contains?(file, "_test.exs") or
      String.contains?(file, "/test/") or
      String.contains?(file, "/migrations/") or
      String.contains?(file, "/priv/")
  end

  defp check_file(file) do
    relative = Path.relative_to_cwd(file)
    content = File.read!(file)
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> find_with_blocks(relative, lines)
  end

  defp find_with_blocks(indexed_lines, file, all_lines) do
    indexed_lines
    |> Enum.flat_map(fn {line, line_num} ->
      trimmed = String.trim(line)

      cond do
        String.starts_with?(trimmed, "#") -> []

        # Match the start of a with expression
        Regex.match?(~r/^\s*with\s/, line) ->
          arrow_count = count_with_arrows(all_lines, line_num - 1)

          # Check for suppression comment
          has_suppression = line_num > 1 and
            String.contains?(Enum.at(all_lines, line_num - 2, ""), "with-complexity:allow")

          if arrow_count > @max_arrows and not has_suppression do
            [{:complex_with, file, line_num, arrow_count,
              "`with` has #{arrow_count} arrows (max #{@max_arrows}) — extract steps into named functions",
              line}]
          else
            []
          end

        true -> []
      end
    end)
  end

  defp count_with_arrows(lines, start_idx) do
    lines
    |> Enum.drop(start_idx)
    |> Enum.take(50)
    |> Enum.reduce_while(0, fn line, count ->
      trimmed = String.trim(line)

      cond do
        # Stop at the do block
        trimmed == "do" or String.ends_with?(trimmed, " do") ->
          {:halt, count}

        # Count arrow clauses
        String.contains?(line, "<-") ->
          {:cont, count + 1}

        true ->
          {:cont, count}
      end
    end)
  end

  defp print_issue({:complex_with, file, line_num, arrow_count, message, line}) do
    IO.puts("  ❌ [COMPLEX-WITH] #{file}:#{line_num} (#{arrow_count} arrows)")
    IO.puts("    #{String.trim(line)}")
    IO.puts("    → #{message}")
    IO.puts("    Suppress: Add # with-complexity:allow on the line above")
  end
end

WithComplexityChecker.run()
