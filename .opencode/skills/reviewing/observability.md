---
name: observability
description: >
  Performance measurement and observability for Elixir/Phoenix. ALWAYS use when reviewing
  query costs, LiveView responsiveness, telemetry setup, memory/process usage, or worker
  throughput. For BEAM runtime tools → load beam-introspection. For refactoring decisions
  → load refactoring.
---

# Performance and Observability

Never optimize without measuring first. This skill covers what to measure, how to
measure it, and which tool to reach for. The goal is evidence-based optimization:
identify the bottleneck, measure it, fix it, verify the improvement.

## 1. Rules

1. **Measure before optimizing** -- profile first, then fix the measured bottleneck. Guessing wastes effort.
2. **Check for N+1 queries before adding caching** -- the most common Phoenix performance issue is hidden N+1s, not missing caches.
3. **Inspect query counts and indexes before micro-optimizing Elixir code** -- database round-trips dominate response time in most web apps.
4. **Use telemetry events, not `IO.inspect` timing** -- `:telemetry.span/3` integrates with dashboards; `IO.inspect` is throwaway.
5. **Stream large LiveView collections** -- `stream/3` sends diffs; list assigns re-send the entire collection on every update.
6. **Avoid assigning large derived data in LiveView** -- compute in the template or assign incrementally. Large assigns cause big diffs.
7. **Preload associations when templates touch them** -- every `assoc.field` in a template without preload is an N+1 query.
8. **Batch database writes** -- `insert_all`/`update_all` for bulk operations; individual `Repo.insert` in a loop is O(n) round-trips.
9. **Size Oban queues to real throughput limits** -- match concurrency to API rate limits and CPU cores, not arbitrary numbers.

## 2. Decision Table

| Intent / Situation | Use | Avoid | Why |
|---|---|---|---|
| Slow page load, unknown cause | `mix phx.routes` + browser devtools network tab + `Ecto.LogEntry` | Guessing which query is slow | Measure total time, then drill into DB vs render vs network |
| Suspected N+1 queries | Enable `Ecto.LogEntry`, count queries per request; or `project_eval` with `Ecto.Adapters.SQL.log/2` | Adding a cache layer | N+1 is O(n) queries; fix with preload, not cache |
| Slow Ecto query | `EXPLAIN ANALYZE` via `execute_sql_query`; check missing indexes | Rewriting the query in Elixir | The DB query planner shows the actual bottleneck (seq scan, sort, etc.) |
| LiveView feels sluggish | Check assign sizes with `get_process_info`; check diff size in browser WS inspector | Adding JS optimizations | Large assigns or broad re-renders cause big WS diffs |
| Large collection in LiveView | `stream/3` with `stream_insert`/`stream_delete` | List assign with full re-render | Streams send only changed items; lists re-send everything |
| Memory usage growing | `:erlang.memory()`, `get_top_processes` sorted by memory | Restarting the app periodically | Find the process/ETS table consuming memory; fix the leak |
| Process mailbox growing | `get_top_processes` sorted by message_queue_len | Increasing timeout | Growing mailboxes mean the process cannot keep up; reduce input rate or increase parallelism |
| Profiling a specific function | `:timer.tc/1` for quick; `:eprof` or `:fprof` for detailed | `IO.inspect` with timestamps | Profilers measure actual CPU time, not wall clock; handle concurrent code correctly |
| Setting up telemetry | `:telemetry.attach/4` + `:telemetry.span/3` | Custom GenServer for metrics | Telemetry is the standard; integrates with LiveDashboard, StatsD, Prometheus |
| Monitoring in production | LiveDashboard, `telemetry_metrics` + reporter | Custom health-check endpoints | Standard tools; no maintenance burden |
| Oban queue throughput | Check `oban_jobs` table: completed_at - attempted_at per queue | Guessing concurrency settings | Actual execution time shows if workers are CPU-bound or I/O-bound |
| Template rendering slow | Profile with `:fprof`; check for function calls in templates | Caching rendered HTML | Templates should be thin; move computation to assigns |

## 3. Patterns

### 3.1 Optimizing Without Measurement

**Severity:** BLOCK

```elixir
# BAD -- adding ETS cache without knowing the actual bottleneck
defmodule MyApp.Cache do
  use GenServer
  # ... 50 lines of caching infrastructure ...
end

# GOOD -- measure first, then decide
# Step 1: Count queries per request
Logger.configure(level: :debug)
# Check Ecto logs: how many queries per page load?

# Step 2: Profile the slow path
:timer.tc(fn -> MyApp.Orders.list_with_items(user_id) end)

# Step 3: Fix the measured issue (e.g., missing preload)
def list_with_items(user_id) do
  Order
  |> where(user_id: ^user_id)
  |> preload(:items)  # was missing -- caused N+1
  |> Repo.all()
end
```

**Why:** Caching adds complexity (invalidation, consistency, memory). The actual issue is usually a missing preload or index. Measure to find the real bottleneck.

### 3.2 N+1 Hidden in Analytics Code

**Severity:** BLOCK

