---
name: implementing/otp-decisions
description: >
  OTP key decisions for Elixir implementers — process necessity, construct choice,
  GenServer templates, call vs cast, callback returns, supervisor strategies,
  DynamicSupervisor + Registry, Task patterns, ETS, process state, memoization.
  ALWAYS use when implementing GenServer, Task, Agent, or supervision code.
---

# OTP — Key Decisions for Implementers

> **Parent:** [SKILL.md](SKILL.md) — implementing routing core.
> **Depth:** For callback templates (GenServer `init/handle_call/cast/info/continue`, Task/Agent patterns, Registry via-tuples, ETS calls, `:gen_statem` skeleton, supervisor child-specs), load [otp-callbacks.md](otp-callbacks.md). For architectural OTP decisions (WHICH construct to choose, supervision-tree shape), load `../elixir-planning/otp-design.md` and `../elixir-planning/process-topology.md`.

When implementing code that involves processes, the first decision is always *do I need a process at all?* Most code doesn't. The rest of this section walks through the decisions that DO need a process.

---

### 9.1 Do you need a process at all?

| Situation | Process? |
|---|---|
| Pure data transformation | No — pure function |
| Stateless request/response | No — pure function |
| State that lives for one function call | No — pass as arg, return new state |
| State shared across calls within one process | No — struct module + threading through calls |
| State shared across MULTIPLE processes | Yes |
| State that must survive a crash | Yes (supervised) |
| Serializing access to a resource (writer) | Yes (GenServer) |
| Concurrent independent work | Maybe Task; Yes if long-running |
| Scheduled / periodic work | Yes (GenServer with `Process.send_after`, or Oban) |
| Cross-node messaging | Yes (GenServer or similar) |

**If you need a process, pick the narrowest construct.**

### 9.2 Which OTP construct? — decision table

| Need | Use | Why |
|---|---|---|
| One-off concurrent side-effect work | `Task.Supervisor.start_child/2` | Supervised, no state |
| Parallel map with bounded concurrency | `Task.async_stream/3,5` | Built-in concurrency control + backpressure |
| Long-running worker holding state | `GenServer` | Standard behaviour, well-tooled |
| Explicit state machine with transitions | `:gen_statem` | Cleaner than huge `case` in GenServer |
| Single-value concurrent update (counter, cache) | `Agent` | Lightweight; wraps GenServer |
| Read-heavy shared data (many readers, one writer) | ETS (`:public`, `read_concurrency: true`) | Avoids GenServer bottleneck |
| Atomic counters / gauges | `:counters` / `:atomics` | Lock-free, very fast |
| Rarely-changing global config | `:persistent_term` | O(1) reads; expensive writes |
| Backpressured data pipeline | GenStage / Broadway | Designed for flow control |
| Persistent job queue with retries | Oban | Durable, observable |
| Name-based dispatch across many processes | Registry (`:via` tuples) | Per-process naming without atoms |
| Many transient processes (one per user/session) | DynamicSupervisor + Registry | Start/stop dynamically, find by key |
| Pub/sub within a node | `Registry` with `:duplicate` keys, or `Phoenix.PubSub` | Native dispatch |

#### 9.2.1 `:gen_statem` callback mode — default to `[:state_functions, :state_enter]`

`:gen_statem` has three callback modes. The default choice for per-entity FSMs (device state, order workflow, connection lifecycle) is `[:state_functions, :state_enter]`:

| Callback mode | When to use | Shape |
|---|---|---|
| `[:state_functions, :state_enter]` | **Default for per-entity FSMs.** One function per state; `:enter` callbacks for transition-local effects (start timer, log transition, push telemetry). | `def idle(:enter, _old, data), do: ...` + `def idle({:call, from}, msg, data), do: ...` |
| `:state_functions` (without state_enter) | Simple FSMs where transitions have no setup/teardown. Rare. | Same as above, no `:enter` clause. |
| `:handle_event_function` | One big `handle_event/4` dispatching on state. Use when states are not well-separated (many shared events) or the state space is dynamic. | `def handle_event({:call, from}, msg, state, data), do: ...` |

