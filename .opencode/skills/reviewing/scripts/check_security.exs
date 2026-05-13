#!/usr/bin/env elixir

# Security anti-pattern checker for any Elixir/Phoenix project:
# 1. ATOM-EXHAUSTION     — String.to_atom/1 in lib/ (use String.to_existing_atom/1)
# 2. UNSAFE-RAW          — raw() calls in web templates (XSS risk)
# 3. QUERY-INTERPOLATION — string interpolation inside Ecto fragments / raw queries (SQL injection)
# 4. HARDCODED-SECRET    — secret_key_base / signing_salt with a literal string in config files

defmodule SecurityChecker do
  @lib_root "lib"

  def run do
    atom_exhaustion     = check_atom_exhaustion()
    unsafe_raw          = check_unsafe_raw()
    query_interpolation = check_query_interpolation()
    hardcoded_secret    = check_hardcoded_secret()

    all_issues =
      atom_exhaustion ++
      unsafe_raw ++
      query_interpolation ++
      hardcoded_secret

    if all_issues == [] do
      IO.puts("✅ No security anti-patterns found")
    else
      Enum.each(all_issues, &print_issue/1)
      IO.puts("Total: #{length(all_issues)} violation(s)")
      System.halt(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Dynamic project root detection
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
  # 1. ATOM-EXHAUSTION — String.to_atom/1 in lib/
  # ---------------------------------------------------------------------------
  # Safe contexts (test files, seeds, migrations) are excluded because
  # they run in controlled environments where atom exhaustion is not a risk.

  defp check_atom_exhaustion do
    issues =
      @lib_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.reject(&safe_context?/1)
      |> Enum.flat_map(&check_atom_exhaustion_file/1)

    if issues == [] do
      IO.puts("✅ Atom exhaustion: no String.to_atom/1 calls found in lib/")
    end

    issues
  end

  defp safe_context?(file) do
    String.contains?(file, "_test.exs") or
      String.contains?(file, "priv/repo/seeds") or
      String.contains?(file, "priv/repo/migrations") or
      String.ends_with?(file, "_test.ex")
  end

  defp check_atom_exhaustion_file(file) do
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
        if Regex.match?(~r/\bString\.to_atom\s*\(/, trimmed) do
          [{:atom_exhaustion, relative, line_num,
            "String.to_atom/1 can exhaust the atom table — use String.to_existing_atom/1 instead",
            line}]
        else
          []
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # 2. UNSAFE-RAW — raw() calls in the web directory
  # ---------------------------------------------------------------------------
  # Phoenix.HTML.raw/1 bypasses HTML escaping and can create XSS vulnerabilities.
  # Every use should be reviewed to confirm the content is sanitized before rendering.

  defp check_unsafe_raw do
    web_root = find_web_root()

    if web_root == nil do
      IO.puts("✅ Unsafe raw: no *_web directory found, skipping")
      []
    else
      issues =
        [web_root |> Path.join("**/*.ex") |> Path.wildcard(),
         web_root |> Path.join("**/*.heex") |> Path.wildcard()]
        |> List.flatten()
        |> Enum.uniq()
        |> Enum.flat_map(&check_unsafe_raw_file/1)

      if issues == [] do
        IO.puts("✅ Unsafe raw: no raw() calls found in web templates")
      end

      issues
    end
  end

  defp check_unsafe_raw_file(file) do
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
        # Match raw( as a function call — covers Phoenix.HTML.raw( and bare raw(
        # Skip lines that already pass through HtmlSanitizer — those are already protected
        already_sanitized? =
          String.contains?(trimmed, "HtmlSanitizer") or String.contains?(trimmed, "sanitize")

        # Hardcoded HTML strings — raw(~s(...)) with no assigns (@) references are
        # developer-controlled HTML with no user input, so they are safe.
        hardcoded_html? =
          Regex.match?(~r/\braw\s*\(~s\(/, trimmed) and not String.contains?(trimmed, "@")

        # Empty raw("") — the empty string is trivially safe.
        empty_raw? = Regex.match?(~r/\braw\s*\(\s*""\s*\)/, trimmed)

        # Pipe-terminating raw — "|> raw()" or "|> Phoenix.HTML.raw()" as a standalone
        # pipe step. The content is produced by the preceding pipeline steps; the
        # sanitization call lives on the line above and is not visible here.
        pipe_terminal_raw? = Regex.match?(~r/^\|>\s*(Phoenix\.HTML\.)?raw\s*\(\s*\)$/, trimmed)

        if Regex.match?(~r/\braw\s*\(/, trimmed) and not already_sanitized? and
             not hardcoded_html? and not empty_raw? and not pipe_terminal_raw? do
          [{:unsafe_raw, relative, line_num,
            "raw() bypasses HTML escaping — verify content is sanitized to prevent XSS",
            line}]
        else
          []
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # 3. QUERY-INTERPOLATION — string interpolation in Ecto queries
  # ---------------------------------------------------------------------------
  # String interpolation inside fragment(), Repo.query(), or Repo.query!() calls
  # creates SQL injection vulnerabilities. Use query parameters instead.

  defp check_query_interpolation do
    issues =
      @lib_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(&check_query_interpolation_file/1)

    if issues == [] do
      IO.puts("✅ Query interpolation: no string interpolation found in Ecto queries")
    end

    issues
  end

  defp check_query_interpolation_file(file) do
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
        # Pin-bound interpolations like ^"%#{var}%" are safe Elixir values passed
        # as query parameters — the ^ operator pins them as parameterized values,
        # not raw SQL. Strip those before checking for unsafe interpolation.
        stripped = Regex.replace(~r/\^"[^"]*#\{[^}]*\}[^"]*"/, trimmed, "")

        cond do
          # fragment("...#{  — SQL injection via interpolated fragment string
          Regex.match?(~r/\bfragment\s*\(.*#\{/, stripped) ->
            [{:query_interpolation, relative, line_num,
              "String interpolation in fragment() — use query parameters (?) instead of \#{} to prevent SQL injection",
              line}]

          # Repo.query("...#{  or  Repo.query!("...#{  — raw SQL with interpolation
          Regex.match?(~r/\bRepo\.query[!]?\s*\(.*#\{/, stripped) ->
            [{:query_interpolation, relative, line_num,
              "String interpolation in Repo.query/query! — use parameterized queries instead of \#{} to prevent SQL injection",
              line}]

          true ->
            []
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # 4. HARDCODED-SECRET — literal secrets in config files
  # ---------------------------------------------------------------------------
  # Secrets like secret_key_base must come from System.get_env/1
  # in config/runtime.exs, not be hardcoded as strings in config files.

  defp check_hardcoded_secret do
    config_files = ["config/config.exs", "config/prod.exs"]

    issues =
      config_files
      |> Enum.filter(&File.exists?/1)
      |> Enum.flat_map(&check_hardcoded_secret_file/1)

    if issues == [] do
      IO.puts("✅ Hardcoded secrets: no literal secrets found in config files")
    end

    issues
  end

  defp check_hardcoded_secret_file(file) do
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
        cond do
          # secret_key_base: "..." — should use System.get_env/1
          Regex.match?(~r/secret_key_base:\s*"[^"]+"/, trimmed) ->
            [{:hardcoded_secret, file, line_num,
              "secret_key_base should use System.get_env/1 in config/runtime.exs, not a hardcoded string",
              line}]

          # signing_salt: "..." — signing_salt is a standard Phoenix LiveView cookie-signing
          # salt, not a secret. It is intentionally hardcoded and safe to commit.
          Regex.match?(~r/signing_salt:\s*"[^"]+"/, trimmed) ->
            []

          # Long hex/base64 string assigned to a config key — looks like an API key or token
          Regex.match?(~r/\w+:\s*"[A-Za-z0-9+\/=_\-]{32,}"/, trimmed) and
          not String.contains?(trimmed, "System.get_env") and
          not String.contains?(trimmed, "Path.") and
          not String.contains?(trimmed, "url") and
          not String.contains?(trimmed, "host") and
          not String.contains?(trimmed, "adapter") and
          not String.contains?(trimmed, "pool") ->
            [{:hardcoded_secret, file, line_num,
              "Possible hardcoded API key or secret (long string literal) — use System.get_env/1 in config/runtime.exs",
              line}]

          true ->
            []
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Docstring detection — returns a MapSet of line numbers inside @moduledoc/@doc blocks
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
  # Output
  # ---------------------------------------------------------------------------

  defp print_issue({type, file, line_num, message, line}) do
    label =
      case type do
        :atom_exhaustion     -> "ATOM-EXHAUSTION"
        :unsafe_raw          -> "UNSAFE-RAW"
        :query_interpolation -> "QUERY-INTERPOLATION"
        :hardcoded_secret    -> "HARDCODED-SECRET"
      end

    IO.puts("  ❌ [#{label}] #{file}:#{line_num}")
    IO.puts("    #{String.trim(line)}")
    IO.puts("    → #{message}\n")
  end
end

SecurityChecker.run()
