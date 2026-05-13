#!/usr/bin/env elixir

# Checks HEEx templates for raw HTML elements that should use Phoenix components.
#
# Every Phoenix project generates CoreComponents with .button, .input, .table, .modal,
# .header, .back, .flash_group, .simple_form, .error, .list. Using raw HTML instead
# of these components bypasses consistent styling, accessibility, and error handling.
# Adapted from SutraUI check_component_usage.exs — generic Phoenix convention.
#
# Checks:
# 1. Raw <button> instead of <.button> or Phoenix.Component button
# 2. Raw <input> instead of <.input>
# 3. Raw <table> instead of <.table>
# 4. Raw <form> instead of <.simple_form> or <.form>
# 5. Raw <a href> for internal navigation instead of <.link>

defmodule ComponentUsageChecker do
  @lib_root "lib"

  @component_mappings [
    {"<button", ".button", ~r/<button\b(?!.*<\/button>.*<\.button)/, "Use <.button> component"},
    {"<input", ".input", ~r/<input\b(?!\s+type="hidden")/, "Use <.input> component"},
    {"<table", ".table", ~r/<table\b/, "Use <.table> component"},
    {"<form", ".simple_form or .form", ~r/<form\b/, "Use <.simple_form> or <.form> component"},
  ]

  @link_pattern ~r/<a\s+href=["'][^"']*["']/

  def run do
    web_root = find_web_root()

    if is_nil(web_root) do
      IO.puts("✅ No *_web directory found — skipping component checks")
      System.halt(0)
    end

    heex_files = Path.join(web_root, "**/*.html.heex") |> Path.wildcard()
    ex_files = Path.join(web_root, "**/*.ex") |> Path.wildcard()

    all_files = (heex_files ++ ex_files) |> Enum.reject(&skip_file?/1)

    issues = Enum.flat_map(all_files, &check_file/1)

    if issues == [] do
      IO.puts("✅ Templates use Phoenix components consistently")
    else
      Enum.each(issues, &print_issue/1)
      IO.puts("\nTotal: #{length(issues)} raw HTML element(s) — use Phoenix components instead")
      IO.puts("  Suppress: Add <!-- component:allow --> or # component:allow in the file")
      System.halt(1)
    end
  end

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

  defp skip_file?(file) do
    String.contains?(file, "_test.exs") or
      String.contains?(file, "/test/") or
      String.contains?(file, "core_components.ex") or
      String.contains?(file, "components/") and String.ends_with?(file, ".ex")
  end

  defp check_file(file) do
    relative = Path.relative_to_cwd(file)
    content = File.read!(file)

    if String.contains?(content, "component:allow") do
      []
    else
      lines = String.split(content, "\n")
      in_heex = String.ends_with?(file, ".heex")

      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_num} ->
        trimmed = String.trim(line)

        cond do
          String.starts_with?(trimmed, "#") -> []
          String.starts_with?(trimmed, "<%#") -> []
          String.starts_with?(trimmed, "<!--") -> []

          # Only check inside ~H sigils for .ex files
          not in_heex and not in_heex_sigil?(lines, line_num) -> []

          true ->
            check_components(trimmed, line_num, relative, line) ++
              check_links(trimmed, line_num, relative, line)
        end
      end)
    end
  end

  defp in_heex_sigil?(lines, line_num) do
    preceding = Enum.take(lines, line_num - 1)
    sigil_opens = Enum.count(preceding, &Regex.match?(~r/~H\s*"""/, &1))
    sigil_closes = Enum.count(preceding, fn l ->
      trimmed = String.trim(l)
      trimmed == ~S(""") and sigil_opens > 0
    end)
    sigil_opens > sigil_closes
  end

  defp check_components(line, line_num, file, original_line) do
    @component_mappings
    |> Enum.flat_map(fn {raw_tag, _component, regex, message} ->
      if Regex.match?(regex, line) do
        [{:raw_html, file, line_num, "Raw #{raw_tag}> found — #{message}", original_line}]
      else
        []
      end
    end)
  end

  defp check_links(line, line_num, file, original_line) do
    if Regex.match?(@link_pattern, line) do
      # Only flag internal links (starting with / or ~p)
      if Regex.match?(~r/<a\s+href=["']\//, line) or
           Regex.match?(~r/<a\s+href=["']~p/, line) do
        [{:raw_html, file, line_num,
          "Raw <a href> for internal link — use <.link navigate={...}> component",
          original_line}]
      else
        []
      end
    else
      []
    end
  end

  defp print_issue({:raw_html, file, line_num, message, line}) do
    IO.puts("  ❌ [RAW-HTML] #{file}:#{line_num}")
    IO.puts("    #{String.trim(line)}")
    IO.puts("    → #{message}")
  end
end

ComponentUsageChecker.run()