```elixir
defmodule MyApp.Device do
  @behaviour :gen_statem
  def callback_mode, do: [:state_functions, :state_enter]

  def init(opts), do: {:ok, :offline, %{id: opts[:id], last_seen: nil}}

  # One function per state
  def offline(:enter, _old, _data), do: :keep_state_and_data
  def offline({:call, from}, :ping, data) do
    {:next_state, :online, %{data | last_seen: now()}, [{:reply, from, :ok}]}
  end

  def online(:enter, _old_state, data) do
    Logger.info("device online", id: data.id)
    {:keep_state_and_data, [{:state_timeout, 30_000, :expire}]}
  end
  def online(:state_timeout, :expire, data), do: {:next_state, :offline, data}
  def online({:call, from}, :ping, data), do: {:keep_state, %{data | last_seen: now()}, [{:reply, from, :ok}]}
end
```

The `:state_enter` half is what makes this mode idiomatic: transition-side-effects live in the `(:enter, _old_state, data)` clause of the destination state, not scattered across the transitioning events.

#### 9.2.2 `:persistent_term` hot-path config with test-override

Pattern: a value read on every call must be O(1), configured once at boot, and swappable in tests. The shape:

```elixir
defmodule MyApp.Signal do
  @moduledoc "Backend-swappable signal codec. Hot path reads go through backend/0."

  # Called once from Application.start/2 — AFTER the supervision tree is up.
  @spec install_backend() :: :ok
  def install_backend do
    backend = Application.fetch_env!(:my_app, __MODULE__)[:backend]
    :persistent_term.put({__MODULE__, :backend}, backend)
  end

  # Hot path — O(1), no GenServer, no Application dict lookup.
  @spec backend() :: module()
  def backend, do: :persistent_term.get({__MODULE__, :backend})

  # Test helper — writes to BOTH Application env and persistent_term so
  # tests can swap the backend. Use in setup blocks or per-test fixtures.
  @spec put_backend(module()) :: :ok
  def put_backend(mod) when is_atom(mod) do
    Application.put_env(:my_app, __MODULE__, backend: mod)
    :persistent_term.put({__MODULE__, :backend}, mod)
  end
end
```

Use this for: codec/backend choice, NIF-vs-pure fallback, feature-flag modules, hot-path formatters. NOT for: values that change per-call (use Application env or GenServer state); large values (persistent_term writes are expensive — O(n) copy across all processes).

### 9.3 GenServer — canonical template

```elixir
defmodule MyApp.Counter do
  use GenServer
  require Logger

  # --- Client API (public) ---
  @doc "Starts the counter under a supervisor."
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec increment(GenServer.server()) :: non_neg_integer()
  def increment(server \\ __MODULE__), do: GenServer.call(server, :increment)

  @spec get(GenServer.server()) :: non_neg_integer()
  def get(server \\ __MODULE__), do: GenServer.call(server, :get)

  # --- Server callbacks (private — delegate to pure logic) ---
  @impl true
  def init(opts) do
    initial = Keyword.get(opts, :initial, 0)
    {:ok, %{count: initial}}
  end

  @impl true
  def handle_call(:increment, _from, state) do
    new_state = %{state | count: state.count + 1}
    {:reply, new_state.count, new_state}
  end

  def handle_call(:get, _from, state), do: {:reply, state.count, state}

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
```

### 9.4 call vs cast — decision table

| Use call when... | Use cast when... |
|---|---|
| The caller needs a reply (value, confirmation) | Fire-and-forget (logging, metrics, notifications) |
| Consistency matters and caller should block until done | High throughput; losing a message is acceptable |
| You want natural backpressure (slow server = slow caller) | Independent side effect (PubSub broadcast) |
| Failure should propagate to the caller | The server can handle failure internally |

**Default to `call`.** `cast` silently drops messages when the mailbox overflows; `call` gives you a crash with a meaningful timeout.

### 9.5 GenServer callback returns — decision table

