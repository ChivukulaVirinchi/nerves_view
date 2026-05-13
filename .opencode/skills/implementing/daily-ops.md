---
name: implementing/daily-ops
description: >
  Daily operations for Elixir implementation — ok/error conventions, error handling,
  module structure, naming, documentation, configuration, logging, Mix commands, IEx.
  ALWAYS use when structuring modules, naming functions, or setting up configuration.
---

# Daily Operations

> **Parent:** [SKILL.md](SKILL.md) — implementing routing core.
> **Depth:** For `@spec`/`@type`/`@doc`/`@moduledoc`/doctests/Dialyzer, load [type-and-docs.md](type-and-docs.md). For Ecto schemas/changesets/queries/migrations/Multi, load [ecto-impl.md](ecto-impl.md). For TCP/UDP/protocol-framing code, load [networking-patterns.md](networking-patterns.md).

The code-maintenance toolkit: error handling, module structure, naming, docs, configuration, logging. Each subsection leads with the decision and shows the idiomatic shape.

---

### 8.1 ok/error tuple conventions

| When the function... | Returns |
|---|---|
| Succeeds with data | `{:ok, value}` |
| Succeeds with no meaningful data (side effect confirmed) | `:ok` |
| Fails with a known reason | `{:error, atom_reason}` or `{:error, struct_or_map}` |
| Fails with compound context | `{:error, {reason, details}}` |
| Cannot fail (infallible) | Return the value directly |
| Fails loudly because the caller guaranteed valid input | `!`-suffixed version that raises |

**Canonical pairs:**

```elixir
# Non-bang returns ok/error — caller decides how to handle failure
def fetch(id) do
  case lookup(id) do
    nil -> {:error, :not_found}
    val -> {:ok, val}
  end
end

# Bang raises — failure is a programmer error, fail fast
def fetch!(id) do
  case fetch(id) do
    {:ok, val} -> val
    {:error, reason} -> raise "fetch/1 failed: #{inspect(reason)}"
  end
end
```

### 8.2 Error handling decision tree

| Situation | Strategy |
|---|---|
| Condition is checkable before the call | Check first (`Process.whereis`, `Map.fetch`), don't catch |
| Calling a process you don't control | `catch :exit, _` at the boundary |
| Untrusted external input (network bytes, user blob) | `rescue` specific exception at the adapter boundary |
| Expected business failure | Return `{:error, reason}`; caller matches |
| Programmer error in script / seed | Use bang variant, let it crash |
| Anything else inside a supervised process | Let it crash — supervisor restarts |

#### 8.2.1 Secret comparison — constant-time only

When comparing secrets (API tokens, HMAC digests, verifier codes, literal passwords in dev/debug paths) use `Plug.Crypto.secure_compare/2`. The regular `==` operator is variable-time: it short-circuits on the first mismatched byte, leaking timing information that can be exploited remotely.

```elixir
# BAD — variable-time comparison of a secret
def valid_api_key?(user_input), do: user_input == @expected_api_key

# GOOD — constant-time, even when lengths differ
def valid_api_key?(user_input) do
  Plug.Crypto.secure_compare(user_input, @expected_api_key)
end
```

Rule of thumb: if the value being compared came from an untrusted source and a "match" grants access, use `secure_compare/2`. Cookies, bearer tokens, HMAC digests, webhook signatures all qualify. For cleartext password verification specifically, use your password library's verifier (`Bcrypt.verify_pass/2`, `Argon2.verify_pass/2`) — those are already constant-time.

### 8.3 Module structure — the canonical template

```elixir
defmodule MyApp.Accounts.User do
  @moduledoc """
  User aggregate — identity, authentication, profile.
  """

  use Ecto.Schema                          # 1. use
  import Ecto.Changeset                    # 2. import
  alias MyApp.{Repo, Accounts.Token}       # 3. alias
  require Logger                           # 4. require

  @behaviour MyApp.Identifiable            # 5. @behaviour

  @type t :: %__MODULE__{}                 # 6. @type / @typedoc
  @type role :: :admin | :member | :guest

  @roles [:admin, :member, :guest]         # 7. module attributes (constants)
  @derive {Jason.Encoder, only: [:id, :email, :name]}

  # 8. schema / defstruct
  schema "users" do
    field :email, :string
    field :name, :string
    field :role, Ecto.Enum, values: @roles
    timestamps(type: :utc_datetime_usec)
  end

  # 9. public API with @doc + @spec
  @doc "Creates a changeset for user registration."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs), do: ...

  # 10. callback implementations
  @impl MyApp.Identifiable
  def id(%__MODULE__{id: id}), do: id

  # 11. private helpers (defp) at the bottom
  defp validate_email_format(cs), do: ...
end
```

**Order:** `@moduledoc` → `use` → `import` → `alias` → `require` → `@behaviour` → `@type` → attributes → schema/struct → public functions → private helpers.

### 8.4 Naming

