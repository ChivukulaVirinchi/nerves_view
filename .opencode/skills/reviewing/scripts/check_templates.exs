#!/usr/bin/env elixir

# Generic template size checker for any Elixir/Phoenix project.
#
# Checks:
# 1. LiveView render/1 functions exceeding 50 lines of HEEx
# 2. Component template files (.html.heex) exceeding 80 lines
# 3. Skips sigil content in non-render functions (only flags render/1 as public)
#
# Suppress with: # template-size:allow on the line before ~H"""

defmodule TemplateChecker do
  @lib_root "lib"
  @render_limit 50
  @heex_file_limit 80

  def run do
    web_root = find_web_root()

    if is_nil(web_root) do
      IO.puts("✅ No *_web directory found — skipping template checks")
      System.halt(0)
    end

    inline_issues = check_inline_templates(web_root)
    heex_file_issues = check_heex_files(web_root)

    all_issues = inline_issues ++ heex_file_issues

    if all_issues == [] do
      IO.puts("✅ All templates within size limits (render ≤#{@render_limit}, .heex files ≤#{@heex_file_limit})")
    else
      IO.puts("⚠️  Template size violations found:\n")

      Enum.each(all_issues, fn {file, func, lines, limit} ->
        IO.puts("  ❌ #{file} - #{func}: #{lines} lines (limit: #{limit})")
      end)

      IO.puts("\nTotal: #{length(all_issues)} violation(s)")
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
  # Check 1: Inline ~H""" templates in .ex files
  # ---------------------------------------------------------------------------

  defp check_inline_templates(web_root) do
    web_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.flat_map(&check_ex_file/1)
  end

  defp check_ex_file(file) do
    content = File.read!(file)
    relative = Path.relative_to_cwd(file)
    lines = String.split(content, "\n")

    # Find all ~H""" blocks with their preceding context
    lines
    |> Enum.with_index(1)
    |> Enum.reduce({[], nil, nil}, fn
      {line, line_num}, {issues, nil, _} ->
        if String.contains?(line, ~S[~H"""]) do
          # Check if previous line has suppression comment
          prev_line = Enum.at(lines, line_num - 2) || ""

          if String.contains?(prev_line, "template-size:allow") do
            {issues, :suppressed, nil}
          else
            {func_name, visibility} = find_function(lines, line_num)
            {issues, {:in_template, line_num, func_name, visibility, 0}, nil}
          end
        else
          {issues, nil, nil}
        end

      {line, _line_num}, {issues, :suppressed, _} ->
        trimmed = String.trim(line)

        if trimmed == ~S["""] or (String.ends_with?(trimmed, ~S["""]) and not String.contains?(trimmed, ~S[~H"""])) do
          {issues, nil, nil}
        else
          {issues, :suppressed, nil}
        end

      {line, _line_num}, {issues, {:in_template, start, func, vis, count}, _} ->
        trimmed = String.trim(line)

        if trimmed == ~S["""] or (String.ends_with?(trimmed, ~S["""]) and not String.contains?(trimmed, ~S[~H"""])) do
          limit = if vis == :public, do: @render_limit, else: @render_limit

          if count > limit do
            label = if vis == :public, do: "render/1", else: "#{func}"
            {[{relative, label, count, limit} | issues], nil, nil}
          else
            {issues, nil, nil}
          end
        else
          # Don't count blank lines or comment-only lines toward template size
          increment = if trimmed == "" or String.starts_with?(trimmed, "<%!--"), do: 0, else: 1
          {issues, {:in_template, start, func, vis, count + increment}, nil}
        end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # Walk backwards from the ~H""" line to find the enclosing def/defp
  defp find_function(lines, template_line_num) do
    lines
    |> Enum.take(template_line_num - 1)
    |> Enum.reverse()
    |> Enum.reduce_while({nil, :private}, fn line, _acc ->
      cond do
        Regex.match?(~r/^\s*def\s+(\w+)/, line) ->
          [_, name] = Regex.run(~r/^\s*def\s+(\w+)/, line)
          {:halt, {name, :public}}

        Regex.match?(~r/^\s*defp\s+(\w+)/, line) ->
          [_, name] = Regex.run(~r/^\s*defp\s+(\w+)/, line)
          {:halt, {name, :private}}

        true ->
          {:cont, {nil, :private}}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Check 2: .html.heex template files exceeding line limit
  # ---------------------------------------------------------------------------

  defp check_heex_files(web_root) do
    web_root
    |> Path.join("**/*.html.heex")
    |> Path.wildcard()
    |> Enum.flat_map(&check_heex_file/1)
  end

  defp check_heex_file(file) do
    relative = Path.relative_to_cwd(file)
    content = File.read!(file)

    # Count non-blank, non-comment lines
    line_count =
      content
      |> String.split("\n")
      |> Enum.count(fn line ->
        trimmed = String.trim(line)
        trimmed != "" and not String.starts_with?(trimmed, "<%!--")
      end)

    if line_count > @heex_file_limit do
      [{relative, "template file", line_count, @heex_file_limit}]
    else
      []
    end
  end
end

TemplateChecker.run()