```elixir
# BAD -- N+1 hidden in reporting; each order triggers a query for items
def generate_report(orders) do
  Enum.map(orders, fn order ->
    items = Repo.all(from i in Item, where: i.order_id == ^order.id)
    %{order: order.id, total: Enum.sum(Enum.map(items, & &1.price))}
  end)
end

# GOOD -- preload or join upfront
def generate_report(user_id) do
  from(o in Order,
    where: o.user_id == ^user_id,
    join: i in assoc(o, :items),
    group_by: o.id,
    select: %{order: o.id, total: sum(i.price)}
  )
  |> Repo.all()
end
```

**Why:** Analytics/reporting code is often written quickly and runs less frequently, so N+1 patterns hide there longer. A report over 1000 orders becomes 1001 queries.

### 3.3 Giant LiveView Assigns

**Severity:** WARN

```elixir
# BAD -- re-sending entire list on every event
@impl true
def handle_event("toggle", %{"id" => id}, socket) do
  items = Enum.map(socket.assigns.items, fn
    %{id: ^id} = item -> %{item | selected: !item.selected}
    item -> item
  end)
  {:noreply, assign(socket, :items, items)}  # full list diff every time
end

# GOOD -- use streams for collections
@impl true
def mount(_params, _session, socket) do
  {:ok, stream(socket, :items, Items.list_items())}
end

@impl true
def handle_event("toggle", %{"id" => id}, socket) do
  item = Items.toggle_item!(id)
  {:noreply, stream_insert(socket, :items, item)}  # only sends the changed item
end
```

**Why:** List assigns send the full list over the WebSocket on every change. With 500 items, that is 500 items diffed and transmitted per click. Streams send only the changed item.

### 3.4 IO.inspect Timing

**Severity:** SUGGEST

```elixir
# BAD -- throwaway timing that doesn't integrate with monitoring
start = System.monotonic_time(:millisecond)
result = expensive_operation()
IO.inspect(System.monotonic_time(:millisecond) - start, label: "elapsed")

# GOOD -- telemetry span integrates with dashboards
:telemetry.span([:my_app, :expensive_op], %{}, fn ->
  result = expensive_operation()
  {result, %{}}
end)

# Attach a handler (in Application.start or a dedicated module)
:telemetry.attach("log-expensive", [:my_app, :expensive_op, :stop], fn _event, measurements, _meta, _config ->
  Logger.info("expensive_op took #{measurements.duration / 1_000_000}ms")
end, nil)
```

**Why:** Telemetry events are the standard for Elixir/Phoenix observability. They integrate with LiveDashboard, StatsD, Prometheus, and Datadog. `IO.inspect` timing is deleted after debugging.

### 3.5 Individual Inserts in a Loop

**Severity:** WARN

```elixir
# BAD -- N database round-trips
Enum.each(items, fn item ->
  Repo.insert!(%LineItem{order_id: order.id, product_id: item.product_id, qty: item.qty})
end)

# GOOD -- single round-trip
line_items = Enum.map(items, fn item ->
  %{order_id: order.id, product_id: item.product_id, qty: item.qty,
    inserted_at: now, updated_at: now}
end)
Repo.insert_all(LineItem, line_items)
```

**Why:** Each `Repo.insert` is a network round-trip to PostgreSQL (~0.5-2ms). With 100 items, that is 100-200ms of pure latency. `insert_all` sends one query.

## 4. Checklist

- [ ] Measured the actual bottleneck before optimizing
- [ ] Checked Ecto query count per request (no N+1)
- [ ] LiveView collections use `stream/3` (not list assigns)
- [ ] Bulk operations use `insert_all`/`update_all`
- [ ] Associations are preloaded where templates access them
- [ ] Telemetry events used for production monitoring (not `IO.inspect`)
- [ ] Oban queue concurrency matches actual throughput needs

## 5. Routing

| If you need... | Load instead |
|---|---|
| BEAM runtime tools (eval, process inspection) | `beam-introspection` |
| Refactoring duplicated or oversized code | `refactoring` |
| Ecto query optimization patterns | `ecto` |
| LiveView stream patterns | `liveview-streams` |
| Oban queue design | `oban` |
| Quality checks before shipping | `quality-gates` |

## Runtime Checks Quick Reference

| What to Check | Tool | Command/Pattern |
|---|---|---|
| System memory | `project_eval` | `:erlang.memory()` |
| Top processes by memory | `get_top_processes` | Sort by memory |
| Top processes by mailbox | `get_top_processes` | Sort by message_queue_len |
| ETS table sizes | `project_eval` | `:ets.all() \|> Enum.map(&:ets.info/1) \|> Enum.sort_by(& &1[:memory], :desc)` |
| Scheduler utilization | `project_eval` | `:scheduler.utilization(5)` (OTP 21+) |
| LiveView mount smoke test | `smoke_test` | Check mount-time failures |
| Query plan analysis | `execute_sql_query` | `EXPLAIN ANALYZE SELECT ...` |
| GenServer state size | `get_process_info` | `include_state: true` |

## Profiling Tool Selection

| Tool | When to Use | Overhead |
|---|---|---|
| `:timer.tc/1` | Quick one-off timing | Negligible |
| `:eprof` | Per-function CPU time breakdown | Low-medium |
| `:fprof` | Detailed call graph with timing | Medium-high |
| `:cprof` | Call counts only (no timing) | Very low |
| `:observer` | Visual process/memory inspection | Low |
| LiveDashboard | Production-safe web UI | Very low |