| Kind | Style | Example |
|---|---|---|
| Module | PascalCase | `MyApp.OrderProcessor` |
| Function | snake_case | `process_order/2` |
| Private helper | snake_case, often with `do_` prefix for recursive or `maybe_` for conditional | `do_process/2`, `maybe_notify/1` |
| Predicate | ends with `?` | `valid?/1`, `empty?/1` |
| Raising variant | ends with `!` | `fetch!/1`, `parse!/1` |
| Atom identifier | snake_case | `:not_found`, `:invalid_email` |
| Module attribute | snake_case | `@default_timeout` |
| Variable | snake_case | `current_user`, `email_pid` |
| Type | lowercase, ends `t()` for the main struct type | `user :: t()` |

**Function naming patterns:**

- `get_foo/1` — pure lookup, returns value or `nil` / default
- `fetch_foo/1` — returns `{:ok, value}` / `{:error, reason}`
- `fetch_foo!/1` — returns value or raises
- `list_foos/0,1` — returns a list (possibly empty)
- `create_foo/1` — inserts new; returns `{:ok, struct}` / `{:error, changeset}`
- `update_foo/2` — updates existing; same return shape
- `delete_foo/1` — deletes
- `foo?/1` — predicate returning boolean

### 8.5 Documentation

**Minimum every public module must have:**

```elixir
defmodule MyApp.Orders do
  @moduledoc """
  Order aggregate — cart → payment → fulfillment.

  ## Overview

  One-paragraph summary. What problem does this module solve?

  ## Examples

      iex> MyApp.Orders.place_order(%{...})
      {:ok, %Order{id: _}}
  """

  @doc """
  Places a new order.

  ## Parameters
    * `attrs` — order attributes (must include `:user_id`, `:items`)

  ## Examples

      iex> MyApp.Orders.place_order(%{user_id: 1, items: []})
      {:error, :empty_cart}
  """
  @spec place_order(map()) :: {:ok, Order.t()} | {:error, term()}
  def place_order(attrs), do: ...
end
```

**Doctest rule:** put `iex>` examples in `@doc` when the function is pure and has easily demonstrable output. Doctests become tests automatically via `doctest MyApp.Orders` in your test file.

### 8.6 Configuration — where each kind lives

| Config type | File | Loaded when |
|---|---|---|
| Compile-time, known at build (e.g., `Application.compile_env`) | `config/config.exs` | Compile time |
| Dev-specific overrides | `config/dev.exs` | Compile time (dev only) |
| Test-specific overrides (Mox wiring, reduced pool sizes) | `config/test.exs` | Compile time (test only) |
| Production secrets, per-env env vars | `config/runtime.exs` | Boot time (after release assembly) |
| Library defaults (when writing a library) | `config/config.exs` (minimal) — callers override | Compile time |

**Rules:**

- Libraries use `Application.get_env/3` at runtime — callers configure after compilation
- Applications can use `Application.compile_env/3` for values set at build
- Never put `System.get_env/1` in `config/config.exs` for production values — use `runtime.exs`

```elixir
# config/runtime.exs (Mix release pattern)
import Config
if config_env() == :prod do
  config :my_app, MyApp.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  config :my_app, MyAppWeb.Endpoint,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end
```

### 8.7 Logger — levels and structured logging

| Level | Use for |
|---|---|
| `Logger.debug/1` | Detail useful during development, disabled in prod |
| `Logger.info/1` | Lifecycle events (startup, shutdown, job completed) |
| `Logger.notice/1` | Unusual but normal (rate limit hit, fallback used) |
| `Logger.warning/1` | Recovered error, degraded service |
| `Logger.error/1` | Unrecovered error, alert-worthy |

```elixir
# Prefer structured metadata — searchable in log aggregators
Logger.info("order completed", order_id: order.id, total_cents: order.total_cents)

# Lazy-evaluation for expensive messages — the closure only runs if level is enabled
Logger.debug(fn -> "state: #{inspect(build_heavy_state(), pretty: true)}" end)

# Never: Logger.info("order #{inspect(order)}") — all of inspect runs even if debug is off
```

### 8.8 Mix commands — daily use

```bash
# Compile with warnings as errors (catches undefined functions, unused vars, etc.)
mix compile --warnings-as-errors

# Format + credo + test — the pre-commit trio
mix format
mix credo --strict
mix test

# Focused test runs
mix test path/file_test.exs:42
mix test --failed
mix test --stale

# Dependency operations
mix deps.get                  # Install deps from mix.lock
mix deps.update --all         # Update all deps (respecting version constraints)
mix deps.tree                 # See dependency graph

# Build a production release (Mix releases)
MIX_ENV=prod mix release

# Ecto
mix ecto.create
mix ecto.migrate
mix ecto.rollback --step 1
mix ecto.gen.migration add_users

# Phoenix
mix phx.gen.schema Blog.Post posts title:string body:text
mix phx.server
mix phx.routes
```

### 8.9 IEx — the development REPL

```elixir
# iex -S mix      — start IEx with your project loaded
# iex --dbg pry   — enable IEx.pry/0 for interactive breakpoints

# Helpers (typed in IEx)
h Enum.map/2                  # Docs for a function
i value                       # Type info for a value
v()                           # Last result; v(3) for the result 3 commands ago
r MyModule                    # Recompile a module
recompile                     # Recompile the whole project
s Enum.map/2                  # Show @spec
t String                      # Show @type definitions in a module
exports Module                # List public functions
```

**Remote shell (production release):**

```bash
iex --sname debug --cookie $COOKIE --remsh myapp@localhost
```
