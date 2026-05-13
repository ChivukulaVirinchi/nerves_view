---
name: elixir-otp
description: >
  OTP process patterns covering GenServer, Task, Agent, ETS, DynamicSupervisor,
  Registry, PubSub, and supervision trees. ALWAYS use when designing processes,
  choosing between GenServer/Task/Agent/ETS, writing supervision trees, or
  handling async work. For background jobs -> load oban. For LiveView async
  state -> load liveview-async-state.
---

# OTP: Processes, Supervision & Concurrency

OTP process design is where LLMs most commonly over-engineer. The default should
be plain functions -- only introduce a process when there is a concrete runtime
reason (long-lived state, concurrency coordination, isolation). This skill covers
process selection, supervision patterns, message design, and the most common
anti-patterns.

## 1. Rules

1. **No process without a runtime reason.** If a module only groups functions and holds no runtime state, it should not be a GenServer.
2. **Supervise every long-lived process.** Never use bare `GenServer.start_link/3` in application code. Always go through a supervisor.
3. **Name shared processes explicitly.** Unnamed processes are invisible to the rest of the system and cannot be discovered.
4. **Keep GenServer state small and serializable.** Large state causes slow `:sys.get_state` introspection and OOM risk on state transfer.
5. **Keep messages small.** Pass IDs or compact payloads, not entire structs or data graphs. The receiver can look up what it needs.
6. **Use `Task.Supervisor.async_nolink/3` for async work you need to monitor.** Plain `Task.async` links to the caller -- if the task crashes, the caller crashes too.
7. **Use `Task.async_stream/3` for bounded parallel enumeration.** It applies backpressure automatically, unlike spawning tasks in a loop.
8. **Use PubSub for fan-out notifications.** Never discover and message processes manually when broadcasting is the intent.
9. **Use `send_after` + `handle_info` for periodic work in GenServers.** Never use `:timer.send_interval` (it does not respect backpressure).
10. **Document why every process and lock exists.** A comment explaining the concurrency invariant saves hours of future debugging.

## 2. Decision Tables

### 2.1 Process Type Selection

| Need | Use | Avoid | Why |
|------|-----|-------|-----|
| Group related functions, no runtime state | Plain module with functions | GenServer | No process needed; a module is just a namespace |
| Read-heavy shared state (config, lookup tables) | ETS table | GenServer with `handle_call` reads | ETS allows concurrent reads without serializing through a process |
| Simple get/set state wrapper | Agent | GenServer | Agent is a simplified GenServer for trivial state; less boilerplate |
| Coordinated state with timeouts, messages, lifecycle | GenServer | Agent, ETS | GenServer handles the full message/state/timeout surface |
| One-off async work (fire-and-forget) | `Task.Supervisor.start_child/2` | `Task.start/1` | Supervised task gets monitored and logged on failure |
| Async work with result needed | `Task.Supervisor.async_nolink/3` + `yield`/`shutdown` | `Task.async/1` (links) | `async_nolink` isolates caller from task crash |
| Parallel map over a collection | `Task.async_stream/3` | `Enum.map` + `Task.async` in a loop | `async_stream` applies backpressure via `max_concurrency` |
| Many keyed processes (per-user, per-room) | DynamicSupervisor + Registry | Hardcoded child specs | Dynamic processes come and go; static supervision doesn't fit |
| Broadcast to multiple subscribers | Phoenix.PubSub | Manual process discovery + send | PubSub decouples publishers from subscribers |
| Periodic background work (every N seconds) | GenServer with `Process.send_after` | `:timer.send_interval` | `send_after` re-schedules after processing; interval can pile up messages |
| Scheduled/retryable background jobs | Oban | GenServer + `Process.send_after` | Oban persists jobs, handles retries, and survives deploys |

### 2.2 Supervision Strategy Selection

| Children Relationship | Strategy | Why |
|----------------------|----------|-----|
| Independent children | `:one_for_one` | One child crash should not affect siblings |
| Children depend on each other | `:one_for_all` | If one crashes, all must restart to stay consistent |
| Ordered dependencies (A starts before B) | `:rest_for_one` | Restart B and everything after it when A crashes |
| Dynamic children (created at runtime) | `DynamicSupervisor` | Child count is unknown at compile time |

### 2.3 Registry vs Named Process vs ETS

| Need | Use | Why |
|------|-----|-----|
| Single well-known process | `name: MyApp.Worker` | Simple, discoverable, one instance |
| Many processes keyed by ID | `Registry` with `{:via, Registry, {Reg, key}}` | O(1) lookup, built-in monitoring |
| Process-independent shared state | ETS table | Survives process crashes, concurrent reads |
| Cross-node process discovery | `:global` or distributed Registry | Standard `Registry` is node-local |