| Return | Meaning |
|---|---|
| `{:reply, reply, state}` | Normal reply, continue |
| `{:reply, reply, state, timeout}` | Reply, then `:timeout` message if no activity in `timeout` ms |
| `{:reply, reply, state, :hibernate}` | Reply, then compact memory (for rarely-used long-lived processes) |
| `{:reply, reply, state, {:continue, term}}` | Reply, then invoke `handle_continue/2` before next message |
| `{:noreply, state}` | No reply yet — will reply later via `GenServer.reply/2` |
| `{:stop, reason, reply, state}` | Reply, then terminate with `reason` |
| `{:stop, reason, state}` (no reply) | Terminate without reply |

**`handle_continue/2` — use it when `init/1` has expensive work:**

```elixir
@impl true
def init(opts) do
  {:ok, %{}, {:continue, :load_data}}   # Return fast, keep supervision snappy
end

@impl true
def handle_continue(:load_data, state) do
  data = MyApp.Data.load_all()          # Expensive, runs AFTER init returns
  {:noreply, %{state | data: data}}
end
```

### 9.6 GenServer rules (LLM)

1. **ALWAYS provide a client API** — callers use `MyServer.get/1`, not `GenServer.call(pid, :get)`
2. **NEVER block in a callback** — no HTTP, no DB queries, no `Process.sleep`. Offload via `Task` or `handle_continue`
3. **NEVER put business logic in callbacks** — delegate to pure functions
4. **ALWAYS set explicit timeouts on `GenServer.call`** — the default 5000ms is often wrong
5. **ALWAYS use the same via-tuple to call** a process that was registered with one
6. **ALWAYS implement `format_status/1`** on GenServers holding sensitive data (tokens, passwords)
7. **PREFER `handle_continue/2`** over crashing `init/1` for expensive initialization

### 9.7 Supervisor strategies — decision table

| Strategy | Restarts | Use when |
|---|---|---|
| `:one_for_one` | Only the crashed child | Children are independent (most common) |
| `:rest_for_one` | Crashed child + all started AFTER it | Later children depend on earlier ones |
| `:one_for_all` | All children | Children are tightly coupled (crash together) |

**Canonical layout:**

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyAppWeb.Telemetry,             # 1. Instrumentation first
      MyApp.Repo,                     # 2. DB
      {Phoenix.PubSub, name: MyApp.PubSub},    # 3. PubSub
      {Task.Supervisor, name: MyApp.TaskSupervisor},
      MyApp.WorkerRegistry,           # 5. Registry BEFORE DynamicSupervisor
      MyApp.WorkerSupervisor,         # 6. Dynamic workers
      MyAppWeb.Endpoint               # 7. HTTP endpoint LAST
    ]
    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

**Ordering rule:** Infrastructure (Telemetry, Repo, PubSub) first → domain workers → HTTP endpoints last. HTTP endpoint depending on everything below it.

### 9.8 DynamicSupervisor + Registry — canonical template

```elixir
# Registry — must start BEFORE DynamicSupervisor
defmodule MyApp.WorkerRegistry do
  def child_spec(_), do: Registry.child_spec(keys: :unique, name: __MODULE__)
  def via(id), do: {:via, Registry, {__MODULE__, id}}
end

# DynamicSupervisor — starts worker children on demand
defmodule MyApp.WorkerSupervisor do
  use DynamicSupervisor
  def start_link(_), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_worker(id, opts \\ []) do
    DynamicSupervisor.start_child(__MODULE__, {MyApp.Worker, [id: id] ++ opts})
  end
end

# Worker registers via the Registry helper
defmodule MyApp.Worker do
  use GenServer
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: MyApp.WorkerRegistry.via(id))
  end

  # Client always calls via() — never the raw id atom
  def call(id, msg), do: GenServer.call(MyApp.WorkerRegistry.via(id), msg)
  # ...
end

# In application.ex (Registry MUST be before DynamicSupervisor):
children = [MyApp.WorkerRegistry, MyApp.WorkerSupervisor]
```

