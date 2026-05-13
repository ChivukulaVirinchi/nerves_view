---
name: implementing/architecture-decisions
description: >
  Architecture key decisions while implementing Elixir — context modules, behaviour vs protocol,
  config strategy, Ecto boundary, struct vs map, function placement, file/module layout.
  ALWAYS use when deciding where code lives, choosing polymorphism, or setting up config.
---

# Architecture — Key Decisions While Implementing

> **Parent:** [SKILL.md](SKILL.md) — implementing routing core.
> **Depth:** For upfront project design (umbrella vs single, context splits, data ownership across bounded contexts, architectural styles, resilience patterns, growing from small to large), load `elixir-planning` and in particular its `architecture-patterns.md`, `data-ownership-deep.md`, and `integration-patterns.md`.

When you're implementing code, you encounter architectural decisions at a smaller scale: where does this function live, which module owns this data, should this be a behaviour? This section covers those in-the-moment decisions. For upfront project design (umbrella vs single, context split planning, data ownership across bounded contexts), load `elixir-planning`.

---

### 10.1 Context modules — the public API boundary

**Contexts are the public API of a domain.** Controllers, LiveViews, CLI, scheduled jobs → call the context. Contexts → call Ecto / internal modules.

```elixir
defmodule MyApp.Catalog do
  @moduledoc "Product catalog — public API for all product operations."
  alias MyApp.Catalog.{Product, PriceCalculator}
  alias MyApp.Repo

  # Thin pass-through → defdelegate
  defdelegate get_product!(id), to: Product, as: :fetch!

  # Wrapper with added logic → regular def
  def calculate_price(product, qty) do
    product
    |> PriceCalculator.total(qty)
    |> tap(fn total -> :telemetry.execute([:catalog, :priced], %{total: total}) end)
  end
end
```

```elixir
# Internal modules — @moduledoc false, never called from outside the context
defmodule MyApp.Catalog.PriceCalculator do
  @moduledoc false
  def total(product, qty), do: Decimal.mult(product.price, qty)
end
```

**Rules:**

- The context module file lives directly under `lib/my_app/`: `lib/my_app/catalog.ex`
- Internal modules live in a subdirectory: `lib/my_app/catalog/product.ex`, `lib/my_app/catalog/price_calculator.ex`
- Cross-context calls go through the context public API, never into internals

#### When an `@moduledoc false` module is widely used

If you find that a module marked `@moduledoc false` is reached from many places — multiple contexts, the web layer, Mix tasks, MCP/CLI surface — the marker is lying. The intent says "internal," the call sites say "public infrastructure." Reconcile, don't ignore.

Three responses, by signal:

| Signal | Response | Action |
|---|---|---|
| Module is at the top-level (`MyApp.Diagnostic`) OR ≥ 3 contexts call it | **Move to shared kernel** | Either keep at top level with a real `@moduledoc` documenting it as project-wide infrastructure, OR move under `MyApp.Shared.<Name>`. The `@moduledoc false` marker comes off; the call sites stay. |
| One context plausibly owns the abstraction; thin pass-through suffices | **Facade through the owning context** | Add public functions on the parent context that delegate (`defdelegate`) or wrap with cross-cutting concerns (telemetry, logging). The internal module stays `@moduledoc false`; consumers reach it only through the parent. |
| The module IS the API many consumers genuinely need; you're committing to back-compat | **Promote to public** | Replace `@moduledoc false` with a real moduledoc. Document API stability. Accept that renames and signature changes are now breaking. |

**Default ordering**: try the shared-kernel form first, then facade, then full promotion. Promotion is the heaviest commitment — it locks the function set in place.

**Counter-indicators**:

- *Shared kernel is wrong* when the abstraction has a clear domain owner — moving it to `MyApp.Shared` hides ownership and creates a god-namespace.
- *Facade is wrong* when the wrapper would be pure ceremony (`defdelegate :every_function, :as: :every_function`); promotion is more honest.
- *Promotion is wrong* when the module's internals are likely to evolve — locking with a public moduledoc forecloses future refactor; better to facade and keep flexibility.

The decision points to *where ownership lives*, not *whether the API exists*. Once 3+ unrelated callers reach for the same internal helper, the abstraction is real; only the location is in question.

