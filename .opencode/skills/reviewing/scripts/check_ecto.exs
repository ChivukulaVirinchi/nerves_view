#!/usr/bin/env elixir

# Checks for common Ecto anti-patterns in any Elixir/Phoenix project:
# 1. N+1-QUERY         — Repo.get/one/all inside Enum.map/each/filter/flat_map blocks
# 2. MISSING-ON-DELETE — references() in migrations without on_delete:
# 3. FLOAT-FOR-MONEY   — :float type on money-related field names (use :decimal or integer cents)
# 4. UNSAFE-FRAGMENT   — String interpolation inside Ecto fragment() calls (SQL injection)
# 5. RAW-SQL-INTERP    — String interpolation inside Repo.query/Repo.query! calls

defmodule EctoPatternChecker do
  @lib_root "lib"
  @migrations_root "priv/repo/migrations"

  def run do
    n_plus_one     = check_n_plus_one()
    missing_delete = check_missing_on_delete()
    float_money    = check_float_for_money()
    unsafe_frag    = check_unsafe_fragment_interpolation()
    raw_sql        = check_raw_sql_interpolation()

    all_issues =
      n_plus_one ++
      missing_delete ++
      float_money ++
      unsafe_frag ++
      raw_sql

    if all_issues == [] do
      IO.puts("✅ No Ecto pattern violations found")
    else
      Enum.each(all_issues, &print_issue/1)
      IO.puts("Total: #{length(all_issues)} violation(s)")
      System.halt(1)
    end
  end

  # ---------------------------------------------------------------------------
  # 1. N+1 query — Repo.get/one/all inside Enum.map/each/filter/flat_map blocks
  # ---------------------------------------------------------------------------

  defp check_n_plus_one do
    issues =
      app_files()
      |> Enum.flat_map(&check_n_plus_one_file/1)

    if issues == [] do
      IO.puts("✅ N+1 queries: no Repo calls detected inside Enum iteration blocks")
    end

    issues
  end

  # Detects N+1 queries: Repo.get/one/all/preload called INSIDE an Enum callback.
  #
  # Three heuristics reduce false positives:
  #
  # 1. Skip ID-extraction Enum calls — lines like `Enum.map(items, & &1.id)` or
  #    `Enum.map(items, fn x -> x.id end)` only extract scalars from an already-
  #    loaded list, so they cannot cause an N+1.
  #
  # 2. Require the Repo call to be at DEEPER indentation than the Enum line —
  #    this approximates "the Repo call is inside the fn callback", not sequential
  #    code that happens to follow the Enum call.
  #
  # 3. Skip batch queries — if the Repo call line contains `in ^` it is using an
  #    IN clause with a pinned list, which is the correct batch-loading pattern,
  #    not an N+1.
  defp check_n_plus_one_file(file) do
    relative = Path.relative_to_cwd(file)
    content = File.read!(file)
    doc_lines = docstring_lines(content)

    lines =
      content
      |> String.split("\n")
      |> Enum.with_index(1)

    line_index =
      lines
      |> Enum.into(%{}, fn {line, num} -> {num, line} end)

    total_lines = length(lines)

    # Collect Enum.*/2 call sites that are NOT simple ID extractions.
    enum_starts =
      lines
      |> Enum.flat_map(fn {line, line_num} ->
        trimmed = String.trim(line)

        cond do
          String.starts_with?(trimmed, "#") -> []
          MapSet.member?(doc_lines, line_num) -> []
          not Regex.match?(~r/\bEnum\.(map|each|filter|flat_map|reduce)\b/, trimmed) -> []
          # Skip ID-extraction patterns like `& &1.id` or `fn x -> x.id end`
          Regex.match?(~r/Enum\.\w+\([^,]+,\s*(&\s*&1\.\w+|fn\s+\w+\s*->\s*\w+\.\w+\s*end)\s*\)/, trimmed) -> []
          true -> [{line_num, leading_spaces(line)}]
        end
      end)

    Enum.flat_map(enum_starts, fn {enum_line, enum_indent} ->
      window_end = min(enum_line + 10, total_lines)

      # Build the window of lines to inspect, stopping at any function definition
      # boundary (def/defp). Crossing into a new function means the Repo call
      # cannot be inside the original Enum callback.
      window_lines =
        (enum_line + 1)..window_end
        |> Enum.reduce_while([], fn ln, acc ->
          raw_line = Map.get(line_index, ln, "")
          trimmed = String.trim(raw_line)

          if Regex.match?(~r/^\s*(defp?|defmacrop?)\s+\w/, raw_line) do
            {:halt, acc}
          else
            {:cont, [{ln, raw_line, trimmed} | acc]}
          end
        end)
        |> Enum.reverse()

      Enum.flat_map(window_lines, fn {ln, raw_line, trimmed} ->
        cond do
          String.starts_with?(trimmed, "#") -> []
          MapSet.member?(doc_lines, ln) -> []
          not Regex.match?(~r/\bRepo\.(get|get!|one|one!|all|preload)\b/, trimmed) -> []
          # Repo call must be INSIDE the callback (deeper indentation)
          leading_spaces(raw_line) <= enum_indent -> []
          # Batch query with IN clause is not an N+1.
          # Check the Repo line itself and the preceding few lines (for multi-line
          # pipe queries where `in ^` appears inside the from/where block).
          batch_query_nearby?(line_index, ln) -> []
          true ->
            [{:n_plus_one, relative, ln,
              "Repo call inside Enum iteration (line #{enum_line}) — preload associations instead of fetching in a loop",
              raw_line}]
        end
      end)
    end)
    |> Enum.uniq_by(fn {_, _, ln, _, _} -> ln end)
    |> Enum.sort_by(fn {_, _, ln, _, _} -> ln end)
  end

  # Returns the number of leading spaces (treating each tab as one unit).
  defp leading_spaces(line) do
    line
    |> String.to_charlist()
    |> Enum.take_while(&(&1 in [?\s, ?\t]))
    |> length()
  end

  # Returns true if the Repo call at `ln` is part of a batch (IN-clause) query.
  #
  # We search a window of 10 lines both before and after the Repo call line.
  # This covers two common layouts:
  #   - Pipe style:  the `in ^ids` WHERE clause is in preceding lines, and the
  #     `|> Repo.all()` terminus is the last line of the pipe chain.
  #   - Inline style: `Repo.all(from(..., where: x in ^ids, ...))` — the `in ^`
  #     appears on lines that follow the opening `Repo.all(` line.
  defp batch_query_nearby?(line_index, ln) do
    ln_start = max(1, ln - 10)
    total = map_size(line_index)
    ln_end = min(ln + 10, total)

    ln_start..ln_end
    |> Enum.any?(fn n ->
      line = Map.get(line_index, n, "")
      String.contains?(line, "in ^")
    end)
  end

  # ---------------------------------------------------------------------------
  # 2. Missing on_delete: in migration references()
  # ---------------------------------------------------------------------------

  defp check_missing_on_delete do
    issues =
      migration_files()
      |> Enum.flat_map(&check_missing_on_delete_file/1)

    if issues == [] do
      IO.puts("✅ on_delete: all references() in migrations include on_delete:")
    end

    issues
  end

  defp check_missing_on_delete_file(file) do
    relative = Path.relative_to_cwd(file)

    lines =
      file
      |> File.read!()
      |> String.split("\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      trimmed = String.trim(line)

      # Skip comments
      if String.starts_with?(trimmed, "#") do
        []
      else
        # Match: add :something_id, references(  OR  modify :something_id, references(
        if Regex.match?(~r/\b(add|modify)\s+:\w+_id\s*,\s*references\s*\(/, trimmed) do
          # Check if on_delete: is on the same line
          if String.contains?(trimmed, "on_delete:") do
            []
          else
            # Look one line ahead for on_delete: (multi-line references call)
            next_line = Enum.at(lines, line_num) || ""

            if String.contains?(next_line, "on_delete:") do
              []
            else
              [{:missing_on_delete, relative, line_num,
                "references() without on_delete: — specify on_delete: :delete_all, :nilify_all, or :restrict",
                line}]
            end
          end
        else
          []
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # 3. Float type for money-related fields
  # ---------------------------------------------------------------------------

  @money_field_pattern ~r/\b(price|amount|cost|total|balance|fee|discount|tax|revenue|salary|wage|rate|charge|payment|refund|credit|debit)\b/i

  defp check_float_for_money do
    migration_issues =
      migration_files()
      |> Enum.flat_map(&check_float_money_file(&1, :migration))

    schema_issues =
      app_files()
      |> Enum.flat_map(&check_float_money_file(&1, :schema))

    issues = migration_issues ++ schema_issues

    if issues == [] do
      IO.puts("✅ Float-for-money: no :float used on monetary fields (using :decimal or integer cents)")
    end

    issues
  end

  defp check_float_money_file(file, source) do
    relative = Path.relative_to_cwd(file)

    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      trimmed = String.trim(line)

      if String.starts_with?(trimmed, "#") do
        []
      else
        has_money_name = Regex.match?(@money_field_pattern, trimmed)
        has_float_type =
          case source do
            # Migration: add :price, :float  OR  add :price_cents, :float
            :migration -> Regex.match?(~r/\b(add|modify)\s+:\w+\s*,\s*:float\b/, trimmed)
            # Schema:    field :price, :float
            :schema    -> Regex.match?(~r/\bfield\s+:\w+\s*,\s*:float\b/, trimmed)
          end

        if has_money_name and has_float_type do
          [{:float_for_money, relative, line_num,
            "Monetary field uses :float — use :decimal for exactness or :integer (store cents) instead",
            line}]
        else
          []
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # 4. Unsafe fragment interpolation — fragment("...#{...}")
  # ---------------------------------------------------------------------------

  defp check_unsafe_fragment_interpolation do
    issues =
      app_files()
      |> Enum.flat_map(&check_unsafe_fragment_file/1)

    if issues == [] do
      IO.puts("✅ Fragment interpolation: no string interpolation found inside fragment() calls")
    end

    issues
  end

  defp check_unsafe_fragment_file(file) do
    relative = Path.relative_to_cwd(file)
    content = File.read!(file)
    doc_lines = docstring_lines(content)

    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      trimmed = String.trim(line)

      if String.starts_with?(trimmed, "#") or MapSet.member?(doc_lines, line_num) do
        []
      else
        # Match: fragment("...#{  or  fragment(~s"...#{  or  fragment(~S"...#{
        if Regex.match?(~r/\bfragment\s*\(\s*(~[sS])?"[^"]*#\{/, trimmed) do
          [{:unsafe_fragment, relative, line_num,
            "String interpolation inside fragment() is a SQL injection risk — use fragment(\"? = ?\", value) with parameters instead",
            line}]
        else
          []
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # 5. Raw SQL interpolation — Repo.query("...#{  or  Repo.query!("...#{
  # ---------------------------------------------------------------------------

  defp check_raw_sql_interpolation do
    issues =
      app_files()
      |> Enum.flat_map(&check_raw_sql_file/1)

    if issues == [] do
      IO.puts("✅ Raw SQL interpolation: no string interpolation found inside Repo.query calls")
    end

    issues
  end

  defp check_raw_sql_file(file) do
    relative = Path.relative_to_cwd(file)
    content = File.read!(file)
    doc_lines = docstring_lines(content)

    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      trimmed = String.trim(line)

      if String.starts_with?(trimmed, "#") or MapSet.member?(doc_lines, line_num) do
        []
      else
        if Regex.match?(~r/\bRepo\.query!?\s*\(\s*"[^"]*#\{/, trimmed) do
          [{:raw_sql_interp, relative, line_num,
            "String interpolation inside Repo.query is a SQL injection risk — use parameterised queries with $1, $2, ... placeholders instead",
            line}]
        else
          []
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Docstring detection — skip @moduledoc/@doc heredoc blocks
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # File helpers
  # ---------------------------------------------------------------------------

  defp app_files do
    # Scan all .ex files under lib/ (covers both app and web directories)
    @lib_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
  end

  defp migration_files do
    @migrations_root
    |> Path.join("**/*.exs")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
  end

  # ---------------------------------------------------------------------------
  # Output
  # ---------------------------------------------------------------------------

  defp print_issue({type, file, line_num, message, line}) do
    label =
      case type do
        :n_plus_one       -> "N+1-QUERY"
        :missing_on_delete -> "MISSING-ON-DELETE"
        :float_for_money  -> "FLOAT-FOR-MONEY"
        :unsafe_fragment  -> "UNSAFE-FRAGMENT-INTERPOLATION"
        :raw_sql_interp   -> "RAW-SQL-INTERPOLATION"
      end

    IO.puts("  ❌ [#{label}] #{file}:#{line_num}")
    IO.puts("    #{String.trim(line)}")
    IO.puts("    → #{message}\n")
  end
end

EctoPatternChecker.run()
