#!/usr/bin/env elixir

# Generic LiveView antipattern checker for any Elixir/Phoenix project.
#
# Checks:
# 1. Deprecated phx-update="append"/"prepend" (use streams)
# 2. List assigns for collections in LiveView mount (use stream/3 instead)
# 3. Streams used as enumerables (streams can't be enumerated)
# 4. Missing connected? guard on side effects in mount
# 5. :let on <.form> in LiveView (bypasses change tracking)
# 6. Map.put on assigns in validate handlers (mutates Ecto structs, breaks changesets)

defmodule LiveViewAntipatterns do
  @lib_root "lib"

  def run do
    web_root = find_web_root()

    if is_nil(web_root) do
      IO.puts("✅ No *_web directory found — skipping LiveView checks")
      System.halt(0)
    end

    live_root = find_live_root(web_root)

    deprecated_update   = check_deprecated_phx_update(web_root)
    list_assigns        = check_list_assigns_in_mount(live_root)
    stream_enumerated   = check_streams_as_enumerables(web_root)
    missing_connected   = check_missing_connected_guard(live_root)
    form_let            = check_form_let_in_liveview(live_root)
    struct_mutation     = check_struct_mutation_in_validate(live_root)

    all_issues =
      deprecated_update ++
      list_assigns ++
      stream_enumerated ++
      missing_connected ++
      form_let ++
      struct_mutation

    if all_issues == [] do
      IO.puts("✅ No LiveView antipatterns found")
    else
      Enum.each(all_issues, &print_issue/1)
      IO.puts("Total: #{length(all_issues)} violation(s)")
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

  defp find_live_root(web_root) do
    candidate = Path.join(web_root, "live")

    if File.dir?(candidate) do
      candidate
    else
      # Fall back to web root if no live/ subdirectory
      web_root
    end
  end

  # ---------------------------------------------------------------------------
  # 1. Deprecated phx-update="append" / phx-update="prepend"
  # ---------------------------------------------------------------------------

  defp check_deprecated_phx_update(web_root) do
    issues =
      web_files(web_root, ["**/*.ex", "**/*.heex"])
      |> Enum.flat_map(&scan_lines(&1, ~r/phx-update="(append|prepend)"/, :deprecated_phx_update,
           "phx-update=\"append\"/\"prepend\" is deprecated — use phx-update=\"stream\" with stream/3 instead"))

    if issues == [] do
      IO.puts("✅ Deprecated phx-update: none found")
    end

    issues
  end

  # ---------------------------------------------------------------------------
  # 2. List assigns for collections in LiveView mount
  # ---------------------------------------------------------------------------

  defp check_list_assigns_in_mount(live_root) do
    issues =
      live_files(live_root)
      |> Enum.flat_map(&check_list_assigns_file/1)

    if issues == [] do
      IO.puts("✅ Collection list assigns: none found (mount functions use stream/3)")
    end

    issues
  end

  defp check_list_assigns_file(file) do
    content = File.read!(file)
    relative = Path.relative_to_cwd(file)

    # Find mount function bodies (between "def mount" and the next "def " or end of file)
    mount_blocks = extract_mount_blocks(content)

    Enum.flat_map(mount_blocks, fn {block, start_line} ->
      block
      |> String.split("\n")
      |> Enum.with_index(start_line)
      |> Enum.flat_map(fn {line, line_num} ->
        trimmed = String.trim(line)
        # Skip comments
        if String.starts_with?(trimmed, "#") do
          []
        else
          # Pattern 1: assign(socket, items: [...]) or assign(socket, items: get_items())
          # Pattern 2: assign(socket, :items, [...]) or assign(socket, :items, get_items())
          # We look for plural assign keys that suggest collections
          cond do
            Regex.match?(~r/assign\(\s*socket\s*,\s*(\w+):\s*(\[|list_|get_|all_|fetch_|load_)/, trimmed) ->
              case Regex.run(~r/assign\(\s*socket\s*,\s*(\w+):/, trimmed) do
                [_, key] when byte_size(key) > 1 ->
                  if looks_like_collection_key?(key) do
                    [{:list_assign, relative, line_num,
                      "assign(socket, #{key}: ...) for a collection — use stream(socket, :#{key}, ...) instead",
                      line}]
                  else
                    []
                  end
                _ -> []
              end

            Regex.match?(~r/assign\(\s*socket\s*,\s*:\w+\s*,\s*(\[|list_|get_|all_|fetch_|load_)/, trimmed) ->
              case Regex.run(~r/assign\(\s*socket\s*,\s*:(\w+)\s*,/, trimmed) do
                [_, key] ->
                  if looks_like_collection_key?(key) do
                    [{:list_assign, relative, line_num,
                      "assign(socket, :#{key}, ...) for a collection — use stream(socket, :#{key}, ...) instead",
                      line}]
                  else
                    []
                  end
                _ -> []
              end

            true -> []
          end
        end
      end)
    end)
  end

  # Heuristic: plural keys or common collection-naming patterns suggest a list
  defp looks_like_collection_key?(key) do
    # Ends in 's' (plural), or common patterns like 'list', 'items', 'results', 'entries'
    String.ends_with?(key, "s") or
      String.ends_with?(key, "_list") or
      String.ends_with?(key, "_items") or
      String.ends_with?(key, "_results") or
      String.ends_with?(key, "_entries") or
      String.ends_with?(key, "_records")
  end

  # ---------------------------------------------------------------------------
  # 3. Streams used as enumerables
  # ---------------------------------------------------------------------------

  defp check_streams_as_enumerables(web_root) do
    issues =
      web_files(web_root, ["**/*.ex", "**/*.heex"])
      |> Enum.flat_map(&check_stream_enum_file/1)

    if issues == [] do
      IO.puts("✅ Stream enumeration: no streams used as enumerables")
    end

    issues
  end

  defp check_stream_enum_file(file) do
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
        # Matches: Enum.count(@streams, Enum.filter(@streams, Enum.map(@streams, length(@streams
        if Regex.match?(~r/(Enum\.(count|filter|map|reduce|each|reject|find|sort|group_by)|length)\(@streams/, trimmed) do
          [{:stream_enum, relative, line_num,
            "Streams cannot be enumerated — use a regular assign list or query the collection directly",
            line}]
        else
          []
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # 4. Missing connected? guard on side effects in mount
  # ---------------------------------------------------------------------------

  defp check_missing_connected_guard(live_root) do
    issues =
      live_files(live_root)
      |> Enum.flat_map(&check_connected_guard_file/1)

    if issues == [] do
      IO.puts("✅ connected? guards: all side effects in mount appear guarded")
    end

    issues
  end

  defp check_connected_guard_file(file) do
    content = File.read!(file)
    relative = Path.relative_to_cwd(file)

    mount_blocks = extract_mount_blocks(content)

    side_effect_pattern = ~r/(send\s*\(\s*self\(\)|Process\.send_after|Phoenix\.PubSub\.subscribe)/

    Enum.flat_map(mount_blocks, fn {block, start_line} ->
      has_side_effect = Regex.match?(side_effect_pattern, block)
      has_connected_guard = String.contains?(block, "connected?(socket)")

      if has_side_effect and not has_connected_guard do
        # Find the first line in the block that has a side effect to report it
        block
        |> String.split("\n")
        |> Enum.with_index(start_line)
        |> Enum.flat_map(fn {line, line_num} ->
          trimmed = String.trim(line)
          if String.starts_with?(trimmed, "#") do
            []
          else
            if Regex.match?(side_effect_pattern, trimmed) do
              [{:missing_connected, relative, line_num,
                "Side effect in mount without connected?(socket) guard — triggers twice (once per disconnected render)",
                line}]
            else
              []
            end
          end
        end)
        |> Enum.take(1)  # Only report once per mount block
      else
        []
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # 5. :let on <.form> in LiveView
  # ---------------------------------------------------------------------------

  defp check_form_let_in_liveview(live_root) do
    issues =
      live_files(live_root)
      |> Enum.flat_map(&scan_lines(&1, ~r/<\.form\s[^>]*:let=\{/, :form_let,
           "<.form :let={...}> in LiveView bypasses change tracking — use .input components with @form instead"))

    if issues == [] do
      IO.puts("✅ Form :let usage: no <.form :let={}> found in LiveView files")
    end

    issues
  end

  # ---------------------------------------------------------------------------
  # 6. Map.put on assigns in validate handlers (struct mutation)
  # ---------------------------------------------------------------------------

  defp check_struct_mutation_in_validate(live_root) do
    issues =
      live_files(live_root)
      |> Enum.flat_map(&check_struct_mutation_file/1)

    if issues == [] do
      IO.puts("✅ Validate handlers: no struct mutation via Map.put found")
    end

    issues
  end

  defp check_struct_mutation_file(file) do
    content = File.read!(file)
    relative = Path.relative_to_cwd(file)

    extract_validate_handler_blocks(content)
    |> Enum.flat_map(fn {block, start_line} ->
      block
      |> String.split("\n")
      |> Enum.with_index(start_line)
      |> Enum.flat_map(fn {line, line_num} ->
        trimmed = String.trim(line)

        if not String.starts_with?(trimmed, "#") and
             Regex.match?(~r/\bMap\.put\(/, trimmed) do
          [{:struct_mutation_in_validate, relative, line_num,
            "Map.put in validate handler mutates the Ecto struct — use to_form(params) for form state instead",
            line}]
        else
          []
        end
      end)
      |> Enum.take(1)  # One report per handler is enough
    end)
  end

  # Extract handle_event("validate_*" blocks from file content.
  defp extract_validate_handler_blocks(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.reduce({[], nil, nil, 0}, fn {line, line_num}, {blocks, current_block, block_start, depth} ->
      trimmed = String.trim(line)

      cond do
        is_nil(current_block) and Regex.match?(~r/handle_event\(\s*"validate/, line) ->
          {blocks, [line], line_num, count_depth_delta(trimmed)}

        not is_nil(current_block) ->
          new_depth = depth + count_depth_delta(trimmed)

          # A new top-level def/defp or @impl ends this handler
          is_new_def = (Regex.match?(~r/^\s*def(p?)\s+\w+/, line) or
                         Regex.match?(~r/^\s*@impl/, line)) and
                        depth <= 1 and line_num > block_start

          cond do
            is_new_def ->
              block_str = Enum.join(Enum.reverse(current_block), "\n")
              {[{block_str, block_start} | blocks], nil, nil, 0}

            new_depth <= 0 and depth > 0 ->
              final_block = [line | current_block]
              block_str = Enum.join(Enum.reverse(final_block), "\n")
              {[{block_str, block_start} | blocks], nil, nil, 0}

            true ->
              {blocks, [line | current_block], block_start, new_depth}
          end

        true ->
          {blocks, current_block, block_start, depth}
      end
    end)
    |> then(fn {blocks, current_block, block_start, _depth} ->
      if current_block do
        block_str = Enum.join(Enum.reverse(current_block), "\n")
        [{block_str, block_start} | blocks]
      else
        blocks
      end
    end)
    |> Enum.reverse()
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp web_files(web_root, patterns) when is_list(patterns) do
    Enum.flat_map(patterns, fn pattern ->
      web_root
      |> Path.join(pattern)
      |> Path.wildcard()
    end)
    |> Enum.uniq()
    |> Enum.filter(&File.regular?/1)
  end

  defp live_files(live_root) do
    live_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
  end

  defp scan_lines(file, pattern, type, message) do
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
        if Regex.match?(pattern, trimmed) do
          [{type, relative, line_num, message, line}]
        else
          []
        end
      end
    end)
  end

  # Extract mount function bodies from file content.
  # Returns a list of {block_string, start_line_number} tuples.
  defp extract_mount_blocks(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.reduce({[], nil, nil, 0}, fn {line, line_num}, {blocks, current_block, block_start, depth} ->
      trimmed = String.trim(line)

      cond do
        # Detect start of a mount/2 or mount/3 function definition
        is_nil(current_block) and Regex.match?(~r/^\s*def\s+mount\s*[\(\b]/, line) ->
          {blocks, [line], line_num, count_depth_delta(trimmed)}

        # Accumulating lines inside a mount block
        not is_nil(current_block) ->
          new_depth = depth + count_depth_delta(trimmed)

          # A new top-level def/defp ends the current mount block
          is_new_def = Regex.match?(~r/^\s*def(p?)\s+\w+/, line) and depth <= 1 and line_num > block_start

          cond do
            is_new_def and new_depth <= 0 ->
              block_str = Enum.join(Enum.reverse(current_block), "\n")
              {[{block_str, block_start} | blocks], nil, nil, 0}

            new_depth <= 0 and depth > 0 ->
              # Closing the mount block
              final_block = [line | current_block]
              block_str = Enum.join(Enum.reverse(final_block), "\n")
              {[{block_str, block_start} | blocks], nil, nil, 0}

            true ->
              {blocks, [line | current_block], block_start, new_depth}
          end

        true ->
          {blocks, current_block, block_start, depth}
      end
    end)
    |> then(fn {blocks, current_block, block_start, _depth} ->
      # Flush any unclosed block (end of file)
      if current_block do
        block_str = Enum.join(Enum.reverse(current_block), "\n")
        [{block_str, block_start} | blocks]
      else
        blocks
      end
    end)
    |> Enum.reverse()
  end

  # Simple depth heuristic: count do/end/fn keywords to track nesting
  defp count_depth_delta(line) do
    opens =
      (if Regex.match?(~r/\bdo\b/, line), do: 1, else: 0) +
      (if Regex.match?(~r/\bfn\b/, line), do: 1, else: 0)

    closes =
      (if Regex.match?(~r/\bend\b/, line), do: 1, else: 0)

    opens - closes
  end

  # --- Output ---

  defp print_issue({type, file, line_num, message, line}) do
    label =
      case type do
        :deprecated_phx_update        -> "DEPRECATED-PHX-UPDATE"
        :list_assign                  -> "LIST-ASSIGN-IN-MOUNT"
        :stream_enum                  -> "STREAM-ENUMERATED"
        :missing_connected            -> "MISSING-CONNECTED-GUARD"
        :form_let                     -> "FORM-LET-IN-LIVEVIEW"
        :struct_mutation_in_validate  -> "STRUCT-MUTATION-IN-VALIDATE"
      end

    IO.puts("  ❌ [#{label}] #{file}:#{line_num}")
    IO.puts("    #{String.trim(line)}")
    IO.puts("    → #{message}\n")
  end
end

LiveViewAntipatterns.run()