```elixir
# Example — Archdo's own evolution: Archdo.Diagnostic was marked
# @moduledoc false but used by every rule module. The right call was
# response A (shared kernel) — keep at top-level with a real moduledoc
# documenting it as the diagnostic-builder infrastructure.

defmodule Archdo.Diagnostic do
  @moduledoc """
  Public diagnostic-builder API. Every rule constructs findings via
  `error/2`, `warning/2`, `info/2`, `nitpick/2` from this module.
  Stable: rename / signature change is a breaking change to every rule.
  """
  # ... defstruct, builders ...
end
```


### 10.2 Behaviour vs protocol — the polymorphism decision

Elixir has two polymorphism mechanisms. Elixir-wide rule: **default to a plain module** — introduce either mechanism only when a real second implementation or test double exists.

> **Depth:** [idioms-reference.md](idioms-reference.md) §Protocols and §Behaviours — full templates including `@derive`, `@fallback_to_any`, `@undefined_impl_description`, `Enumerable`/`Collectable`/`Inspect` implementation patterns, `use` + `defoverridable`, Mox integration, consolidation, common anti-patterns. **Architectural decision** (behaviour design, contract evolution, protocol-on-struct strategy pattern): `../elixir-planning/architecture-patterns.md` §4.7–4.11.

**Quick decision:**

| When you need to... | Use |
|---|---|
| Dispatch on **module identity** chosen at config time (which mailer, which HTTP client) | Behaviour |
| Dispatch on **data type** (polymorphic serialization, iteration, inspection) | Protocol |
| Testable with Mox | Behaviour (Mox requires a behaviour) |
| Single implementation chosen per environment (test vs prod) | Behaviour + `Application.compile_env` |
| Many implementations, auto-dispatched by struct type | Protocol (`@derive` friendly) |
| Add behaviour to a type you don't own | Protocol (implement `defimpl` from your module) |
| Runtime-pluggable per-entity behaviour (not per-env) | Protocol-on-struct (see planning §4.6) |

### 10.3 Behaviours — define, implement, test

**Define the contract:**

```elixir
defmodule MyApp.Mailer do
  @type result :: :ok | {:error, term()}

  @callback send_welcome(User.t()) :: result()
  @callback send_reset(User.t(), token :: String.t()) :: result()

  @callback batch_send([User.t()]) :: result()
  @optional_callbacks batch_send: 1
end
```

**Implement it:**

```elixir
defmodule MyApp.Mailer.Swoosh do
  @behaviour MyApp.Mailer

  @impl true
  def send_welcome(user), do: # real Swoosh call
  @impl true
  def send_reset(user, token), do: # real Swoosh call
end
```

**`@impl` is mandatory** — the compiler catches typos (`hanle_call` vs `handle_call`) and missing implementations at compile time.

**Wire config — swap per environment:**

```elixir
# config/config.exs
config :my_app, :mailer, MyApp.Mailer.Swoosh

# config/test.exs
config :my_app, :mailer, MyApp.Mailer.Mock     # Mox.defmock/2

# Call site
@mailer Application.compile_env!(:my_app, :mailer)
def notify(user), do: @mailer.send_welcome(user)
```

**Testing with Mox:**

```elixir
# test/test_helper.exs
Mox.defmock(MyApp.Mailer.Mock, for: MyApp.Mailer)

# In a test
expect(MyApp.Mailer.Mock, :send_welcome, fn %User{email: "a@b.c"} -> :ok end)
assert :ok = MyApp.Onboarding.run(user)
```

**Defaults via `use`** when most implementations would share the same code:

```elixir
defmodule MyApp.Worker do
  @callback perform(map()) :: :ok | {:error, term()}
  @callback retry_delay(attempt :: non_neg_integer()) :: pos_integer()

  defmacro __using__(_) do
    quote do
      @behaviour MyApp.Worker
      @impl true
      def retry_delay(attempt), do: trunc(:math.pow(2, attempt) * 1_000)
      defoverridable retry_delay: 1
    end
  end
end
```

### 10.4 Protocols — define, implement, derive

**Define:**

```elixir
defprotocol MyApp.Printable do
  @spec print(t()) :: iodata()
  def print(term)
end
```