### 2.4 Task Yield Timeout Handling

| Scenario | Pattern | Why |
|----------|---------|-----|
| Result needed, willing to wait | `Task.yield(task, timeout)` | Returns `{:ok, result}` or `nil` on timeout |
| Result needed, hard deadline | `Task.yield(task, timeout) \|\| Task.shutdown(task)` | Kills task if it exceeds deadline |
| Result needed, graceful then hard | `Task.yield(task, soft) \|\| Task.shutdown(task, :brutal_kill)` | Tries graceful exit first, then forces |
| Fire and forget | `Task.Supervisor.start_child/2` | No yield needed, supervisor handles lifecycle |

## 3. Patterns (BAD -> GOOD)

### 3.1 GenServer for Function Grouping

**Severity:** BLOCK

```elixir
# BAD -- GenServer that holds no state, just groups functions
defmodule MyApp.Calculator do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def init(state), do: {:ok, state}

  def handle_call({:add, a, b}, _from, state) do
    {:reply, a + b, state}
  end
end

# Usage: GenServer.call(Calculator, {:add, 1, 2})

# GOOD -- plain module, no process needed
defmodule MyApp.Calculator do
  def add(a, b), do: a + b
end
```

**Why:** A GenServer serializes all calls through a single process mailbox. Using one for pure functions creates a bottleneck where none is needed. The overhead of process messaging, scheduling, and supervision is pure waste.

### 3.2 Task.start for Important Work

**Severity:** BLOCK

```elixir
# BAD -- fire and forget with no monitoring
Task.start(fn -> send_welcome_email(user) end)
# If this crashes, nobody knows

# GOOD -- supervised task
Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
  send_welcome_email(user)
end)
# Crash is logged, supervisor tracks it

# BETTER for critical work -- use Oban
%{user_id: user.id}
|> MyApp.Workers.WelcomeEmail.new()
|> Oban.insert()
# Persisted, retried on failure, survives deploys
```

**Why:** `Task.start/1` spawns a process with no supervision. If it crashes, the error is silently swallowed. `Task.Supervisor` ensures logging and optional restart. For work that must not be lost, use Oban.

### 3.3 Large State in GenServer

**Severity:** WARN

```elixir
# BAD -- storing entire dataset in GenServer state
defmodule MyApp.Cache do
  use GenServer

  def init(_) do
    data = Repo.all(from i in Item, preload: [:comments, :tags, :author])
    {:ok, %{items: data}}  # could be megabytes
  end
end

# GOOD -- use ETS for read-heavy shared data
defmodule MyApp.Cache do
  use GenServer

  def init(_) do
    table = :ets.new(__MODULE__, [:set, :named_table, read_concurrency: true])
    load_data(table)
    {:ok, %{table: table}}
  end

  def get(key) do
    case :ets.lookup(__MODULE__, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  defp load_data(table) do
    Repo.all(Item)
    |> Enum.each(fn item -> :ets.insert(table, {item.id, item}) end)
  end
end
```

**Why:** GenServer state is copied on every `handle_call` reply (the state and reply share the process heap, but introspection via `:sys.get_state` copies it). ETS stores data outside process heaps, allows concurrent reads with `read_concurrency: true`, and survives process crashes if owned by a supervisor.

### 3.4 Timer.send_interval for Periodic Work

**Severity:** WARN

```elixir
# BAD -- interval fires regardless of processing time
defmodule MyApp.Poller do
  use GenServer

  def init(state) do
    :timer.send_interval(5_000, :poll)  # messages pile up if poll takes > 5s
    {:ok, state}
  end
end

# GOOD -- re-schedule after processing completes
defmodule MyApp.Poller do
  use GenServer

  def init(state) do
    schedule_poll()
    {:ok, state}
  end

  def handle_info(:poll, state) do
    new_state = do_polling(state)
    schedule_poll()
    {:ok, new_state}
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, 5_000)
end
```

**Why:** `:timer.send_interval/2` sends messages at fixed intervals regardless of whether the previous message was processed. If processing takes longer than the interval, messages accumulate in the mailbox, consuming memory and creating cascading delays. `Process.send_after` re-schedules only after the current tick completes.

### 3.5 Linked Task for Isolated Work

**Severity:** WARN

