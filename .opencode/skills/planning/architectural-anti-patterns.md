# Architectural Anti-Patterns — depth reference

> **Routing:** [SKILL.md](SKILL.md) §3 — BAD/GOOD patterns section.

---

## 1. Wrong module layout

**Severity:** BLOCK
**Why:** Importing `models/services/helpers` from other ecosystems produces flat, uncohesive namespaces that obscure domain boundaries and make Elixir tooling (contexts, behaviours) unusable.

```elixir
# BAD
lib/my_app/
├── models/
│   └── user.ex
├── services/
│   └── user_service.ex
└── helpers/
    └── format_helper.ex

# GOOD — Elixir domain-driven
lib/my_app/
├── accounts.ex
├── accounts/
│   ├── user.ex
│   └── authentication.ex
└── catalog.ex
```

## 2. Domain depending on framework

**Severity:** BLOCK
**Why:** Domain importing Phoenix/Plug makes domain logic untestable without the web framework and creates upward dependency (domain -> interface).

```elixir
# BAD — domain module references web layer
defmodule MyApp.Orders do
  alias MyAppWeb.Router.Helpers, as: Routes    # NEVER — domain depends on web!
  import Phoenix.Controller                     # NEVER — framework in domain!

  def complete_order(order) do
    url = Routes.order_url(MyAppWeb.Endpoint, :show, order)
    # ...
  end
end

# GOOD — domain is framework-agnostic
defmodule MyApp.Orders do
  def complete_order(order) do
    # Pure domain logic. URL generation belongs in controller/LiveView.
    with {:ok, order} <- mark_completed(order), do: {:ok, order}
  end
end
```

## 3. Interface layer calling Repo directly

**Severity:** WARN
**Why:** Bypasses context boundaries. Controllers/LiveViews coupled to schema details. Testing requires full DB setup for what should be unit-testable.

```elixir
# BAD — controller queries Repo
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

## 4. God context

**Severity:** WARN
**Why:** A context that owns users, products, payments, and notifications has no coherent domain. Changes for any reason touch the same module; teams step on each other.

```elixir
# BAD — god context with unrelated concerns
defmodule MyApp.Admin do
  def list_users, do: ...
  def create_product, do: ...
  def process_payment, do: ...
  def send_notification, do: ...
end

# GOOD — separate contexts per domain
defmodule MyApp.Accounts do ... end
defmodule MyApp.Catalog do ... end
defmodule MyApp.Billing do ... end
defmodule MyApp.Notifications do ... end
```

## 5. Tight coupling to external services

**Severity:** BLOCK
**Why:** Domain code that calls Stripe/Twilio/SendGrid directly cannot be tested without the service, cannot swap providers, and leaks foreign data types into domain logic.

```elixir
# BAD — domain tightly coupled to Stripe
defmodule MyApp.Billing do
  def charge(order) do
    Stripe.Charge.create(%{amount: order.total, source: order.token})
  end
end

# GOOD — behaviour-based abstraction
defmodule MyApp.Billing do
  @gateway Application.compile_env(:my_app, :payment_gateway)
  def charge(order), do: @gateway.charge(order.total, order.token)
end
```

## 6. Business logic in GenServer callbacks

**Severity:** WARN
**Why:** Business rules inside `handle_call`/`handle_cast` are untestable without spinning up a process. The domain logic is buried in OTP plumbing.

```elixir
# BAD — business logic in the callback
def handle_call({:apply_discount, code}, _from, state) do
  discount = case code do
    "SAVE10" -> Decimal.new("0.10")
    "SAVE20" -> Decimal.new("0.20")
    _ -> Decimal.new("0")
  end
  new_total = Decimal.mult(state.total, Decimal.sub(1, discount))
  {:reply, {:ok, new_total}, %{state | total: new_total}}
end

# GOOD — pure function for logic, GenServer just for state
defmodule MyApp.Pricing do
  def apply_discount(total, code), do: Decimal.mult(total, Decimal.sub(1, rate(code)))
  defp rate("SAVE10"), do: Decimal.new("0.10")
  defp rate("SAVE20"), do: Decimal.new("0.20")
  defp rate(_), do: Decimal.new("0")
end

def handle_call({:apply_discount, code}, _from, state) do
  new_total = MyApp.Pricing.apply_discount(state.total, code)
  {:reply, {:ok, new_total}, %{state | total: new_total}}
end
```

## 7. Premature umbrella split

**Severity:** WARN
**Why:** An umbrella with apps that depend on each other in every direction is a single app with extra build overhead. The split adds maintenance cost without providing real boundaries.

```
# BAD — premature umbrella
apps/
├── auth/               # Used by every other app
├── core/               # Used by every other app
├── web/                # Depends on auth, core, billing, catalog
├── billing/            # Depends on auth, core
├── catalog/            # Depends on auth, core
└── notifications/      # Depends on auth, core, billing, catalog

# GOOD — single app with clean contexts
lib/my_app/
├── accounts.ex
├── billing.ex
├── catalog.ex
└── notifications.ex
```

## 8. Wrong supervision strategy

**Severity:** BLOCK
**Why:** Registry + DynamicSupervisor under `:one_for_one` means a Registry crash leaves DynamicSupervisor children orphaned with no way to re-register. The system enters an inconsistent state silently.

```elixir
# BAD — Registry + DynamicSupervisor under :one_for_one
children = [
  {Registry, keys: :unique, name: MyApp.Registry},
  {DynamicSupervisor, name: MyApp.DynSup}
]
Supervisor.init(children, strategy: :one_for_one)   # WRONG — Registry crash leaves workers orphaned

