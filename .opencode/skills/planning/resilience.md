# Resilience Planning — depth reference

> **Routing:** [SKILL.md](SKILL.md) §2 — Master Decision Table, row 3.8 (Resilience).
> **Related depth:** [integration-patterns.md](integration-patterns.md) §10 — resilience at integration boundaries (circuit breakers around adapters, retries by layer, graceful degradation, timeout cascades).

OTP provides resilience primitives that other ecosystems need external libraries for. These patterns are **architectural** — they determine where failure handling lives and how subsystems degrade.

---

## 1. BEAM processes as bulkheads

Every BEAM process is an isolated failure domain — its own heap, its own GC, its own crash boundary. **This IS the bulkhead pattern.** When one process crashes, others are unaffected.

```elixir
children = [
  # If email sending fails, order processing continues
  {MyApp.Mailer.Pool, pool_size: 5},
  # If payment gateway is slow, catalog browsing is unaffected
  {MyApp.PaymentWorker, []},
  # If search indexing crashes, CRUD operations work fine
  {MyApp.SearchIndexer, []}
]
```

**Architectural rule:** Different concerns run in different processes. This gives you bulkhead isolation for free. **Never run unrelated work in the same GenServer** — split it.

## 2. Circuit breaker — where it belongs

Prevent cascading failures by stopping calls to a failing subsystem. In Elixir, implement with a GenServer or use the `:fuse` library.

**Architectural placement: around infrastructure adapters** (HTTP clients, external APIs, database calls to remote services). **NEVER in domain logic.**

```elixir
defmodule MyApp.PaymentGateway.Protected do
  @behaviour MyApp.PaymentGateway

  @impl true
  def charge(amount, token) do
    case :fuse.ask(:payment_fuse, :sync) do
      :ok ->
        case MyApp.PaymentGateway.Stripe.charge(amount, token) do
          {:ok, _} = success -> success
          {:error, :timeout} -> :fuse.melt(:payment_fuse); {:error, :service_unavailable}
          {:error, _} = error -> error
        end
      :blown -> {:error, :service_unavailable}
    end
  end
end

# Supervision — fuse must start before the service that uses it
children = [
  {Fuse, name: :payment_fuse, strategy: {:standard, 5, 60_000}},   # 5 failures in 60s
  MyApp.PaymentWorker
]
```

**Rule:** The domain receives `{:error, :service_unavailable}` and decides what to do (queue for retry, show cached data, return partial result). Domain never knows a circuit breaker exists.

## 3. Retry and backoff — where each lives

Retries belong in infrastructure, **never** in domain logic. Different layers handle retries at different scales.

| Layer | Retry mechanism | Example |
|---|---|---|
| HTTP client | Built-in retry | `Req.new(retry: :transient, max_retries: 3)` |
| Background jobs | Job-level retry | `use Oban.Worker, max_attempts: 5` |
| Event handlers | Handler-level retry | Commanded error callback with backoff |
| GenServer | Process restart (supervisor) | `max_restarts` / `max_seconds` on supervisor |
| Infrastructure adapter | Wrapper with custom backoff | Custom retry around external call |

**Idempotency is a prerequisite for safe retries.** If an operation isn't idempotent, retrying it may cause duplicate effects. See [data-ownership.md](data-ownership.md) §5.

## 4. Graceful degradation

When a subsystem is down, serve degraded functionality instead of failing entirely.

```elixir
defmodule MyApp.Catalog do
  def get_product_with_recommendations(product_id) do
    product = get_product!(product_id)

    # Recommendations are nice-to-have — degrade if service is down
    recommendations =
      case MyApp.Recommendations.for_product(product_id) do
        {:ok, recs} -> recs
        {:error, _} -> []   # Show product without recommendations
      end

    {product, recommendations}
  end
end
```

**Architectural rule:** For each feature, identify whether it's **critical** (must work) or **nice-to-have** (can degrade). Critical paths use synchronous calls with clear error handling. Nice-to-have features use `try`-style fallbacks or cached data.

## 5. Timeout architecture

Timeouts must be set at **every boundary**, and **outer > middle > inner**. Otherwise outer timeouts fire before inner ones with meaningless errors.

```
Phoenix endpoint   : timeout 15_000ms     (outermost)
  GenServer.call   : timeout 10_000ms     (middle)
    HTTP client    : timeout 5_000ms      (innermost)

15_000 > 10_000 > 5_000  correct
```

**Where to set timeouts:**

- HTTP clients: `receive_timeout` in Req/Finch
- GenServer calls: second argument to `GenServer.call/3` (default 5000ms — usually too short)
- `Task.await`: second argument (default 5000ms)
- DB queries: `:timeout` option in Repo operations
- Phoenix endpoint: `:timeout` in endpoint config