```elixir
# BAD -- task crash kills the caller
task = Task.async(fn ->
  external_api_call()  # if this raises, caller crashes too
end)
result = Task.await(task)

# GOOD -- nolink isolates caller from task failure
task = Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn ->
  external_api_call()
end)

case Task.yield(task, 10_000) || Task.shutdown(task, :brutal_kill) do
  {:ok, result} -> {:ok, result}
  {:exit, reason} -> {:error, reason}
  nil -> {:error, :timeout}
end
```

**Why:** `Task.async/1` links the task to the calling process. If the task crashes (e.g., external API timeout), the caller crashes too. `async_nolink` keeps them isolated -- the caller can handle the failure gracefully.

### 3.6 Manual Process Discovery for Broadcasting

**Severity:** WARN

```elixir
# BAD -- manually tracking and messaging subscribers
defmodule MyApp.Notifier do
  use GenServer

  def init(_), do: {:ok, %{subscribers: []}}

  def handle_cast({:subscribe, pid}, state) do
    {:noreply, %{state | subscribers: [pid | state.subscribers]}}
  end

  def handle_cast({:notify, msg}, state) do
    Enum.each(state.subscribers, &send(&1, msg))
    {:noreply, state}
  end
end

# GOOD -- use PubSub
# In subscriber (e.g., LiveView mount):
Phoenix.PubSub.subscribe(MyApp.PubSub, "quiz:#{quiz_id}")

# In publisher (e.g., context function):
Phoenix.PubSub.broadcast(MyApp.PubSub, "quiz:#{quiz_id}", {:quiz_updated, quiz})
```

**Why:** Manual subscriber tracking requires handling process death (removing dead PIDs), is single-node only, and reinvents what PubSub already provides. PubSub handles subscription cleanup, works across nodes, and is battle-tested.

### 3.7 Spawning Tasks in a Loop Without Backpressure

**Severity:** WARN

```elixir
# BAD -- spawns unbounded concurrent tasks
results =
  large_list
  |> Enum.map(fn item -> Task.async(fn -> process(item) end) end)
  |> Enum.map(&Task.await/1)

# GOOD -- bounded concurrency with async_stream
results =
  large_list
  |> Task.async_stream(&process/1, max_concurrency: 10, timeout: 30_000)
  |> Enum.map(fn {:ok, result} -> result end)
```

**Why:** Spawning a task per item in a large list can create thousands of concurrent processes, exhausting system resources (memory, file descriptors, database connections). `Task.async_stream` limits concurrency to a configurable maximum.

### 3.8 Hidden Unnamed Processes

**Severity:** SUGGEST

```elixir
# BAD -- unnamed process, invisible to tooling
GenServer.start_link(MyWorker, arg)
# Who can find this process? Only the caller who has the PID.

# GOOD -- named process, discoverable
GenServer.start_link(MyWorker, arg, name: MyApp.MyWorker)
# Or for dynamic processes:
GenServer.start_link(MyWorker, arg,
  name: {:via, Registry, {MyApp.Registry, {:worker, id}}})
```

**Why:** Unnamed processes can't be found through `:observer`, `Process.whereis`, or Registry lookups. When debugging production issues, unnamed processes are invisible.

## 4. Checklist

### Process Design
- [ ] Every process has a documented runtime reason (state, concurrency, isolation)
- [ ] No GenServer is used purely for function grouping
- [ ] State is small and serializable (IDs, not full data graphs)
- [ ] Messages carry IDs or compact payloads, not full structs

### Supervision
- [ ] Every long-lived process is supervised (no bare `start_link`)
- [ ] Supervision strategy matches child dependency relationship
- [ ] DynamicSupervisor used for runtime-created processes
- [ ] Shared processes are named (module name or via Registry)

### Async Work
- [ ] `Task.Supervisor.async_nolink` for work that might fail
- [ ] `Task.async_stream` for bounded parallel enumeration
- [ ] Yield + shutdown pattern for timeout handling
- [ ] Critical work uses Oban, not fire-and-forget tasks

### Periodic Work
- [ ] Uses `Process.send_after` (not `:timer.send_interval`)
- [ ] Re-schedules after processing, not before
- [ ] Interval is appropriate for the work duration

### Testing
- [ ] Test processes use `start_supervised!/1`
- [ ] No `Process.sleep` -- uses monitors, `assert_receive`, or `:sys.get_state`
- [ ] Process state is verified via public API, not internal inspection

## 5. Routing

- **Background jobs with persistence and retries** -> load `oban`
- **LiveView async data loading** -> load `liveview-async-state`
- **ETS for caching query results** -> load `ecto` (preload strategies)
- **PubSub for LiveView real-time updates** -> load `liveview-streams`
- **Testing process behavior** -> load `testing`
- **Process performance and observability** -> load `observability`