**Implement for structs:**

```elixir
defmodule MyApp.User do
  defstruct [:name, :email]

  defimpl MyApp.Printable do
    def print(%{name: n, email: e}), do: [n, " <", e, ">"]
  end
end
```

**Implement for built-in types** (`Atom`, `BitString`, `Integer`, `List`, `Map`, `Tuple`, etc.):

```elixir
defimpl MyApp.Printable, for: BitString do
  def print(s) when is_binary(s), do: s
end

defimpl MyApp.Printable, for: [Integer, Float] do
  def print(n), do: to_string(n)
end
```

**`@derive` — compile-time generated implementation:**

```elixir
defmodule MyApp.User do
  # @derive MUST come BEFORE defstruct
  @derive {Jason.Encoder, only: [:id, :name, :email]}    # selective JSON encoding
  @derive {Inspect, only: [:id, :name]}                   # hide password from logs
  defstruct [:id, :name, :email, :password_hash]
end
```

For foreign structs you don't own:

```elixir
require Protocol
Protocol.derive(Jason.Encoder, SomeLib.Thing, only: [:id])
```

**Anti-patterns:** `@derive` after `defstruct` (compiler warns, may not apply); `defimpl for: Map` expecting to match structs (structs dispatch separately); introducing a behaviour when a protocol fits (strategy-module is a behaviour; type-dispatch is a protocol).

### 10.5 Config strategy — when to use which

| Value | File | API |
|---|---|---|
| Known at compile time, application-owned | `config/config.exs` | `Application.compile_env(:my_app, :key)` |
| Runtime env var, per-deployment | `config/runtime.exs` | `System.fetch_env!/1`, `Application.get_env/2` |
| Library consumer configures at runtime | Caller's `config/*.exs` | `Application.get_env/3` (NEVER `compile_env` in a library) |
| Feature flag, toggleable at runtime | Database / FunWithFlags / Flagsmith | Library-specific |

```elixir
# Application code — compile_env is fine
defmodule MyApp.Cache do
  @ttl Application.compile_env!(:my_app, [:cache, :ttl])
  def ttl, do: @ttl
end

# LIBRARY code — use get_env so consumers can reconfigure after compilation
defmodule MyLib.Client do
  def api_key, do: Application.get_env(:my_lib, :api_key)
end
```

**Default for app-owned config: `compile_env`** — **but only when the value is truly frozen at compile time.** Reach for `get_env` when ANY of these are true:

- `config/runtime.exs` overrides the key from an env var (compile_env freezes the default; runtime.exs never takes effect).
- Tests override the key with `Application.put_env/3` (same reason — compile_env ignores runtime writes).
- The value can change during a running node (feature flag, per-request override).

If none of those apply, `compile_env` wins for three reasons:

1. **Dialyzer visibility** — `compile_env` embeds the concrete type; `get_env` returns `any()`.
2. **Fail-fast misconfiguration** — a missing required key crashes at compile, not at first use.
3. **Recompile trigger** — the compiler re-runs modules that depend on changed compile-env keys.

```elixir
# BAD — app-owned constant read on every call, returns any()
def default_timeout, do: Application.get_env(:my_app, :default_timeout, 5_000)

# GOOD — value is truly constant, no runtime.exs override, no test swap
@default_timeout Application.compile_env(:my_app, :default_timeout, 5_000)
def default_timeout, do: @default_timeout
```

```elixir
# When runtime.exs overrides the value, stay on get_env
# config/runtime.exs:
#   if config_env() == :prod do
#     config :my_app, port: System.get_env("MY_APP_PORT", "4040") |> parse_port()
#   end
#
# GOOD — get_env reflects the runtime.exs override at boot
def port, do: Application.get_env(:my_app, :port, 4040)
```

**Diagnostic:** before switching `get_env` to `compile_env`, grep for the key in `config/runtime.exs` AND in every test file. If either overrides it at runtime, leave `get_env` in place and document the choice in a moduledoc line — future reviewers will ask, and the answer should be findable.

#### 10.5.1 Centralize config reads in a `MyApp.Config` module

