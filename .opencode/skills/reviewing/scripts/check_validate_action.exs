#!/usr/bin/env elixir

# Checks LiveView validate event handlers for missing action: :validate in to_form().
#
# Without action: :validate, the form won't show inline errors during validation.
# Source: implementing/phoenix-forms.md §3.3
#
# Checks:
# 1. handle_event("validate", ...) calls to_form() without action: :validate

defmodule ValidateActionChecker do
  @lib_root "lib"

  def run do
    web_root = find_web_root()

    if is_nil(web_root) do
      IO.puts("✅ No *_web directory found — skipping validate action checks")
      System.halt(0)
    end

    issues =
      [web_root, @lib_root]
      |> Enum.flat_map(fn root ->
        root
        |> Path.join("**/*.ex")
        |> Path.wildcard()
      end)
      |> Enum.uniq()
      |> Enum.reject(&skip_file?/1)
      |> Enum.flat_map(&check_file/1)

    if issues == [] do
      IO.puts("✅ All validate handlers include action: :validate in to_form()")
    else
      Enum.each(issues, &print_issue/1)
      IO.puts("\nTotal: #{length(issues)} issue(s)")
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
      String.contains?(file, "/migrations/")
  end

  defp check_file(file) do
    relative = Path.relative_to_cwd(file)
    content = File.read!(file)
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> find_validate_handlers(relative, lines)
  end

  defp find_validate_handlers(indexed_lines, file, all_lines) do
    indexed_lines
    |> Enum.flat_map(fn {line, line_num} ->
      trimmed = String.trim(line)

      if String.starts_with?(trimmed, "#") do
        []
      else
        if Regex.match?(~r/handle_event\(\s*"validate"/, trimmed) do
          scan_handler_body(all_lines, line_num, file)
        else
          []
        end
      end
    end)
  end

  # Scan the next 30 lines after handle_event("validate"...) for to_form() without action:
  defp scan_handler_body(all_lines, start_line, file) do
    end_line = min(start_line + 30, length(all_lines))

    body_lines =
      all_lines
      |> Enum.slice(start_line, end_line - start_line)
      |> Enum.with_index(start_line + 1)

    has_to_form = Enum.any?(body_lines, fn {line, _} ->
      Regex.match?(~r/to_form\b/, line) and not String.starts_with?(String.trim(line), "#")
    end)

    has_action_validate = Enum.any?(body_lines, fn {line, _} ->
      Regex.match?(~r/action:\s*:validate/, line)
    end)

    # Also check for the two-step pattern: changeset |> Map.put(:action, :validate) |> to_form()
    has_map_put_action = Enum.any?(body_lines, fn {line, _} ->
      Regex.match?(~r/Map\.put\(\s*:action,\s*:validate\)/, line) or
        Regex.match?(~r/\|>\s*Map\.put\(\s*:action,\s*:validate\)/, line)
    end)

    if has_to_form and not has_action_validate and not has_map_put_action do
      to_form_line = Enum.find(body_lines, fn {line, _} ->
        Regex.match?(~r/to_form\b/, line) and not String.starts_with?(String.trim(line), "#")
      end)

      case to_form_line do
        {line, num} ->
          [{:missing_action, file, num,
            "to_form() in validate handler without action: :validate — form won't show inline errors",
            line}]
        nil -> []
      end
    else
      []
    end
  end

  defp print_issue({:missing_action, file, line_num, message, line}) do
    IO.puts("  ❌ [MISSING-VALIDATE-ACTION] #{file}:#{line_num}")
    IO.puts("    #{String.trim(line)}")
    IO.puts("    → #{message}")
  end
end

ValidateActionChecker.run()