# GOOD — tightly coupled processes under :one_for_all (or a sub-supervisor with :rest_for_one)
Supervisor.init(children, strategy: :one_for_all)
```

## 9. Simulating objects with processes

**Severity:** BLOCK
**Why:** One Agent/GenServer per domain concept (cart, inventory, order) converts simple function calls into cross-process messaging. Adds latency, complexity, and makes coordination between concepts require distributed protocols.

```elixir
# BAD — one Agent per domain concept
cart_agent = Agent.start_link(fn -> Cart.new() end)
inventory_agent = Agent.start_link(fn -> Inventory.new(products) end)
# Every operation needs cross-process messaging to coordinate!

# GOOD — pure functional abstractions
cart = Cart.new()
{:ok, item, inventory} = Inventory.take(inventory, sku)
cart = Cart.add(cart, item)
```

**Rule:** Use functions and modules to separate *thought* concerns. Use processes to separate *runtime* concerns (fault isolation, parallelism, independent lifecycles). If things always change together, keep them together.

## 10. Mock lies about real behavior

**Severity:** WARN
**Why:** A mock that always returns `:ok` means tests never exercise error paths. Production crashes on `{:error, _}` because no code handles it.

```elixir
# BAD — mock always returns :ok; hides error paths
Mox.expect(PaymentMock, :charge, fn _, _ -> {:ok, %{id: "tx_123"}} end)
# Tests pass; production crashes on {:error, _} because no code handles it.

# GOOD — test both success AND error paths
test "handles payment failure" do
  Mox.expect(PaymentMock, :charge, fn _, _ -> {:error, :card_declined} end)
  assert {:error, :payment_failed} = Orders.complete_order(order)
end
```

## 11. Shared database between contexts

**Severity:** BLOCK
**Why:** Two contexts writing to the same table means invariants are split, migrations affect both, and data ownership is ambiguous. The "shared database" anti-pattern from microservices, imported into a monolith.

```elixir
# BAD — two contexts writing to the same table
defmodule MyApp.Accounts do
  def update_last_login(user_id), do: Repo.update(...)
end
defmodule MyApp.Analytics do
  def track_login(user_id), do: Repo.update_all(...)  # Also writes users table!
end

# GOOD — one context owns the write; other context is a consumer
defmodule MyApp.Accounts do
  def update_last_login(user_id), do: ...
  # Publishes an event; Analytics subscribes
end
defmodule MyApp.Analytics do
  def handle_info({:user_logged_in, user_id}, state), do: ...
  # Stores analytics in its own tables
end
```

## 12. Cross-context `Repo.preload`

**Severity:** WARN
**Why:** `Repo.preload(:orders)` in the Accounts context reaches into Orders' internal schema. Accounts now depends on Orders' table structure, not its public API.

```elixir
# BAD — reaching into another context's data with preload
users = MyApp.Accounts.list_users()
|> Repo.preload(orders: :items)    # Orders + items belong to Orders context!

# GOOD — context provides the data shape
users_with_orders = MyApp.Orders.list_users_with_orders(user_ids)
# Orders context assembles the data, exposes it as a well-defined shape
```

## 13. Microservices split for "loose coupling"

**Severity:** WARN
**Why:** OTP already provides loose coupling (behaviours + PubSub), fault isolation (supervision), and independent scaling (process pools). Splitting adds network hops, distributed transactions, and deployment complexity.

- "We want loose coupling" -> use behaviours and PubSub
- "We want fault isolation" -> use supervision trees
- "We want independent scaling" -> use process pools, Task.async_stream, Broadway
- "It's getting big" -> add contexts

**Microservices are justified for: different languages, compliance isolation, org-level autonomy, or genuinely wildly different scaling needs.** Never for "it feels like it should be."

## 14. LiveView stream rendering off external assigns

**Severity:** BLOCK
**Why:** LiveView streams only re-render rows you `stream_insert`. Updating a separate assign (even one the row template reads) does NOT redraw the row — the DOM stays stale. This is a planning-level bug because the fix requires schema changes, context function changes, and often Postgres-side shape changes.

```
# BAD — design-time shape
Socket assigns:
  :devices (stream)           <- rendered row
  :device_states (%{id => state}) <- influences row rendering
  :cluster_status             <- influences row rendering

handle_info({:device_state_changed, ...}) -> update(:device_states, ...)
  # Row DOM is NOT re-emitted. UI goes stale.

# GOOD — design-time shape
Device schema has virtual :current_state field.
Context function: Fleet.list_with_state/0 populates :current_state.
Stream member carries all row-rendering data.

handle_info({:device_state_changed, id, new_state}) ->
  stream_insert(socket, :devices, Fleet.get_device_with_state!(id))
```

**Planning rule:** stream members carry everything a row needs to render. Any state that changes per-row goes on the member, not on a separate assign.

---

## 15. Cross-references

- [SKILL.md](SKILL.md) §3 — BAD/GOOD patterns section
- [architecture-patterns.md](architecture-patterns.md) — correct patterns for each anti-pattern above
- [process-topology.md](process-topology.md) §11 — process design mistakes
- [integration-patterns.md](integration-patterns.md) §15 — integration mistakes
- [growing-evolution.md](growing-evolution.md) §12 — evolution mistakes

---

**End of architectural-anti-patterns.md.** For the correct patterns, see [architecture-patterns.md](architecture-patterns.md) and the routing core [SKILL.md](SKILL.md).