Scattered `Application.get_env/3` calls across dozens of modules are an anti-pattern: they hide what's configurable, they're hard to mock consistently, and they're hard to audit. Instead, every application should have a single `MyApp.Config` module whose public functions are zero-arg accessors. Every other module routes config reads through that module.

```elixir
defmodule MyApp.Config do
  @moduledoc """
  All application configuration accessors. Every `Application.get_env` /
  `compile_env` read for this app lives here and nowhere else.

  Benefits: `grep 'Application.get_env' lib/` should return zero hits outside
  this file. Tests swap values by `Application.put_env/3` in setup blocks and
  the accessors reflect the swap.
  """

  @spec database_url() :: String.t()
  def database_url, do: Application.fetch_env!(:my_app, MyApp.Repo)[:url]

  @spec signal_backend() :: module()
  def signal_backend, do: Application.fetch_env!(:my_app, MyApp.Signal)[:backend]

  @spec api_timeout_ms() :: pos_integer()
  def api_timeout_ms, do: Application.get_env(:my_app, :api_timeout_ms, 5_000)

  # Truly compile-time (no runtime.exs override, no test swap):
  @feature_flags Application.compile_env(:my_app, :feature_flags, [])
  @spec feature_flags() :: keyword()
  def feature_flags, do: @feature_flags
end
```

**In an umbrella,** each deployable app gets its own `MyApp.Config` (e.g., `Nodepulse.Config` for the central app, `NodepulseEdge.Config` for the edge app). Shared wire/protocol libs use the default Application env pattern so consumers configure them.

**Audit boundary discipline** with: `grep -rn 'Application.get_env\|Application.fetch_env\|Application.compile_env' lib/` — any hits outside the Config module are either (a) something that belongs in Config, or (b) deliberately local with a moduledoc explanation. Treat both as code-review checkpoints.

### 10.6 Ecto — the implementation boundary

**Never call `Repo` from a boundary layer (controller, LiveView, CLI). Always go through a context.**

```elixir
# BAD — Repo from a controller
def index(conn, _) do
  products = Repo.all(Product)
  render(conn, :index, products: products)
end

# GOOD — controller calls context
def index(conn, _) do
  products = Catalog.list_products()
  render(conn, :index, products: products)
end
```

**Context-level query function template:**

```elixir
defmodule MyApp.Catalog do
  import Ecto.Query

  @spec list_products(keyword()) :: [Product.t()]
  def list_products(opts \\ []) do
    opts = Keyword.validate!(opts, category: nil, in_stock: nil, limit: 50)

    Product
    |> maybe_filter_by_category(opts[:category])
    |> maybe_filter_by_stock(opts[:in_stock])
    |> limit(^opts[:limit])
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  defp maybe_filter_by_category(q, nil), do: q
  defp maybe_filter_by_category(q, c), do: where(q, [p], p.category == ^c)

  defp maybe_filter_by_stock(q, nil), do: q
  defp maybe_filter_by_stock(q, in_stock?), do: where(q, [p], p.in_stock == ^in_stock?)
end
```

#### 10.6.1 `Repo.insert_all` bypasses casts — pass raw DB representations

`Repo.insert_all/3` is schemaless by design: it does NOT run changeset validations, Ecto type casts, or `autogenerate` hooks. Rows are passed straight to the adapter. If a column needs a type round-trip, you pass the dumped form yourself:

| Column type | WRONG (string/atom) | RIGHT (raw representation) |
|---|---|---|
| `binary_id` / `Ecto.UUID` | `Ecto.UUID.generate/0` (36-char hex string) | `Ecto.UUID.bingenerate/0` (16-byte binary) |
| `Ecto.Enum` with atom values | `:active` | `"active"` (string) — or `Atom.to_string/1` |
| `:utc_datetime_usec` | `DateTime.utc_now/0` (mostly works) | `DateTime.utc_now/0 \|> DateTime.truncate(:microsecond)` |
| Custom `Ecto.Type` | any high-level value | `MyType.dump!(value)` (call `dump/1` manually) |

```elixir
# BAD — Postgrex raises "expected a binary of 16 bytes"
Repo.insert_all("rollups", [%{id: Ecto.UUID.generate(), bucket: ~U[2026-01-01 00:00:00Z]}])

# GOOD — binary UUID passed raw
Repo.insert_all("rollups", [%{id: Ecto.UUID.bingenerate(), bucket: ~U[2026-01-01 00:00:00Z]}])
```

