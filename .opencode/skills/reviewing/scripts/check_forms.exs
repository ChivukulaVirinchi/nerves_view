#!/usr/bin/env elixir

# Generic form pattern checker for any Elixir/Phoenix project.
#
# Checks:
# 1. <.form tags missing id= attribute (multi-line aware)
# 2. Bracket access on structs inside ~H""" template blocks
# 3. Map.put(:action, :validate) — should use to_form/2 with action: :validate
# 4. <.form with phx-submit but missing phx-change (multi-line aware)
# 5. for={@changeset} — should be for={@form}
# 6. Submit buttons missing phx-disable-with (prevents double-submission)

defmodule FormPatternChecker do
  @lib_root "lib"

  def run do
    web_root = find_web_root()

    if is_nil(web_root) do
      IO.puts("✅ No *_web directory found — skipping form checks")
      System.halt(0)
    end

    files = collect_files(web_root)

    results = %{
      missing_form_id: check_missing_form_id(files),
      bracket_on_struct: check_bracket_on_struct_in_templates(files),
      map_put_action: check_map_put_action(files),
      missing_phx_change: check_missing_phx_change(files),
      raw_changeset_in_form: check_raw_changeset_in_form(files),
      missing_disable_with: check_submit_disable_with(web_root)
    }

    any_issues =
      results
      |> Map.values()
      |> Enum.any?(&(&1 != []))

    if any_issues do
      print_check("Forms missing `id`", results.missing_form_id,
        "Forms need `id` for DOM patching and reconnect recovery. Add id={...} to <.form>.")

      print_check("Bracket access on structs in templates", results.bracket_on_struct,
        "Structs don't implement Access. Use `variable.field` instead of `variable[:field]`.")

      print_check("Map.put(:action, :validate) pattern", results.map_put_action,
        "Use `to_form(changeset, action: :validate)` instead of Map.put/changeset.action.")

      print_check("Forms with phx-submit but missing phx-change", results.missing_phx_change,
        "Forms need phx-change for live validation and reconnect recovery. Add phx-change={...}.")

      print_check("Raw changeset used in for={}", results.raw_changeset_in_form,
        "Use for={@form} (a Phoenix.HTML.Form struct), not for={@changeset} (a raw Changeset).")

      print_check("Submit buttons missing phx-disable-with", results.missing_disable_with,
        "Submit buttons need phx-disable-with to prevent double-submission during latency.")

      total =
        results
        |> Map.values()
        |> Enum.map(&length/1)
        |> Enum.sum()

      IO.puts("Total: #{total} violation(s)")
      System.halt(1)
    else
      IO.puts("✅ No form pattern violations found")
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
  # File collection
  # ---------------------------------------------------------------------------

  defp collect_files(web_root) do
    web_root
    |> Path.join("**/*.{ex,heex}")
    |> Path.wildcard()
  end

  # ---------------------------------------------------------------------------
  # Docstring detection — skip @moduledoc/@doc heredoc blocks
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Check 1: <.form tags missing id= (multi-line aware)
  # ---------------------------------------------------------------------------

  defp check_missing_form_id(files) do
    Enum.flat_map(files, fn file ->
      relative = Path.relative_to_cwd(file)
      content = File.read!(file)
      doc_lines = docstring_lines(content)

      # Use multi-line form tag extraction to check the full tag span
      find_form_tag_spans(content)
      |> Enum.flat_map(fn {tag_text, start_line} ->
        # Skip if the form tag starts inside a docstring
        if MapSet.member?(doc_lines, start_line) do
          []
        else
          has_id = Regex.match?(~r/\bid\s*[={]/, tag_text)

          if not has_id do
            first_line =
              tag_text
              |> String.split("\n")
              |> List.first()
              |> String.trim()

            [{relative, start_line, first_line}]
          else
            []
          end
        end
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Check 2: Bracket access on struct-like variables in ~H""" blocks
  # ---------------------------------------------------------------------------

  # Common struct variable names from Repo queries.
  # Projects can have different names, but these are universal Ecto patterns.
  @always_struct_vars ~w(user changeset record entry item)

  defp check_bracket_on_struct_in_templates(files) do
    Enum.flat_map(files, fn file ->
      relative = Path.relative_to_cwd(file)
      content = File.read!(file)

      # Check if this file declares :map typed attrs for common variable names
      map_typed_attrs = extract_map_typed_attrs(content)

      # Extract only ~H""" template blocks
      template_blocks = extract_template_blocks(content)

      Enum.flat_map(template_blocks, fn {block, base_line} ->
        block
        |> String.split("\n")
        |> Enum.with_index(base_line)
        |> Enum.flat_map(fn {line, line_num} ->
          # Match variable[:field] patterns
          case Regex.scan(~r/\b(\w+)\s*\[:\w+\]/, line, capture: :all) do
            [] ->
              []

            matches ->
              Enum.flat_map(matches, fn [_full, var_name] ->
                # Only flag if the variable is in our always-struct list
                # AND not declared as :map in this file's attrs
                if var_name in @always_struct_vars and var_name not in map_typed_attrs do
                  [{relative, line_num, String.trim(line)}]
                else
                  []
                end
              end)
          end
        end)
      end)
    end)
  end

  # Extract attr names that are typed :map or :list in this file
  defp extract_map_typed_attrs(content) do
    Regex.scan(~r/attr\s+:(\w+)\s*,\s*:(?:map|list)/, content, capture: :all)
    |> Enum.map(fn [_, name] -> name end)
  end

  # Returns [{block_content, starting_line_number}]
  defp extract_template_blocks(content) do
    lines = String.split(content, "\n")
    delimiter = ~S[~H"""]

    {blocks, _} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({[], nil}, fn {line, line_num}, {acc, state} ->
        case state do
          nil ->
            if String.contains?(line, delimiter) do
              {acc, {[], line_num + 1}}
            else
              {acc, nil}
            end

          {collected, start_line} ->
            if String.contains?(line, ~S["""]) and not String.contains?(line, delimiter) do
              block = Enum.reverse(collected) |> Enum.join("\n")
              {[{block, start_line} | acc], nil}
            else
              {acc, {[line | collected], start_line}}
            end
        end
      end)

    blocks
  end

  # ---------------------------------------------------------------------------
  # Check 3: Map.put(:action, :validate) pattern
  # ---------------------------------------------------------------------------

  defp check_map_put_action(files) do
    Enum.flat_map(files, fn file ->
      relative = Path.relative_to_cwd(file)
      content = File.read!(file)
      doc_lines = docstring_lines(content)

      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_num} ->
        trimmed = String.trim(line)

        # Skip comments and docstrings
        if String.starts_with?(trimmed, "#") or MapSet.member?(doc_lines, line_num) do
          []
        else
          cond do
            Regex.match?(~r/Map\.put\s*\(.*:action\s*,\s*:validate/, line) ->
              [{relative, line_num, trimmed}]

            Regex.match?(~r/%\{.*changeset.*\|\s*action:\s*:validate\s*\}/, line) ->
              [{relative, line_num, trimmed}]

            true -> []
          end
        end
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Check 4: <.form with phx-submit but missing phx-change (multi-line aware)
  # ---------------------------------------------------------------------------

  defp check_missing_phx_change(files) do
    Enum.flat_map(files, fn file ->
      relative = Path.relative_to_cwd(file)
      content = File.read!(file)
      doc_lines = docstring_lines(content)

      find_form_tag_spans(content)
      |> Enum.flat_map(fn {tag_text, start_line} ->
        # Skip if inside a docstring
        if MapSet.member?(doc_lines, start_line) do
          []
        else
          has_submit = Regex.match?(~r/phx-submit\s*=/, tag_text)
          has_change = Regex.match?(~r/phx-change\s*=/, tag_text)

          if has_submit and not has_change do
            first_line =
              tag_text
              |> String.split("\n")
              |> List.first()
              |> String.trim()

            [{relative, start_line, first_line}]
          else
            []
          end
        end
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Multi-line <.form> tag extraction (shared by checks 1 and 4)
  # ---------------------------------------------------------------------------

  # Extract the full tag text of each <.form ...> opening tag (potentially
  # spanning multiple lines), along with the line number where it starts.
  defp find_form_tag_spans(content) do
    lines = String.split(content, "\n")

    {spans, _, _, _} =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce({[], nil, [], 0}, fn {line, line_num},
                                          {acc, state, buffer, start_line} ->
        case state do
          nil ->
            if Regex.match?(~r/<\.form\b/, line) do
              if tag_closed?(line) do
                {[{line, line_num} | acc], nil, [], 0}
              else
                {acc, :collecting, [line], line_num}
              end
            else
              {acc, nil, [], 0}
            end

          :collecting ->
            new_buffer = buffer ++ [line]

            if tag_closed?(line) do
              tag_text = Enum.join(new_buffer, "\n")
              {[{tag_text, start_line} | acc], nil, [], 0}
            else
              {acc, :collecting, new_buffer, start_line}
            end
        end
      end)

    spans
  end

  defp tag_closed?(line) do
    trimmed = String.trim(line)
    String.ends_with?(trimmed, ">") or String.ends_with?(trimmed, "}>")
  end

  # ---------------------------------------------------------------------------
  # Check 5: for={@changeset} in templates
  # ---------------------------------------------------------------------------

  defp check_raw_changeset_in_form(files) do
    Enum.flat_map(files, fn file ->
      relative = Path.relative_to_cwd(file)

      file
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_num} ->
        if Regex.match?(~r/\bfor=\{@changeset\b/, line) or
             Regex.match?(~r/\bfor=\{changeset\b/, line) do
          [{relative, line_num, String.trim(line)}]
        else
          []
        end
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Check 6: Submit buttons missing phx-disable-with
  #
  # Strategy: extract each <button ...> and <.button ...> tag as a single
  # chunk (including any attributes that span multiple lines), then check
  # whether the chunk contains both type="submit" and phx-disable-with.
  # ---------------------------------------------------------------------------

  defp check_submit_disable_with(web_root) do
    issues =
      web_root
      |> Path.join("**/*.{ex,heex}")
      |> Path.wildcard()
      |> Enum.flat_map(&check_file_disable_with/1)

    if issues == [] do
      IO.puts("✅ phx-disable-with: all submit buttons protected")
    end

    issues
  end

  defp check_file_disable_with(file) do
    content = File.read!(file)
    relative = Path.relative_to_cwd(file)

    # Find every opening tag for <button and <.button.
    # We scan for the tag opener, then grab characters until the first lone >
    # that isn't inside a {...} expression. This gives us the attribute section.
    extract_button_tag_chunks(content)
    |> Enum.flat_map(fn {chunk, char_offset} ->
      if submit_button_without_disable_with?(chunk) do
        line_num = char_offset_to_line(content, char_offset)
        # First non-empty line of the chunk as the display snippet
        snippet =
          chunk
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.find("", &(&1 != ""))

        [{relative, line_num, snippet}]
      else
        []
      end
    end)
  end

  # Returns [{chunk_string, start_char_offset}]
  defp extract_button_tag_chunks(content) do
    # Match the start of a <button or <.button opening tag
    tag_open_regex = ~r/<\.?button\b/

    content
    |> scan_all_positions(tag_open_regex)
    |> Enum.map(fn start_pos ->
      chunk = extract_tag_from(content, start_pos)
      {chunk, start_pos}
    end)
  end

  # Returns all starting byte positions where the regex matches
  defp scan_all_positions(content, regex) do
    scan_all_positions(content, regex, 0, [])
  end

  defp scan_all_positions(content, regex, offset, acc) do
    slice = binary_slice(content, offset, byte_size(content) - offset)

    case Regex.run(regex, slice, return: :index) do
      [{rel_pos, _len}] ->
        abs_pos = offset + rel_pos
        scan_all_positions(content, regex, abs_pos + 1, [abs_pos | acc])

      nil ->
        Enum.reverse(acc)
    end
  end

  # Extract from content[start..] up to the first `>` that closes the tag,
  # ignoring `>` characters inside `{...}` Elixir expressions.
  defp extract_tag_from(content, start) do
    rest = binary_slice(content, start, byte_size(content) - start)
    extract_tag_chars(rest, 0, [])
  end

  defp extract_tag_chars(<<>>, _depth, acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp extract_tag_chars(<<"{", rest::binary>>, depth, acc),
    do: extract_tag_chars(rest, depth + 1, ["{" | acc])

  defp extract_tag_chars(<<"}", rest::binary>>, depth, acc) when depth > 0,
    do: extract_tag_chars(rest, depth - 1, ["}" | acc])

  defp extract_tag_chars(<<">", _rest::binary>>, 0, acc),
    do: IO.iodata_to_binary(Enum.reverse([">" | acc]))

  defp extract_tag_chars(<<c::binary-size(1), rest::binary>>, depth, acc),
    do: extract_tag_chars(rest, depth, [c | acc])

  defp submit_button_without_disable_with?(chunk) do
    has_submit = String.contains?(chunk, ~s|type="submit"|)
    has_disable_with = String.contains?(chunk, "phx-disable-with")
    has_submit and not has_disable_with
  end

  defp char_offset_to_line(content, offset) do
    content
    |> binary_slice(0, offset)
    |> String.split("\n")
    |> length()
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

FormPatternChecker.run()
