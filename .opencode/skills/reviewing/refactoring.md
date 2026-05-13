---
name: refactoring
description: >
  Tech debt identification and safe refactoring. ALWAYS use when reviewing duplication,
  oversized modules, mixed concerns, or deciding whether to extract code. For code quality
  gates → load quality-gates. For performance-driven refactoring → load observability.
---

# Tech Debt and Refactoring

Refactoring reduces the cost of future changes. This skill covers when to refactor
(triggers), how to refactor safely (rules), and what to extract (patterns). The key
principle: extract only after patterns repeat or boundaries are clearly wrong.

## 1. Rules

1. **Search before extracting** -- the function or module you want to create may already exist. Check contexts, shared modules, and utilities first.
2. **Prefer smaller focused functions before new modules** -- extract a private function first. Promote to a new module only when the function is needed across boundaries.
3. **Extract only after patterns repeat (3+ times) or boundaries are clearly wrong** -- early abstraction after one use creates speculative architecture.
4. **Keep tests green before and after refactors** -- run the relevant test suite before starting and after each extraction step.
5. **Refactor along ownership lines** -- web, context, worker, component. Do not create cross-cutting "helper" modules that blur boundaries.
6. **Never refactor without sufficient test coverage around current behavior** -- if the code has no tests, write characterization tests first.
7. **One refactoring per commit** -- makes each change reviewable and revertible.
8. **Use `mix ex_dna` or `find_code_clones` to detect duplication quantitatively** -- gut feeling misses scattered clones.

## 2. Decision Table

| Intent / Situation | Action | Avoid | Why |
|---|---|---|---|
| Same query logic appears 3+ times | Extract to context function with clear name | Leaving duplicates; generic `QueryHelper` module | Contexts own query logic; helpers blur boundaries |
| Same changeset fragment in multiple changesets | Extract to a dedicated helper function in the schema module | New `ChangesetHelpers` module | Keep changeset logic near the schema it validates |
| Module has 500+ lines | Look for natural seams (groups of functions with shared prefix); split along them | Splitting arbitrarily by line count | Split by responsibility, not size |
| LiveView file > 300 lines | Extract function components for template sections; extract event handlers to context | Creating LiveComponents for everything | Function components are simpler; LiveComponents add state complexity |
| Web layer calls `Repo` directly | Move query to context module; web layer calls context | Leaving `Repo.all` in controllers/LiveViews | Contexts encapsulate data access; web layer handles HTTP/WS concerns |
| LiveView owns domain logic (validation, policy) | Move to context; LiveView calls context and handles UI response | Keeping business rules in `handle_event` | Domain logic must be testable without LiveView |
| Worker mixes domain prep with side effects | Extract pure preparation into context/service; worker orchestrates | Keeping 100+ lines of domain logic in `perform/1` | Workers should be thin orchestrators |
| Code is duplicated but only used twice | Leave it; add a comment noting the duplication | Extracting a shared function prematurely | Two uses is coincidence; three is a pattern |
| Unused code detected | Delete it (check with `mix xref` first) | Commenting it out "just in case" | Dead code is maintenance burden; git has history |
| Large `case` or `cond` with 5+ branches | Consider multi-clause function heads or a dispatch map | Leaving a giant case block | Pattern-matched heads are the Elixir idiom; easier to extend |
| Test file > 500 lines | Extract shared setup into `describe` blocks or test helper module | One giant test module | Grouped tests are easier to run selectively and maintain |

## 3. Patterns

### 3.1 Generic Helper Module

**Severity:** WARN

```elixir
# BAD -- cross-cutting helper with no domain boundary
defmodule MyApp.Helpers do
  def format_date(date), do: ...
  def validate_email(email), do: ...
  def calculate_tax(amount, rate), do: ...
  def truncate_string(str, len), do: ...
end

# GOOD -- functions live in the context they belong to
defmodule MyApp.Accounts do
  def validate_email(email), do: ...
end

defmodule MyApp.Orders do
  def calculate_tax(amount, rate), do: ...
end

# For truly shared utilities (formatting), use a focused utility module
defmodule MyApp.Format do
  def date(date), do: ...
  def truncate(str, len), do: ...
end
```

**Why:** Generic helpers become dumping grounds. Every developer adds "just one more function" until the module has 50 unrelated functions. Domain-aligned modules are discoverable and maintainable.

### 3.2 Early Abstraction After One Use

**Severity:** WARN