This is a real recurring bug class. When in doubt with `insert_all`, prefer `Repo.insert_all(Schema, rows)` (with the schema module) — Ecto will then dump known fields through schema types. The bare-string table form `Repo.insert_all("table_name", rows)` assumes rows are already in DB form.

#### 10.6.2 `NaiveDateTime` leaks from string-source queries

Querying via a string source (`from(b in "rollups_1m", ...)` without a schema) returns `NaiveDateTime` for `:utc_datetime*` columns, regardless of how the column is stored. Ecto has no schema metadata to lift the value to `DateTime` — so downstream code that expects `DateTime.t()` will break.

```elixir
# BAD — assumes DateTime comes out, crashes on DateTime.diff/3
from(b in "rollups_1m", where: b.bucket > ^cutoff, select: b.bucket)
|> Repo.all()
# Returns [%NaiveDateTime{}, ...], not [%DateTime{}, ...]

# GOOD — normalize at the context boundary
defp normalize_bucket(%NaiveDateTime{} = n), do: DateTime.from_naive!(n, "Etc/UTC")
defp normalize_bucket(%DateTime{} = d), do: d
```

Prefer schema-bound queries whenever possible; reach for string sources only for reports, dynamic multi-tenant tables, or perf-critical bulk paths — and always wrap datetime fields through a `normalize_*` helper at the context boundary.

### 10.7 Struct vs map — decision table

| When you have... | Use |
|---|---|
| Known fields at compile time, owned by you | Struct (`defstruct`, `@enforce_keys`) |
| Dynamic keys, or shape varies | Map |
| External data (JSON, form params) at the boundary | Map with string keys — convert to struct inside |
| "Object-like" data with validation rules | Embedded Ecto schema (`embedded_schema`) |
| Parsed configuration | Struct with `@enforce_keys` |
| Options argument | Keyword list, validated with `Keyword.validate!/2` |

**Struct template:**

```elixir
defmodule MyApp.Settings do
  @enforce_keys [:env, :url]                      # Fail fast if these are missing
  defstruct [:env, :url, timeout: 5_000, retries: 3]

  @type t :: %__MODULE__{
          env: :dev | :staging | :prod,
          url: String.t(),
          timeout: non_neg_integer(),
          retries: non_neg_integer()
        }

  @spec new(keyword()) :: t()
  def new(attrs), do: struct!(__MODULE__, attrs)
end
```

### 10.8 Function placement — where does this code live?

| This function... | Belongs in |
|---|---|
| Transforms a domain struct (pure) | The struct's module (e.g., `User.full_name/1`) |
| Queries the DB for domain data | Context module (e.g., `Accounts.get_user!/1`) |
| Orchestrates multiple contexts or external services | Context module (e.g., `Accounts.register/1` calls Mailer) |
| Is a shared helper (string, number, date) | `MyApp.Utils.Foo` or dedicated helper module |
| Cross-cuts many modules (auth, rate limit, telemetry) | Plug / middleware / separate module |
| Is test-only | `test/support/*.ex` |
| Is a DSL / macro | Separate module, well-documented, usually internal |

### 10.9 File / module layout — canonical Phoenix-app example

```
lib/
  my_app/
    application.ex            # Application supervisor
    accounts.ex               # Accounts context (public API)
    accounts/
      user.ex                 # User schema + changeset
      session.ex              # Session schema
      authenticator.ex        # Password hashing (internal)
    catalog.ex
    catalog/
      product.ex
      price_calculator.ex
    orders.ex
    orders/
      order.ex
      line_item.ex
      workflow.ex
    mailer.ex                 # Behaviour
    mailer/
      swoosh.ex               # Real impl
  my_app_web/
    endpoint.ex
    router.ex
    controllers/...
    live/...
config/
  config.exs
  dev.exs
  test.exs
  runtime.exs
test/
  my_app/accounts_test.exs
  my_app/catalog_test.exs
  my_app_web/controllers/...
  support/
    data_case.ex
    factory.ex
    conn_case.ex
test_helper.exs
mix.exs
```
