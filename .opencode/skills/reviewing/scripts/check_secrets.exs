#!/usr/bin/env elixir

# Checks structs with sensitive fields for missing @derive {Inspect, only: [...]}.
#
# Without this, IO.inspect/Logger will leak secrets (tokens, passwords, keys)
# into logs. Source: implementing/critical-patterns.md §5.14
#
# Checks:
# 1. defstruct with sensitive field names but no @derive Inspect restriction

defmodule SecretStructChecker do
  @lib_root "lib"

  @sensitive_fields ~w(
    password password_hash hashed_password encrypted_password password_digest
    token access_token refresh_token api_token auth_token secret_token
    secret secret_key secret_key_base api_key api_secret
    private_key signing_key encryption_key
    otp_secret totp_secret two_factor_secret
    credit_card_number card_number cvv ssn
  )

  def run do
    issues =
      @lib_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&skip_file?/1)
      |> Enum.flat_map(&check_file/1)

    if issues == [] do
      IO.puts("✅ All structs with sensitive fields have @derive Inspect restrictions")
    else
      Enum.each(issues, &print_issue/1)
      IO.puts("\nTotal: #{length(issues)} issue(s)")
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

    modules = extract_module_blocks(lines)

    Enum.flat_map(modules, fn {module_lines, start_offset} ->
      check_module(module_lines, start_offset, relative)
    end)
  end

  defp extract_module_blocks(lines) do
    [{lines, 0}]
  end

  defp check_module(lines, offset, file) do
    indexed = Enum.with_index(lines, offset + 1)

    defstruct_line = Enum.find(indexed, fn {line, _} ->
      trimmed = String.trim(line)
      not String.starts_with?(trimmed, "#") and
        Regex.match?(~r/defstruct\b/, trimmed)
    end)

    case defstruct_line do
      nil -> []
      {line, line_num} ->
        struct_text = collect_defstruct(lines, line_num - offset - 1)
        sensitive = find_sensitive_fields(struct_text)

        if sensitive == [] do
          []
        else
          has_derive_inspect = Enum.any?(indexed, fn {l, _} ->
            Regex.match?(~r/@derive\s+\{?\s*Inspect\b/, l)
          end)

          has_inspect_impl = Enum.any?(indexed, fn {l, _} ->
            Regex.match?(~r/defimpl\s+Inspect/, l)
          end)

          # Check for secret-struct:allow suppression
          has_suppression = Enum.any?(indexed, fn {l, _} ->
            String.contains?(l, "secret-struct:allow")
          end)

          if has_derive_inspect or has_inspect_impl or has_suppression do
            []
          else
            [{:exposed_secret, file, line_num,
              "Struct has sensitive fields #{inspect(sensitive)} without @derive {Inspect, only: [...]}",
              line}]
          end
        end
    end
  end

  defp collect_defstruct(lines, start_idx) do
    lines
    |> Enum.drop(start_idx)
    |> Enum.take(20)
    |> Enum.join("\n")
  end

  defp find_sensitive_fields(text) do
    @sensitive_fields
    |> Enum.filter(fn field ->
      Regex.match?(~r/:#{field}\b/, text)
    end)
  end

  defp print_issue({:exposed_secret, file, line_num, message, line}) do
    IO.puts("  ❌ [EXPOSED-SECRET-STRUCT] #{file}:#{line_num}")
    IO.puts("    #{String.trim(line)}")
    IO.puts("    → #{message}")
    IO.puts("    Fix: Add @derive {Inspect, only: [:id, :email]} before defstruct")
    IO.puts("    Suppress: Add # secret-struct:allow comment in the module")
  end
end

SecretStructChecker.run()
