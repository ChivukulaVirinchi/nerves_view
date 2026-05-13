# Configuration Strategy — depth reference

> **Routing:** [SKILL.md](SKILL.md) §2 — Master Decision Table, row 3.10 (Configuration).

---

## 1. Config file roles

| File | Loaded when | Use for |
|---|---|---|
| `config/config.exs` | Compile time | Defaults, application-owned compile-time values |
| `config/dev.exs` | Compile time (dev only) | Dev overrides (verbose logs, dev tooling) |
| `config/test.exs` | Compile time (test only) | Mox wiring, small pool sizes, test adapters |
| `config/runtime.exs` | Boot time (after release assembly) | Per-deployment env vars, secrets |

## 2. Compile-time vs runtime — decision

| Value character | API | File |
|---|---|---|
| Known at build, app-owned, immutable per release | `Application.compile_env!(:my_app, :key)` | `config/config.exs` |
| Per-deployment env var | `System.fetch_env!("VAR")` + `Application.get_env` | `config/runtime.exs` |
| Library consumer configures | `Application.get_env(:my_lib, :key, default)` at runtime; options to `start_link` | Caller's config files |
| Feature flag (toggleable without deploy) | External (FunWithFlags, Flagsmith, DB row, ETS) | Outside `config/*.exs` |
| Test-specific override | `config :my_app, ...` | `config/test.exs` |

## 3. Library vs application config

**Applications** can use `Application.compile_env` safely — they control their own build:

```elixir
defmodule MyApp.Cache do
  @ttl Application.compile_env!(:my_app, [:cache, :ttl])
  def ttl, do: @ttl
end
```

**Libraries MUST NOT** use `Application.compile_env` — consumers can't reconfigure after compilation:

```elixir
# BAD (in a library)
defmodule MyLib.Client do
  @api_key Application.compile_env!(:my_lib, :api_key)
  def call, do: request(@api_key)
end

# GOOD (in a library)
defmodule MyLib.Client do
  def call, do: request(api_key())
  defp api_key, do: Application.get_env(:my_lib, :api_key) ||
                      raise "configure :my_lib, :api_key"
end

# BEST (in a library) — accept as argument
defmodule MyLib.Client do
  def call(opts), do: request(Keyword.fetch!(opts, :api_key))
end
```

## 4. `runtime.exs` validation discipline

`runtime.exs` is where production blows up at boot — so the validation shape is a planning decision, not an implementation detail. Three rules:

1. **Validate the shape** — `System.fetch_env!/1` for required vars (raises clearly if missing); `System.get_env/2` with a typed default for optional ones.
2. **Bounded parse** — every string that becomes a port, pool size, timeout, URL, or boolean goes through a parser with explicit bounds. Don't feed raw env strings into `String.to_integer/1` without a range check; don't feed them into `String.to_atom/1` at all (atom table exhaustion).
3. **Explicit error message** — when validation fails, the error message says **which env var** was wrong and **what shape** was expected. "Invalid argument" is a production incident waiting to happen.

```elixir
# config/runtime.exs — shape and validation
import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      DATABASE_URL is required in prod.
      Expected: ecto://USER:PASS@HOST/DB_NAME
      """

  pool_size =
    case System.get_env("POOL_SIZE", "10") |> Integer.parse() do
      {n, ""} when n in 1..100 -> n
      _ -> raise "POOL_SIZE must be an integer in 1..100"
    end

  config :my_app, MyApp.Repo, url: database_url, pool_size: pool_size
end
```

**NEVER** use `String.to_atom/1` or `String.to_existing_atom/1` on untrusted env input that can be arbitrary — use an explicit allowlist (`case val do "prod" -> :prod; "stage" -> :stage; ... end`).

## 5. Config accessor shape — centralize reads

Planning decision: where do config reads *live* in the code? The answer is a single `MyApp.Config` module whose public functions are zero-arg accessors. Every other module routes config reads through it. Scattered `Application.get_env/3` calls across dozens of modules are a persistent anti-pattern — hard to mock consistently, hard to audit, hard to swap in tests.

In an umbrella with separate deployables, each app gets its own `MyApp.Config` (e.g. `Nodepulse.Config` for the central app, `NodepulseEdge.Config` for the edge app). Shared wire/protocol libs use the default Application env pattern so consumers configure them from the outside.

The concrete module shape is in `elixir-implementing` §10.5.1. The planning commitment is: name the module now (e.g. "Nodepulse will have `Nodepulse.Config`"), and every config access goes through it.

## 6. Configuration handoff to `elixir-implementing`

The implementation patterns for reading config (at-runtime vs at-boot, `fetch_env!` vs `get_env`, the `MyApp.Config` accessor module) are in `elixir-implementing` §10.5-10.5.1 and §8.6. This section is about **where values live**, **why**, and **how the plan pins down the shape** — the planning decision.

---

## 7. Cross-references

- [SKILL.md](SKILL.md) §2 row 3.10 — configuration decision table
- [architecture-patterns.md](architecture-patterns.md) §4 — hexagonal architecture (config selects adapters)
- `elixir-implementing` §10.5-10.5.1 — config accessor module templates
- `elixir-implementing` §8.6 — compile_env vs get_env at call sites

---

**End of configuration.md.** For implementation templates, see `elixir-implementing`. For hexagonal adapter selection via config, see [architecture-patterns.md](architecture-patterns.md) §4.
