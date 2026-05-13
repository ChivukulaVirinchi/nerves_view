# Domain Boundaries (Contexts) — depth reference

A context is a module that groups related functionality behind a public API. Phoenix calls them "contexts"; the pattern is framework-agnostic and works in any Elixir application. **The boundary module is the only public entry point. Internal modules are hidden behind `@moduledoc false`.**

> **Routing:** [SKILL.md](SKILL.md) §2 — Master Decision Table, row 3.2 (Domain boundaries).
> **Related depth:** [data-ownership.md](data-ownership.md) — aggregate design, context boundaries, multi-tenancy. [architecture-patterns.md](architecture-patterns.md) §3.4 — context design within a modular monolith.

---

## 1. Entities vs use cases

Domain code has two kinds of logic. Distinguish them when designing.

**Entities** — core business rules that exist regardless of the application. Pure data structures with functions that enforce invariants:

```elixir
defmodule MyApp.Orders.Order do
  @moduledoc false
  defstruct [:id, :items, :status, :total]

  def calculate_total(%__MODULE__{items: items}) do
    Enum.reduce(items, Decimal.new(0), &Decimal.add(&2, &1.subtotal))
  end

  def can_cancel?(%__MODULE__{status: status}), do: status in [:pending, :confirmed]
end
```

**Use cases** — application-specific orchestration. Each public function in a context module is a use case. It coordinates entities, calls infrastructure through behaviours, returns `{:ok, _} | {:error, _}`:

```elixir
defmodule MyApp.Orders do
  @moduledoc "Order lifecycle — placement, cancellation, fulfillment."
  alias MyApp.Orders.Order

  def cancel_order(order_id) do
    with {:ok, order} <- fetch_order(order_id),
         true <- Order.can_cancel?(order),
         {:ok, order} <- mark_cancelled(order),
         :ok <- notify_cancellation(order) do
      {:ok, order}
    else
      false -> {:error, :not_cancellable}
      error -> error
    end
  end
end
```

**For most Elixir applications**, keep entities as internal modules (`@moduledoc false`) and use cases as public context functions. Separate them explicitly only when entity rules are complex enough to warrant independent testing and reuse across multiple use cases.

## 2. When to create a new context

**Create a new context when:**

- Different business domain (Catalog vs. ShoppingCart vs. Accounts)
- Different teams will own the code
- Data has a distinct lifecycle (orders vs. products)
- Entities have different consistency requirements
- When in doubt — prefer separate contexts. Merging is easier than splitting later.

**DON'T split when:**

- Entities share the same aggregate root (Order and OrderItem — same context)
- Operations always change together in a transaction
- Splitting would require constant cross-context calls
- The contexts would be thin wrappers around a shared set of operations

**Smell tests that say "split this":**

- The context file is over ~800 lines of public functions
- Two clusters of functions never reference each other's data
- Different teams keep stepping on each other's changes
- One set of functions changes for reason A, another for reason B (single-responsibility violation)

## 3. Aggregates — the consistency boundary

An **aggregate** is a cluster of entities that must be consistent as a unit. The **aggregate root** is the entity you load, validate, and save as a whole. In Ecto this maps to `cast_assoc` / `cast_embed`:

```elixir
defmodule MyApp.Orders.Order do
  use Ecto.Schema

  schema "orders" do
    field :status, Ecto.Enum, values: [:pending, :confirmed, :shipped]
    has_many :items, MyApp.Orders.OrderItem, on_replace: :delete
    timestamps()
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [:status])
    |> cast_assoc(:items)                    # Items validated + saved WITH the order
    |> validate_at_least_one_item()
  end
end

# Context operates on the aggregate root, never individual items
defmodule MyApp.Orders do
  def add_item(order, item_attrs) do
    items = order.items ++ [item_attrs]
    update_order(order, %{items: items})     # Whole aggregate saved together
  end
end
```

**Aggregate rules:**

- Never load or save parts of an aggregate independently — always go through the root
- Each aggregate is a transaction boundary — one `Repo.insert`/`update` per aggregate
- Different aggregates communicate through the context's public API, not direct associations
- If two entities must be consistent, they belong in the same aggregate, and therefore the same context

## 4. Boundary structure template

```elixir
# With Ecto (Phoenix, database-backed apps)
defmodule MyApp.Catalog do
  @moduledoc "Product catalog management."

  import Ecto.Query, warn: false
  alias MyApp.Repo
  alias MyApp.Catalog.{Product, Category}

  # Queries
  def list_products, do: Repo.all(Product)
  def get_product!(id), do: Repo.get!(Product, id)

  # Commands
  def create_product(attrs \\ %{}) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end
end

# Without Ecto (Nerves, CLI, pure OTP services)
defmodule MyFirmware.Sensors do
  @moduledoc "Sensor reading and calibration."
  alias MyFirmware.Sensors.{Reader, Calibration}

  defdelegate read(sensor_id), to: Reader
  defdelegate calibrate(sensor_id, reference), to: Calibration

  def read_calibrated(sensor_id) do
    with {:ok, raw} <- Reader.read(sensor_id),
         {:ok, cal} <- Calibration.get(sensor_id) do
      {:ok, Calibration.apply(raw, cal)}
    end
  end
end
```

**Internal modules are private to the boundary:**

