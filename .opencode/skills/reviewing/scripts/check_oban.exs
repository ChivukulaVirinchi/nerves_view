#!/usr/bin/env elixir

# Checks for common Oban worker anti-patterns in any Elixir/Phoenix project:
#
# 1. ATOM-KEYS-IN-ARGS  — .new(%{atom_key: value}) instead of string keys
# 2. STRUCT-IN-ARGS     — structs passed directly into job args
# 3. MISSING-IMPL       — def perform/1 without @impl Oban.Worker / @impl true
# 4. BARE-OK-RETURN     — perform/1 with no error handling (no case/with/{:error)

defmodule ObanPatternChecker do
  @lib_root "lib"

  def run do
    files = collect_worker_files()

    if files == [] do
      IO.puts("✅ No Oban worker files found — skipping Oban checks")
      System.halt(0)
    end

    results = %{
      atom_keys_in_args: check_atom_keys_in_args(files),
      struct_in_args: check_struct_in_args(files),
      missing_impl: check_missing_impl(files),
      bare_ok_return: check_bare_ok_return(files)
    }

    any_issues =
      results
      |> Map.values()
      |> Enum.any?(&(&1 != []))

    if any_issues do
      print_check("Atom keys in Oban args", results.atom_keys_in_args,
        "Oban serializes args to JSON — atom keys become strings after round-trip. Use string keys: %{\"key\" => value}.")

      print_check("Struct in Oban args", results.struct_in_args,
        "Structs cannot survive JSON serialization. Pass IDs and reload from the database inside perform/1.")

      print_check("perform/1 missing @impl", results.missing_impl,
        "Every def perform/1 in an Oban worker must be preceded by @impl Oban.Worker or @impl true.")

      print_check("perform/1 with no error handling", results.bare_ok_return,
        "perform/1 that never returns {:error, _} or uses case/with hides failures. Add explicit error handling.")

      total =
        results
        |> Map.values()
        |> Enum.map(&length/1)
        |> Enum.sum()

      IO.puts("Total: #{total} violation(s)")
      System.halt(1)
    else
      IO.puts("✅ No Oban pattern violations found")
    end
  end

  # ---------------------------------------------------------------------------
  # File collection — find Oban worker files dynamically
  # ---------------------------------------------------------------------------
  # Strategy: scan all .ex files under lib/ and identify those that
  # `use Oban.Worker` — this works regardless of directory structure.

  defp collect_worker_files do
    all_ex_files =
      @lib_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()

    Enum.filter(all_ex_files, fn file ->
      content = File.read!(file)
      String.contains?(content, "use Oban.Worker")
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
  # Check 1: Atom keys in Oban job args
  #
  # Catches patterns like:
  #   MyWorker.new(%{user_id: 1, action: "send"})
  #   %{user_id: id} |> MyWorker.new()
  #
  # We look for `.new(%{` or `|> new(` where the map contains `: ` atom-key
  # syntax on the same line or within the following 5 lines (multi-line maps).
  # ---------------------------------------------------------------------------

  defp check_atom_keys_in_args(files) do
    Enum.flat_map(files, fn file ->
      relative = Path.relative_to_cwd(file)
      content = File.read!(file)
      doc_lines = docstring_lines(content)
      lines = String.split(content, "\n")

      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_num} ->
        trimmed = String.trim(line)

        if String.starts_with?(trimmed, "#") or MapSet.member?(doc_lines, line_num) do
          []
        else
          # Detect opening of a new() call with a map argument
          is_new_call =
            Regex.match?(~r/\.new\s*\(%\{/, line) or
              Regex.match?(~r/\|>\s*new\s*\(/, line)

          if not is_new_call do
            []
          else
            # Collect this line + up to 5 following lines to handle multi-line maps
            window =
              lines
              |> Enum.drop(line_num - 1)
              |> Enum.take(6)
              |> Enum.join("\n")

            # Atom key: identifier followed by colon and a space/value (not :: which is type spec)
            # Matches: user_id: value  but not "key": value or key => value
            if Regex.match?(~r/\b[a-z_][a-zA-Z0-9_]*:\s+[^:]/, window) do
              [{relative, line_num, trimmed}]
            else
              []
            end
          end
        end
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Check 2: Struct passed in Oban args
  #
  # Catches patterns like:
  #   MyWorker.new(%{user: %User{...}})
  #   MyWorker.new(%{config: %MyApp.Config{...}})
  #   MyWorker.new(%{data: %{__struct__: ...}})
  # ---------------------------------------------------------------------------

  defp check_struct_in_args(files) do
    Enum.flat_map(files, fn file ->
      relative = Path.relative_to_cwd(file)
      content = File.read!(file)
      doc_lines = docstring_lines(content)
      lines = String.split(content, "\n")

      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_num} ->
        trimmed = String.trim(line)

        if String.starts_with?(trimmed, "#") or MapSet.member?(doc_lines, line_num) do
          []
        else
          is_new_call =
            Regex.match?(~r/\.new\s*\(%\{/, line) or
              Regex.match?(~r/\|>\s*new\s*\(/, line)

          if not is_new_call do
            []
          else
            # Collect window around the new() call
            window =
              lines
              |> Enum.drop(line_num - 1)
              |> Enum.take(6)
              |> Enum.join("\n")

            cond do
              # %SomeModule.Something{ — any struct literal inside the map
              Regex.match?(~r/%[A-Z][A-Za-z0-9_.]*\{/, window) ->
                [{relative, line_num, trimmed}]

              # %{__struct__: ...} pattern (explicit struct map)
              Regex.match?(~r/%\{__struct__/, window) ->
                [{relative, line_num, trimmed}]

              true ->
                []
            end
          end
        end
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Check 3: def perform/1 without @impl
  #
  # In Elixir, @impl is only required on the FIRST clause of a multi-clause
  # function. We check per file: find the first `def perform(` and verify it
  # has @impl immediately before it. Subsequent clauses are not flagged.
  # ---------------------------------------------------------------------------

  defp check_missing_impl(files) do
    Enum.flat_map(files, fn file ->
      relative = Path.relative_to_cwd(file)
      content = File.read!(file)
      lines = String.split(content, "\n")

      # Find only the first perform/1 clause in this file
      first_perform =
        lines
        |> Enum.with_index(1)
        |> Enum.find(fn {line, _line_num} ->
          Regex.match?(~r/^\s*def perform\(/, line)
        end)

      case first_perform do
        nil ->
          []

        {line, line_num} ->
          trimmed = String.trim(line)

          preceding_impl =
            lines
            |> Enum.take(line_num - 1)
            |> Enum.reverse()
            |> Enum.find(fn l ->
              t = String.trim(l)
              t != "" and not String.starts_with?(t, "#")
            end)
            |> case do
              nil -> false
              prev ->
                t = String.trim(prev)
                t == "@impl Oban.Worker" or t == "@impl true"
            end

          if preceding_impl do
            []
          else
            [{relative, line_num, trimmed}]
          end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Check 4: perform/1 with no error handling
  #
  # Extracts the body of each perform/1 function and checks whether it
  # contains any of: `{:error`, `case `, `with `. Workers that lack these
  # patterns will silently swallow failures.
  #
  # Detection strategy: collect lines from `def perform(` up to the matching
  # `end` (tracking nested def/do/end depth).
  # ---------------------------------------------------------------------------

  defp check_bare_ok_return(files) do
    Enum.flat_map(files, fn file ->
      relative = Path.relative_to_cwd(file)
      content = File.read!(file)
      doc_lines = docstring_lines(content)
      lines = String.split(content, "\n") |> Enum.with_index(1)

      extract_perform_bodies(lines, doc_lines)
      |> Enum.flat_map(fn {body_lines, start_line, header} ->
        body_text = Enum.join(body_lines, "\n")

        has_error_handling =
          String.contains?(body_text, "{:error") or
            Regex.match?(~r/\bcase\s+/, body_text) or
            Regex.match?(~r/\bwith\s+/, body_text)

        if has_error_handling do
          []
        else
          [{relative, start_line, String.trim(header)}]
        end
      end)
    end)
  end

  # Returns [{body_lines, start_line_num, header_line}]
  defp extract_perform_bodies(indexed_lines, doc_lines) do
    {bodies, _} =
      Enum.reduce(indexed_lines, {[], nil}, fn {line, line_num}, {acc, state} ->
        trimmed = String.trim(line)

        case state do
          nil ->
            if Regex.match?(~r/^\s*def perform\(/, line) and
                 not MapSet.member?(doc_lines, line_num) do
              # Determine starting depth: single-line `def perform(...), do: expr` has depth 0
              if String.contains?(trimmed, ", do:") or Regex.match?(~r/\bdo:\s*\S/, trimmed) do
                # Single-line function — treat as body with no block
                {[{[line], line_num, line} | acc], nil}
              else
                {acc, {[line], line_num, line, 1}}
              end
            else
              {acc, nil}
            end

          {collected, start_line, header, depth} ->
            # Count depth changes on this line (do/end, def/end, fn/end)
            added =
              length(Regex.scan(~r/\b(do|fn)\b/, trimmed)) -
                length(Regex.scan(~r/\bend\b/, trimmed))

            new_depth = depth + added
            new_collected = collected ++ [line]

            if new_depth <= 0 do
              {[{new_collected, start_line, header} | acc], nil}
            else
              {acc, {new_collected, start_line, header, new_depth}}
            end
        end
      end)

    bodies
  end

  # ---------------------------------------------------------------------------
  # Output helpers
  # ---------------------------------------------------------------------------

  defp print_check(_label, [], _explanation), do: :ok

  defp print_check(label, issues, explanation) do
    IO.puts("\n❌ [#{String.upcase(label)}] #{length(issues)} issue(s)\n   #{explanation}\n")

    Enum.each(issues, fn {file, line_num, line} ->
      IO.puts("   #{file}:#{line_num}")
      IO.puts("     #{line}\n")
    end)
  end
end

ObanPatternChecker.run()