### 9.9 Task — when and how

| Need | Use |
|---|---|
| Fire-and-forget side effect, supervised | `Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> ... end)` |
| Await a single result, linked | `Task.async/1` + `Task.await/2` |
| Await a result WITHOUT link (handle :DOWN yourself) | `Task.Supervisor.async_nolink/3` |
| Parallel map with concurrency control | `Task.async_stream/3,5` |
| Many small CPU-bound transforms | `Task.async_stream(ordered: false, max_concurrency: schedulers)` |

```elixir
# Parallel map, default ordered, auto concurrency
urls
|> Task.async_stream(&fetch/1, timeout: 10_000)
|> Enum.map(fn
  {:ok, result} -> result
  {:exit, reason} -> {:error, reason}
end)

# Ordered: false when order doesn't matter — slightly faster
files
|> Task.async_stream(&process/1, ordered: false, max_concurrency: 8)
|> Stream.run()
```

**`async` vs `async_nolink` inside a GenServer:**

```elixir
# PREFER async_nolink so task crash doesn't kill the GenServer
def handle_call(:start_fetch, _from, state) do
  task = Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn -> fetch() end)
  {:reply, :ok, %{state | task_ref: task.ref}}
end

def handle_info({ref, result}, %{task_ref: ref} = state) do
  Process.demonitor(ref, [:flush])
  {:noreply, %{state | task_ref: nil, last_result: result}}
end

def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task_ref: ref} = state) do
  {:noreply, %{state | task_ref: nil}}
end
```

### 9.10 ETS — when to choose it over GenServer

| Situation | Table options |
|---|---|
| High-read, low-write cache, multiple readers | `[:named_table, :public, read_concurrency: true]` |
| Many writers to different keys | Add `write_concurrency: true` |
| Only the owner writes, many readers | `[:named_table, :protected, read_concurrency: true]` |
| Only the owner reads and writes | `[:named_table, :private]` |
| Sorted access by key | `:ordered_set` instead of `:set` (default) |

```elixir
# Owner creates the table in init/1
def init(_) do
  :ets.new(:my_cache, [:named_table, :public, read_concurrency: true])
  {:ok, %{}}
end

# Readers from ANY process use the table directly — no GenServer bottleneck
def get(key) do
  case :ets.lookup(:my_cache, key) do
    [{^key, value}] -> {:ok, value}
    [] -> :error
  end
end

# Atomic increment without a GenServer
:ets.update_counter(:stats, :requests, {2, 1}, {:requests, 0})
```

**Rule:** if your GenServer is *just* wrapping a map with `get`/`put`, replace it with ETS.

### 9.11 Process state — what to store

| Store in state | Store elsewhere |
|---|---|
| Small (<10KB) working state | Large blobs → ETS |
| Configuration refs (pids, atoms, module names) | Caches → ETS / :persistent_term |
| Task references awaiting results | Counters → :counters / :atomics |
| Per-instance identity (user_id, session_id) | Shared app config → Application env |
| State that must survive only while process is alive | State that must survive crash → DB / persistent term |

### 9.12 Common OTP anti-patterns

```elixir
# BAD — GenServer.call for reads on a hot path (bottleneck)
def get(key), do: GenServer.call(__MODULE__, {:get, key})
# Every reader serializes through the GenServer.

# GOOD — direct ETS read
def get(key) do
  case :ets.lookup(:my_table, key) do
    [{^key, v}] -> {:ok, v}
    [] -> :error
  end
end
```

```elixir
# BAD — partial state update (crash between steps = corrupt state)
def handle_call(:transfer, _from, state) do
  state = update_in(state.a, & &1 - 100)
  external_api_call()                      # May crash here
  state = update_in(state.b, & &1 + 100)
  {:reply, :ok, state}
end

# GOOD — compute new state fully, then return atomically
def handle_call(:transfer, _from, state) do
  :ok = external_api_call()                # If this crashes, state is unchanged
  new_state =
    state
    |> update_in([:a], & &1 - 100)
    |> update_in([:b], & &1 + 100)
  {:reply, :ok, new_state}
end
```