```elixir
defmodule MyApp.Catalog.Product do
  @moduledoc false                          # Internal — not part of public API
  use Ecto.Schema
  # ...
end
```

**Context organization inside a context:**

```
lib/my_app/catalog/
├── product.ex              # Schema (internal)
├── category.ex             # Schema (internal)
├── product_queries.ex      # Complex query builders (internal)
├── import_worker.ex        # Background processing (internal)
└── price_calculator.ex     # Pure business logic (internal)
```

All internal modules are private. Only `MyApp.Catalog` is the public API.

## 5. Context relationships (context mapping)

Contexts don't exist in isolation — they relate to each other in specific ways.

| Relationship | Meaning | Elixir implementation |
|---|---|---|
| **Shared kernel** | Two contexts share a data structure | Shared module in a common namespace (e.g., `MyApp.Shared.Money`) |
| **Customer-supplier** | One context serves another | Supplier exposes public API, customer calls it |
| **Conformist** | You adapt to an external model | Anti-corruption layer translates their types to yours |
| **Separate ways** | Contexts are independent | No direct communication, possibly PubSub |

**Boundary atom-safety discipline:** every external string identifier crossing into a context — sort key from a query string, action name from a webhook, role name from a JWT claim, channel topic suffix — stays a string OR converts via `String.to_existing_atom/1` against a closed allowlist (`Ecto.Enum` is the canonical pattern). Never `String.to_atom/1` on request data.

## 6. Anti-corruption layer (ACL)

When integrating with external or legacy systems, translate their data model to yours at the boundary. **Never let foreign data structures leak into your domain.**

```elixir
# BAD — external API's data model leaks into domain
def process_payment(stripe_charge) do
  if stripe_charge["status"] == "succeeded" do
    update_order(stripe_charge["metadata"]["order_id"], stripe_charge["amount"])
  end
end

# GOOD — anti-corruption layer translates at the boundary
defmodule MyApp.PaymentGateway.Stripe do
  @behaviour MyApp.PaymentGateway

  @impl true
  def charge(amount, token) do
    case Stripe.Charge.create(%{amount: amount, source: token}) do
      {:ok, charge} -> {:ok, to_domain_result(charge)}
      {:error, err} -> {:error, to_domain_error(err)}
    end
  end

  # Translation layer — Stripe's model -> our domain model
  defp to_domain_result(charge) do
    %{transaction_id: charge.id, amount: charge.amount, captured_at: DateTime.utc_now()}
  end

  defp to_domain_error(%{code: "card_declined"}), do: :card_declined
  defp to_domain_error(%{code: "expired_card"}), do: :card_expired
  defp to_domain_error(_), do: :payment_failed
end
```

**Rule:** The behaviour adapter IS the anti-corruption layer. All translation between external and domain models happens in the adapter module. Domain code never sees external data structures.

## 7. API design for contexts

When designing a context's public API:

| Design choice | Why |
|---|---|
| Each public function is a use case | Not just a CRUD wrapper — name it by business intent (`register_user`, not `insert_user`) |
| Return `{:ok, _} / {:error, _}` | Consistent, composable with `with` |
| Keyword options at the end | Easy to extend without breaking callers |
| Validate options with `Keyword.validate!/2` | Reject typos, document accepted options |
| `defdelegate` for pure pass-through to internals | Keeps context as a clean facade |
| Regular `def` when you add logging, telemetry, cross-cutting logic | The context is more than a namespace — it's the place for cross-cutting concerns |
| **Decide opacity for every struct that crosses the boundary** | Without this, the struct's field shape silently becomes part of your public API. Once 11 callers destructure it, renaming a field is a breaking change. Pick "opaque handle" (MapSet/Ecto.Query -- `@opaque` + accessor functions) or "public data structure" (Plug.Conn/Date -- fields documented as API) **explicitly per struct**. Defer to [architecture-patterns.md §4.12](architecture-patterns.md) for the decision table, mechanics, and migration path. |

```elixir
defmodule MyApp.Catalog do
  # Pure pass-through — defdelegate
  defdelegate get_product!(id), to: Product, as: :fetch!

  # Wrapper with cross-cutting concerns
  def calculate_price(product, qty) do
    product
    |> PriceCalculator.total(qty)
    |> tap(fn total -> :telemetry.execute([:catalog, :priced], %{total: total}) end)
  end

  # Keyword options pattern
  def list_products(opts \\ []) do
    opts = Keyword.validate!(opts, category: nil, in_stock: nil, limit: 50)
    # ...
  end
end
```

---

## 8. Cross-references

- [SKILL.md](SKILL.md) §2 row 3.2 — domain boundaries decision table
- [data-ownership.md](data-ownership.md) — aggregate design, multi-tenancy, cross-context transactions
- [architecture-patterns.md](architecture-patterns.md) §3.4 — context design within a modular monolith
- [architecture-patterns.md](architecture-patterns.md) §4.12 — boundary opacity (opaque vs public structs)
- [growing-evolution.md](growing-evolution.md) §6 — context redraw (changing boundaries)
- [integration-patterns.md](integration-patterns.md) — how contexts communicate

---

**End of domain-boundaries.md.** For data ownership and consistency rules, see [data-ownership.md](data-ownership.md). For how contexts communicate, see [integration-patterns.md](integration-patterns.md).