```elixir
# BAD -- extracting a "pattern" after seeing it once
defmodule MyApp.Patterns.StatusTransition do
  def transition(entity, from, to, opts \\ []) do
    # Complex generic transition logic
    # Only used by Order so far
  end
end

# GOOD -- inline the logic until a second use case appears
defmodule MyApp.Orders do
  def complete_order(%Order{status: :pending} = order) do
    order
    |> Order.changeset(%{status: :completed, completed_at: DateTime.utc_now()})
    |> Repo.update()
  end
end
# When Shipments also needs transitions, THEN extract
```

**Why:** Premature abstractions guess at the wrong boundaries. The second and third use cases reveal what the abstraction should actually look like. Wait for the evidence.

### 3.3 Repo Calls in Web Layer

**Severity:** BLOCK

```elixir
# BAD -- LiveView directly queries the database
@impl true
def handle_event("search", %{"q" => query}, socket) do
  results = MyApp.Repo.all(
    from p in Product,
    where: ilike(p.name, ^"%#{query}%"),
    limit: 20
  )
  {:noreply, assign(socket, :results, results)}
end

# GOOD -- context owns the query
# In MyApp.Catalog context:
def search_products(query, opts \\ []) do
  limit = Keyword.get(opts, :limit, 20)
  from(p in Product, where: ilike(p.name, ^"%#{query}%"), limit: ^limit)
  |> Repo.all()
end

# In LiveView:
@impl true
def handle_event("search", %{"q" => query}, socket) do
  results = Catalog.search_products(query)
  {:noreply, assign(socket, :results, results)}
end
```

**Why:** Repo calls in LiveViews/controllers make the query untestable without a full LiveView test, duplicate query logic across views, and violate Phoenix's context-based architecture.

### 3.4 Refactoring Without Tests

**Severity:** BLOCK

```elixir
# BAD -- "I'll extract this function and hope nothing breaks"
# (no tests exist for the current behavior)

# GOOD -- write characterization tests first
describe "order completion" do
  test "marks order as completed with timestamp" do
    order = insert(:order, status: :pending)
    assert {:ok, completed} = Orders.complete_order(order)
    assert completed.status == :completed
    assert completed.completed_at != nil
  end

  test "rejects already completed orders" do
    order = insert(:order, status: :completed)
    assert {:error, _} = Orders.complete_order(order)
  end
end

# NOW refactor with confidence
```

**Why:** Without tests, you cannot verify that the refactored code preserves existing behavior. Characterization tests document what the code currently does, then act as a safety net during extraction.

### 3.5 Monolithic LiveView

**Severity:** WARN

```elixir
# BAD -- 400-line LiveView that handles everything
defmodule MyAppWeb.DashboardLive do
  # 50 lines of mount/handle_params
  # 100 lines of handle_event (8 different events)
  # 200 lines of template with inline logic
  # 50 lines of private helpers
end

# GOOD -- decomposed along responsibility boundaries
defmodule MyAppWeb.DashboardLive do
  # Mount and top-level state
  # Delegates to context for data
  # Template composes function components
end

# Function components for template sections
defmodule MyAppWeb.DashboardComponents do
  def stats_panel(assigns), do: ...
  def recent_activity(assigns), do: ...
  def quick_actions(assigns), do: ...
end
```

**Why:** Large LiveViews are hard to test, hard to review, and hard to modify. Function components extract template sections without adding process overhead. Context functions extract business logic.

## 4. Checklist

- [ ] Searched for existing implementations before extracting
- [ ] Pattern repeats 3+ times (or boundary is clearly wrong)
- [ ] Tests exist and pass before refactoring
- [ ] Extraction follows ownership lines (web/context/worker/component)
- [ ] No generic "helper" or "utils" modules created
- [ ] Tests pass after refactoring
- [ ] `mix ex_dna` or `find_code_clones` run to check for remaining duplication
- [ ] Each refactoring step is a separate commit

## 5. Routing

| If you need... | Load instead |
|---|---|
| Code quality and static analysis | `quality-gates` |
| Detecting duplication quantitatively | `quality-gates` (ex_dna) |
| Performance-driven optimization | `observability` |
| Ecto query extraction patterns | `ecto` |
| LiveView component decomposition | `liveview-components` |
| BEAM tools for code analysis | `beam-introspection` |

## Common Extractions Reference

| Smell | Extract To | Effort |
|---|---|---|
| Repeated query filters | Context function | Low |
| Repeated changeset fragments | Schema helper function | Low |
| Large template sections | Function components | Low |
| Complex event handling | Context functions (logic) + smaller handlers | Medium |
| Mixed worker/domain logic | Context (pure logic) + thin worker | Medium |
| Cross-context shared logic | Shared context or domain service | Medium-High |
| Duplicated test setup | Test helper module / shared `setup` | Low |