```elixir
# BAD — starting a Registry and DynamicSupervisor under :one_for_one
# If Registry crashes, the DynamicSupervisor's children can't re-register
children = [
  {Registry, keys: :unique, name: MyApp.Registry},
  {DynamicSupervisor, name: MyApp.DynSup}
]
Supervisor.init(children, strategy: :one_for_one)  # WRONG

# GOOD — :rest_for_one so Registry restart cascades to DynSup
Supervisor.init(children, strategy: :rest_for_one)
```

### 9.13 Memoization templates — caching pure-fn results

A pure deterministic building-block function (axes 1 + 2 of `elixir-planning/building-blocks.md` §3.1) can be memoized safely — same input always produces same output, so the cache is correct. **An impure or non-deterministic function CANNOT be memoized without lying.** Memoization is therefore a payoff that *only* building-blocks unlock.

The cache lives in the orchestrator layer, NOT in the building-block. The building-block stays pure and property-testable; the orchestrator wraps it with a cache lookup.

**ETS-backed memoize — the default shape:**

```elixir
# 1. Owner module creates the table at app start (in the supervision tree)
defmodule MyApp.TokenCache do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    :ets.new(:token_cache, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end
end

# 2. Public API — orchestrator wraps the building-block with cache lookup
defmodule MyApp.Tokens.Cached do
  alias MyApp.Tokens

  @spec sign(map(), String.t()) :: String.t()
  def sign(payload, secret) do
    key = {payload, secret}

    case :ets.lookup(:token_cache, key) do
      [{^key, signed}] ->
        signed

      [] ->
        signed = Tokens.sign(payload, secret)   # building-block, pure
        :ets.insert(:token_cache, {key, signed})
        signed
    end
  end
end
```

**`:persistent_term` for read-mostly lookup tables:**

```elixir
# Boot-time write — typically in Application.start/2 or a one-shot GenServer
defmodule MyApp.RegexCache do
  @patterns [
    email: ~r/^[\w.+-]+@[a-z0-9-]+\.[a-z0-9.-]+$/i,
    slug: ~r/^[a-z0-9-]+$/,
    iso8601: ~r/^\d{4}-\d{2}-\d{2}/
  ]

  def install do
    :persistent_term.put({__MODULE__, :patterns}, Map.new(@patterns))
  end

  def get(name) do
    :persistent_term.get({__MODULE__, :patterns})
    |> Map.fetch!(name)
  end
end
```

**Critical warning: `:persistent_term` writes are O(N) where N = process count.** Every `:persistent_term.put/2` triggers a global GC scan across all processes; on a node with 100K processes this stalls the entire VM for measurable time. Use `:persistent_term` ONLY for boot-time writes (config, compiled regex, lookup tables). For runtime-changing values, use ETS.

**When to memoize:**
- Function is on a hot path (called every request, every event, every iteration).
- Function is deterministic AND pure (axes 1 + 2 hold strict).
- Inputs have low cardinality OR high reuse — same arguments repeat enough that the cache pays off.
- Computation is expensive: regex compile, hash, parse, large-data serialization.

**When NOT to memoize:**
- Function is impure (reads from DB, network, clock, random) — caching returns stale values.
- Function is cheap enough that lookup overhead beats recompute.
- Memory budget is tight — cached entries don't expire automatically; bound the cache size or use Cachex / Nebulex with TTL.

**Cache invalidation strategy** belongs in the orchestrator. ETS-backed memoize for a pure fn doesn't need invalidation if inputs are content-addressed (the key IS the input — different inputs naturally land on different cache lines). For caches keyed by external identifiers (user_id), invalidate on the write path: `Repo.update(user); :ets.delete(:cache, user_id)`.

Cross-reference: `elixir-planning/SKILL.md` §4.7.8 (memoization is a building-block payoff, design-stage decision); §9.2 above for ETS table options. The Archdo rule `5.75 MemoizeOpportunity` (planned) flags building-block functions with expensive calls but no cache.