## 6. Resilience decision guide

| Concern | Solution | Where it lives |
|---|---|---|
| External service may be slow / flaky | Circuit breaker (:fuse) | Infrastructure adapter |
| Operation may fail transiently | Retry with backoff | Client library, Oban, supervisor |
| External service is down | Graceful degradation (partial / cached / default) | Context function (orchestration) |
| Timeouts across layers | Outer > middle > inner cascade | Every layer |
| Prevent one subsystem failing another | Separate processes / supervisors | Supervision tree |
| Prevent retries from duplicating | Idempotency | Operation design |

## 7. Observability & trace context

`Logger.metadata` is **per-process** — documented behaviour of the `Logger` module. Any async boundary that doesn't propagate it is a runtime observability defect: log lines and telemetry events from spawned work appear without the originating request's `trace_id` / `request_id` / `tenant_id`. They become orphan when an operator searches by correlation ID.

**Plan every async boundary's metadata strategy at design time:**

| Request shape | Metadata setter |
|---|---|
| Phoenix HTTP request | `Plug.RequestId` configured early in the endpoint pipeline (sets `:request_id` in `Logger.metadata`). |
| Phoenix Channel | A `set_metadata` plug or explicit `Logger.metadata/1` call in `join/3`. |
| Oban job | Producer writes `trace_id` etc. into `Oban.Job.args`; the worker's `perform/1` calls `Logger.metadata/1` from those args (Oban's own job metadata — `:job_id`, `:worker`, `:queue`, `:attempt` — is set by the executor before `perform/1`). |
| Bare `Task.async` / `Task.Supervisor.start_child` | Capture `Logger.metadata()` outside the closure, restore inside. |
| Cross-node `:erpc` / GenServer `call` across nodes | Pass an explicit `TraceContext` struct as part of the message payload — `Logger.metadata` is local to the calling process; the remote process needs the value to set its own metadata. |

**TraceContext template — explicit type for cross-node / cross-Oban / multi-hop scope:**

```elixir
defmodule MyApp.TraceContext do
  @enforce_keys [:trace_id]
  defstruct [:trace_id, :tenant_ref, :target_ref, :operation]

  @type t :: %__MODULE__{
    trace_id: String.t(),
    tenant_ref: String.t() | nil,
    target_ref: String.t() | nil,
    operation: atom() | nil
  }

  @spec from_logger() :: t()
  def from_logger do
    md = Logger.metadata()
    %__MODULE__{
      trace_id: Keyword.get(md, :trace_id) || generate_trace_id(),
      tenant_ref: Keyword.get(md, :tenant_ref),
      target_ref: Keyword.get(md, :target_ref),
      operation: Keyword.get(md, :operation)
    }
  end

  @spec apply_to_logger(t()) :: :ok
  def apply_to_logger(%__MODULE__{} = ctx) do
    Logger.metadata(
      trace_id: ctx.trace_id,
      tenant_ref: ctx.tenant_ref,
      target_ref: ctx.target_ref,
      operation: ctx.operation
    )
  end

  defp generate_trace_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
```

**Decision: `Logger.metadata` propagation vs explicit `TraceContext`:**

| Choice | Use when |
|---|---|
| `Logger.metadata` capture+restore | Single async hop within one node; the metadata fits naturally in keyword form; you want backends/handlers to consume it without code changes. |
| `TraceContext` struct | Cross-node / cross-Oban / multiple async hops; the trace fields outlive the log scope; you want a typed contract enforced by `@spec`. |

**Telemetry rule:** every `:telemetry.execute/3` event that fires from an async closure must include `trace_id` (and any other relevant correlation IDs) in its **metadata** map — not rely on the receiving handler reading `Logger.metadata()`, because the handler runs in the *emitting* process, but a handler that re-publishes (e.g. to a remote sink) may not preserve metadata across that hop.

**Reference**: `Plug.RequestId` (`Logger.metadata([{logger_metadata_key, request_id}])`) is the canonical metadata-setter side; the propagation pattern relies on Logger's documented per-process scope. See `elixir-implementing` §5.12 for the keyboard-time templates.

---

## 8. Cross-references

- [SKILL.md](SKILL.md) §2 row 3.8 — resilience decision table
- [integration-patterns.md](integration-patterns.md) §10 — resilience at integration boundaries
- [process-topology.md](process-topology.md) — supervision as bulkheads
- [data-ownership.md](data-ownership.md) §5 — idempotency design for retries
- `elixir-implementing` §5.12 — trace context templates

---

**End of resilience.md.** For integration-boundary resilience (circuit breakers around adapters), see [integration-patterns.md](integration-patterns.md). For idempotency design, see [data-ownership.md](data-ownership.md).
