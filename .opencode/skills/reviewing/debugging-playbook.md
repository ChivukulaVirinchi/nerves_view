# Debugging Playbook

> **Depth file for [SKILL.md](SKILL.md).** Load when investigating a specific bug. Quick Reference (inline summary) first, then full depth below.

---

## Quick Reference — by symptom

Each subsection: **symptom → likely causes → investigation steps → fix pattern**.

### 8.1 Crash / unexpected exit

```
Symptom: process is crashing, supervisor is restarting it, stack trace in logs
```

| Likely cause | Investigation | Fix |
|---|---|---|
| Exception in `init/1` | Read the stack trace; check `init/1` for unwrapped fallible ops | Use `{:ok, state, {:continue, :setup}}` to defer expensive init |
| Unhandled `handle_info` message | Grep for `handle_info`, add catch-all clause | `def handle_info(msg, state) do Logger.warning("unexpected: #{inspect(msg)}"); {:noreply, state} end` |
| Linked task crash propagating | Task uses `async` (linked) instead of `async_nolink` | Switch to `Task.Supervisor.async_nolink/3` + handle `:DOWN` |
| `MatchError` in `handle_call` | A pattern in the function head or body didn't match | Add missing clause; return `{:error, reason}` instead of pattern-matching happy path |
| `FunctionClauseError` on a public fn | Input shape didn't match any clause | Add validating clause at the top or a fallback clause |
| `:timeout` exit from GenServer.call | Callee slow or busy | Profile callee; extract work to Task; increase timeout only after understanding why |
| Infinite supervisor restart loop | Child crashes immediately on startup; `max_restarts` exceeded | Look at `init/1`; check for missing config; guard against startup with no DB |

**Tools to reach for:**

```elixir
# 1. Read the full stack trace — Elixir shows it in Logger output
# 2. Check the process's last known state
:sys.get_state(pid)
# 3. Trace the process to see messages arriving
:sys.trace(pid, true)
# ... reproduce ...
:sys.trace(pid, false)
# 4. See what's in the mailbox right now
Process.info(pid, :message_queue_len)
Process.info(pid, :messages)        # actual messages (copy — heavy!)
```

### 8.2 Memory growth / leaks

```
Symptom: memory usage growing over time, OOM eventually
```

| Likely cause | Investigation | Fix |
|---|---|---|
| Large binaries retained via references | `:recon.bin_leak(10)` — forces GC, shows processes holding binary refs | Copy binary to detach: `:binary.copy(bin)` |
| Process mailbox growing unbounded | `:recon.proc_count(:message_queue_len, 10)` | Add backpressure (GenStage), or selective receive, or shed load |
| ETS table growing unbounded | `:ets.info(table, :size)` / `:ets.info(table, :memory)` | Add TTL, explicit eviction, or bounded cache |
| Process state accumulating (`[x \| state]` forever) | `:erlang.process_info(pid, :total_heap_size)` | Bound the state; drop old entries |
| `Process.put` leaking per-request data | Check process dictionary usage | Use per-request context maps instead |
| Large number of short-lived processes | `:erlang.system_info(:process_count)` over time | Pool the work (Task.async_stream with max_concurrency) |

**Top-N processes by memory:**

```elixir
:recon.proc_count(:memory, 20)        # Top 20 by memory
:recon.proc_count(:message_queue_len, 20)  # Top 20 by mailbox length
:recon.proc_count(:reductions, 20)    # Top 20 by CPU work
```

**Global memory breakdown:**

```elixir
:erlang.memory()
# [total, processes, processes_used, system, atom, atom_used, binary, code, ets]
```

### 8.3 Mailbox buildup

```
Symptom: a GenServer is falling behind; its mailbox is growing
```

| Cause | Symptom | Fix |
|---|---|---|
| Work per message is too slow | `message_queue_len` growing steadily | Offload heavy work to Task; use `handle_continue` for post-reply work |
| GenServer is the bottleneck for reads | High call rate, reads serialized | Move reads to ETS |
| Sync call blocking the callee | Callee itself blocked on another slow call | Make outer call async via `:noreply` + `GenServer.reply/2` |
| Producer sending faster than consumer processes | Classic PubSub / event-stream overload | Migrate to GenStage / Broadway for backpressure |
| `Process.send_after` flood | Scheduled messages piling up during lag | Coalesce timers; cancel before re-scheduling |

**Investigation:**

```elixir
# Is the mailbox growing over time?
for _ <- 1..5 do
  IO.inspect(Process.info(pid, :message_queue_len))
  Process.sleep(1000)
end

# What kind of messages are piling up?
Process.info(pid, :messages) |> elem(1) |> Enum.take(20)
```

### 8.4 Slow response / timeout

```
Symptom: requests or GenServer.call timing out, or response times high
```

| Likely cause | Investigation | Fix |
|---|---|---|
| N+1 queries | Enable `Ecto.DevLogger`; count queries per request | Batch with `Repo.preload` or explicit query |
| External HTTP call without timeout | Check adapters (`Req`, `Finch`, `HTTPoison`) for `receive_timeout` | Set timeout explicitly |
| GenServer serialization bottleneck | `message_queue_len` growing | ETS for reads; PartitionSupervisor for shards |
| Missing DB index | `EXPLAIN ANALYZE` the slow query | Add index in migration |
| Connection pool exhaustion | `:telemetry` for `[:ecto, :repo, :query]` with `:queue_time` | Increase `pool_size`; reduce per-request queries |
| Slow serialization (JSON, term_to_binary) | Profile at the serialization call site | Stream-encode; use `:erlang.term_to_iovec/1,2` |
| Inner timeout exceeding outer | Check timeout cascade — outer must be > middle > inner | Fix timeouts: endpoint > GenServer.call > HTTP client |

**Measure where the time goes:**

```elixir
# Quick timing of a single call
{microseconds, result} = :timer.tc(fn -> suspected_slow_call() end)

# Statistical view
Benchee.run(%{"candidate" => fn -> suspected_slow_call() end}, warmup: 2, time: 5)

# Per-query visibility
# config/dev.exs:
config :my_app, MyApp.Repo, log: :debug
```

### 8.5 Flaky test

```
Symptom: test passes alone, fails in suite; random failures
```

| Likely cause | Fix |
|---|---|
| Shared global state (named GenServer, Application env, `:ets` table) | Use `start_supervised!` per test; avoid global names; explicitly reset state |
| Race condition: `Process.sleep` before assertion | Replace with `assert_receive pattern, 500` |
| Ecto sandbox: spawned process doesn't have DB access | `Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), spawned_pid)` |
| Wall-clock assertion against `DateTime.utc_now` | `assert_in_delta` with tolerance, or inject a clock module |
| Async mode but test uses named GenServer | Either use `async: false` or use a unique name per test |
| Factory sequence collision | Use `sequence/2` for unique fields |
| Test pollution via `:persistent_term` | Set + `on_exit` to erase, or use a per-test namespace |
| DB migration race in parallel CI | Run migrations serially before parallel tests |

**Find which test flakes:**

```bash
# Run in a repeatable order to isolate
mix test --seed 0 --max-failures 1

# Identify which earlier test pollutes the later one
mix test --trace --seed 12345   # pick a seed that reproduces
```

### 8.6 Dialyzer warnings

```
Symptom: Dialyzer flags contracts, missing callbacks, unreachable patterns, etc.
```

| Warning pattern | Usual cause | Fix |
|---|---|---|
| `Function X has no local return` | Function always raises, no branch returns | Add a return path, or mark with `@spec` returning `no_return()` |
| `Function X will never be called` | Typo in callback name / `@impl` mismatch | Correct name, add `@impl` |
| `The pattern can never match the type` | Redundant clause or wrong `@spec` | Remove dead clause; fix `@spec` |
| `The call ... will never return since it differs in arguments from the success typing` | `@spec` mismatched actual behavior | Align `@spec` with implementation |
| `Unmatched return` | Discarded return value from a fallible function | Explicitly match `{:ok, _} = ...` or `_ = ...` |
| Missing `@impl` | Callback not annotated | Add `@impl true` or `@impl BehaviourModule` |

**Dialyzer is slow for first-time PLT build (~10 minutes). After that incremental checks are fast. Run regularly in CI; fix warnings one at a time — do not baseline.**

### 8.7 Dev server won't start / compilation errors

| Symptom | Investigation | Fix |
|---|---|---|
| Module redefined warnings | Two modules defined with same name in different files | Rename one; check generators |
| "module X is not available" | Module not compiled yet or wrong path | Check `lib/` structure, `mix.exs` paths |
| Cyclic dependency | `mix xref graph` | Break cycle — extract shared module to a lower layer |
| `(CompileError) undefined function` | Called a function that doesn't exist | Check spelling; verify `alias` / `import` |
| Circular aliases / imports | Compile error "module X does not exist" despite existing | Reorder; break cycle |
| Phoenix endpoint crashes on start | Missing config, migration, or dependent process | Read the actual crash message; usually the first line is the truth |

### 8.8 Diagnostic escalation ladder

**Always start at step 1. Escalate only if it doesn't reveal the bug.**

1. **`IO.inspect` / `dbg`** — inspect values at suspected points
2. **`IEx.pry`** — pause execution and inspect bindings (`iex -S mix`)
3. **Test reproduction** — write a failing test that isolates the bug
4. **`:sys.trace` / `:sys.get_state`** — OTP process internals
5. **Logger at `:debug` level** — turn up the dials temporarily
6. **`:observer.start()`** — GUI system overview
7. **`:recon.*`** — production-safe process inspection
8. **`:recon_trace.calls/2` with message limit** — production tracing (ALWAYS set a limit)

### 8.9 Event-subscription boot gap — the retro-scan pattern

```
Symptom: a GenServer that subscribes to events (node up/down, process :DOWN, PubSub topic,
  Presence) shows empty state after start, misses peers/rows/members that were already there
  before the subscription was installed.
```

`:net_kernel.monitor_nodes/1,2`, `Process.monitor/1`, `Phoenix.PubSub.subscribe/2`, and `Phoenix.Tracker` all deliver only **future** events. Anything that existed before you subscribed is invisible unless you explicitly replay it.

**The fix is always the same shape:** subscribe first, then replay current state via `handle_continue/2` using the same handler as the live path.

```elixir
defmodule MyApp.ClusterWatcher do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    :ok = :net_kernel.monitor_nodes(true, node_type: :all)
    # Subscribe first (so no window between retro-scan and live events),
    # THEN deliver retro-events via handle_continue.
    {:ok, %{peers: MapSet.new()}, {:continue, {:retro_nodeup, Node.list()}}}
  end

  @impl true
  def handle_continue({:retro_nodeup, peers}, state) do
    new_state = Enum.reduce(peers, state, &add_peer/2)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:nodeup, node, _info}, state), do: {:noreply, add_peer(node, state)}
  def handle_info({:nodedown, node, _info}, state), do: {:noreply, remove_peer(node, state)}

  defp add_peer(node, state), do: %{state | peers: MapSet.put(state.peers, node)}
  defp remove_peer(node, state), do: %{state | peers: MapSet.delete(state.peers, node)}
end
```

**Same shape applies to:**

- `Process.monitor/1` against a DynamicSupervisor with existing children — on init, monitor each `DynamicSupervisor.which_children/1` result *after* setting up the monitor handler.
- `Phoenix.Presence.list/1` when subscribing to a populated topic — replay the current list in `handle_continue`.
- `Phoenix.PubSub.subscribe/2` for a topic where the "current state" is stored elsewhere (DB, ETS) — query it once in `handle_continue`.

**Why `handle_continue/2` and not doing the scan inline in `init/1`:** keeping `init/1` fast lets the supervisor's start sequence progress; the continue fires immediately after, in the same process, before any external message can arrive.

---

# Deep Reference

Symptom → diagnosis flow for Elixir bugs. Expanded from the quick reference above with concrete investigation steps, likely root causes, and minimum fixes.

**When to use this:** a bug is observed — "this crashes", "mailbox full", "memory leaks", "flaky test", "slow response", "Dialyzer warning" — and you need a structured approach.

---

## Debugging Principles

1. **Read the symptom carefully** — "slow" could mean p50, p99, tail. "Crash" means which error, stack, and frequency?
2. **Smallest tool first** — `IO.inspect` / `dbg` before tracing, `:observer` before profiling.
3. **Reproduce first, fix second** — an intermittent bug with no reproduction is just a hypothesis.
4. **Hypothesis → evidence → conclusion** — don't patch without evidence that the patch addresses the root cause.
5. **Monotonic time only** — never `System.system_time` for measuring durations (NTP jumps).

---

## Symptom: Process Crash

### 1. Read the crash report

Look for these fields in the Logger output:

- **`pid`** — which process died
- **Module/Function/Arity** — where the crash happened
- **`reason`** — what went wrong (the first line is the most important)
- **Stacktrace** — the call chain
- **State** (OTP processes) — what the state was at crash time

### 2. Classify the reason

| Reason | Likely cause | Fix |
|---|---|---|
| `FunctionClauseError` | Input didn't match any clause | Add a catch-all or widen an existing clause |
| `MatchError` | `=` binding failed; expected shape not present | Pattern match robustly or return tagged tuple |
| `ArgumentError` | Bad arg to stdlib (e.g., `String.to_integer("abc")`) | Validate or use `Integer.parse/1` |
| `UndefinedFunctionError` | Missing function or missing module | Check spelling, missing `@impl`, compile issues |
| `KeyError` | `Map.fetch!` or `struct.key` on missing key | `Map.fetch/2` or default via `Map.get/3` |
| `Protocol.UndefinedError` | Protocol not implemented for type | Implement protocol or guard input |
| `ArithmeticError` | `1 / 0`, `:foo + 1` | Validate numeric input; check for integer vs float |
| `:timeout` (from `GenServer.call`) | Callee didn't reply in time | Increase timeout, or make the callee faster/async |
| `:noproc` (from `GenServer.call`) | Target process not registered / dead | `Process.whereis` before call; supervisor not started |
| `:killed` | Process was explicitly `Process.exit(pid, :kill)` | Find who's killing it; `:observer` / `:recon` |
| `:shutdown` | Normal supervisor shutdown | Usually no fix needed |
| `:normal` from `GenServer.stop(:normal)` | Expected lifecycle | Ensure `:transient` isn't restarting on `:normal` |

### 3. Trace the call

If reason isn't obvious from the stack, reproduce and trace:

```elixir
# In dev / IEx:
:dbg.tracer()
:dbg.tpl(MyMod, :my_fun, :_, [])   # trace calls to MyMod.my_fun/*
:dbg.p(:all, :c)                    # trace all processes

# Or with recon (production-safe):
:recon_trace.calls({MyMod, :my_fun, :_}, 10, [formatter: :print])
```

### 4. Check for common patterns

- **Is this at a system boundary?** Unexpected data from HTTP, DB, or file — validate at the boundary.
- **Is this during init?** Dependencies not ready — use `handle_continue/2`.
- **Is this on shutdown?** Trapped exits but no terminate/2 — add one if needed.

---

## Symptom: Mailbox Buildup (Process Growth)

### 1. Identify the slow process

```elixir
# Find processes with large mailboxes
Process.list()
|> Enum.map(&{&1, Process.info(&1, [:message_queue_len, :registered_name, :memory])})
|> Enum.filter(fn {_, info} ->
  info[:message_queue_len] > 1000
end)
|> Enum.sort_by(fn {_, info} -> -info[:message_queue_len] end)
|> Enum.take(10)
```

Or with `:recon`:

```elixir
:recon.proc_count(:message_queue_len, 10)
```

### 2. Find who's sending

```elixir
# Inspect mailbox contents (careful — this copies the mailbox)
{:messages, msgs} = Process.info(pid, :messages)
msgs |> Enum.take(10) |> IO.inspect(label: "first 10 messages")
```

### 3. Common causes & fixes

| Symptom | Cause | Fix |
|---|---|---|
| Constant message rate but process can't keep up | Process handler too slow | Profile `handle_*` callbacks; offload work to `handle_continue` or Task |
| Mailbox growing monotonically | Selective receive — unwanted messages accumulate | Add catch-all `handle_info(_, state)` |
| `GenServer.cast` firehose | Fire-and-forget exceeds processing rate | Switch to `call` for natural backpressure, or add a bounded queue |
| Messages from dead processes (DOWN/EXIT) | Trapping exits + no cleanup | Handle `{:EXIT, _, _}` and `{:DOWN, _, _}` |
| `active: true` socket with slow handler | Data arrives faster than processed | Use `active: :once` or `active: N` |

### 4. Verify fix

After applying the fix:

```elixir
# Monitor mailbox length over time
Task.async(fn ->
  for _ <- 1..60 do
    case Process.info(pid, :message_queue_len) do
      nil -> :dead
      {:message_queue_len, n} -> IO.puts("#{n}"); Process.sleep(1000)
    end
  end
end)
```

---

## Symptom: Memory Growth (Leak)

### 1. Establish baseline

```elixir
# System-level memory
:erlang.memory() |> Enum.map(fn {k, v} -> {k, div(v, 1024 * 1024)} end)
# {:total, :processes, :system, :atom, :binary, :code, :ets}

# Per-process (top 10 by memory)
:recon.proc_count(:memory, 10)
```

### 2. Classify the growth

| Pattern | Likely cause |
|---|---|
| `:processes` growing | A process's state or mailbox is growing |
| `:binary` growing | Binary leak — refcounted binaries piling up |
| `:ets` growing | ETS table accumulating without expiry |
| `:atom` growing | `String.to_atom` on user input — fatal long-term |
| `:code` growing | Hot code reload gone wrong, or runtime module generation |

### 3. Investigate each type

#### Processes

```elixir
# Find the growing PID
:recon.proc_count(:memory, 10)

# What's in the state?
:sys.get_state(pid)   # May be huge — don't IO.inspect it raw

# What's binary references?
Process.info(pid, :binary)

# Are messages backing up?
Process.info(pid, :message_queue_len)
```

#### Binary leak

The classic Elixir leak: refcounted binaries (>64 bytes) are held by processes that don't GC often.

```elixir
# Identify processes holding many binary refs
:recon.bin_leak(10)
# Garbage collects those processes, returns top 10 freed

# Or manually GC a specific process
:erlang.garbage_collect(pid)

# Tune fullsweep_after for chatty processes
Process.flag(:fullsweep_after, 10)  # GC every 10 minor collections
```

#### ETS

```elixir
# List all tables
:ets.all() |> Enum.map(&{&1, :ets.info(&1, :size), :ets.info(&1, :memory)})
|> Enum.sort_by(fn {_, _, m} -> -m end)

# Biggest entries in a specific table
:ets.select(:my_table, [{:"$1", [], [:"$1"]}]) |> Enum.take(5)
```

Common fix: add a periodic cleanup process, or switch to a bounded cache (`cachex`, `nebulex`).

#### Atom growth

```elixir
# Count total atoms
:erlang.system_info(:atom_count)
:erlang.system_info(:atom_limit)

# Find who's creating atoms — grep the codebase
# rg "String.to_atom|to_atom\(" lib/
```

Fix: replace `String.to_atom/1` with `String.to_existing_atom/1` or explicit whitelists.

---

## Symptom: Slow Response

### 1. Identify the bottleneck layer

Ask: is it the DB, the code, the network, or contention?

```elixir
# Measure end-to-end
{time_us, result} = :timer.tc(fn -> MyMod.slow_fun(arg) end)
IO.puts("Took #{div(time_us, 1000)}ms")
```

### 2. Drill into the slow layer

#### Database

- Enable Ecto query logging: `config :my_app, MyApp.Repo, log: :debug`.
- Look for N+1 patterns (same query repeated with different IDs).
- Check for missing indexes: `EXPLAIN ANALYZE` the slow query.
- Check for transaction held too long.

```elixir
# Time a single Ecto query
{time_us, _} = :timer.tc(fn -> Repo.all(query) end)
```

#### Code

```elixir
# Profile with fprof (expensive — dev only)
:fprof.apply(&MyMod.slow_fun/1, [arg])
:fprof.profile()
:fprof.analyse(dest: ~c"/tmp/fprof.analysis", sort: :own)

# Or eprof (time spent per function)
:eprof.profile(fn -> MyMod.slow_fun(arg) end)
:eprof.analyze(:total)

# Or benchee for comparative benchmarks
Benchee.run(%{
  "old" => fn -> old_impl(data) end,
  "new" => fn -> new_impl(data) end
})
```

#### Network / external calls

- Add `:telemetry` timing around external calls.
- Check retries + timeout stack (5s timeout x 3 retries = 15s total).
- Use `Req` with `receive_timeout` and `pool_timeout`.

### 3. Common slow patterns

| Pattern | Fix |
|---|---|
| `Enum.map` over a list of 10K items, each calling Repo | Preload or batch |
| Nested `Enum.filter \|> Enum.map` | Single `for` comprehension |
| Scanning an ETS table with `foldl` | Add `:ordered_set` or use match spec |
| Calling `Map.to_list \|> Enum.find` | Direct `Map.fetch` |
| `++` for list append in a loop | Accumulate head-first, reverse at end |
| Spawn-heavy workload | `Task.async_stream/3` with `:max_concurrency` |

---

## Symptom: Flaky Test

### 1. Identify the flake category

Run the failing test 100x in isolation:

```sh
for i in {1..100}; do mix test path/to/test.exs:42 || break; done
```

If it passes consistently in isolation, the flake is cross-test interference. If it fails intermittently in isolation, it's test-internal timing or nondeterminism.

### 2. Common flake sources

| Category | Cause | Fix |
|---|---|---|
| Cross-test | `async: true` but shared global state (Application env, singleton GenServer) | Make the test `async: false` OR isolate the global |
| Timing | `Process.sleep` waiting for something | Use `assert_receive` with explicit timeout |
| Timing | `Task` completion not awaited | `Task.await` or `assert_receive` for a telemetry signal |
| Nondeterminism | Test depends on map iteration order | Normalize output (sort) before asserting |
| Nondeterminism | Random seed, UUIDs, PID ordering | Make seed deterministic or match on structure only |
| DB state | Test hits DB with `async: true` + shared connection | Use `Ecto.Adapters.SQL.Sandbox.allow/3` |
| Port contention | Test starts listening socket on fixed port | Use port `0` (OS-assigned) |
| ExUnit timeout | Async work runs past assertion | Tighten upstream timeout or await explicitly |

### 3. Tools to confirm flakes

```elixir
# Run until failure with seed
mix test --seed 0 --max-failures 1
mix test --trace             # serial, verbose — exposes cross-test leaks

# Repeat N times
mix test --seed 12345 --max-failures 1 --include tag_to_repeat
```

---

## Symptom: Dialyzer Warning

### 1. Read the warning carefully

Dialyzer warnings are precise. Example:

```
my_app.ex:42: The pattern {:ok, _} can never match the type {:error, atom()}
```

This means: at line 42, the code does `case foo() do {:ok, _} -> ...`, but Dialyzer has inferred that `foo()` only returns `{:error, _}`. Three possibilities:

1. The spec of `foo` is wrong (says both, returns only error).
2. The code logic is wrong (should handle both, but only does error).
3. Dialyzer has incomplete info and needs a hint.

### 2. Common warning types

| Warning | Meaning | Fix |
|---|---|---|
| "No return" | Function never returns (always raises/exits) | Spec as `:: no_return()` or `:: t() \| no_return()` |
| "The pattern can never match" | Dead code / impossible case | Remove the impossible clause, or fix the upstream spec |
| "Function has no specs" | `@spec` missing | Add `@spec` |
| "The call will never return" | Call target always raises | Check the callee's spec |
| "Missing return" | Spec says `X` but code path returns nothing | Add missing return or widen spec |
| "Opaque term" | Pattern matching on internal `@opaque` type | Use the opaque type's public API instead |
| "Underspecs" | Your spec is looser than the actual return | Tighten the spec |
| "Overlapping contract" | Multi-clause specs overlap | Consolidate or disambiguate |

### 3. Fixing vs suppressing

Always prefer fixing over suppressing. When suppression is necessary (third-party library issues, known false positive):

```elixir
# In .dialyzer_ignore.exs
[
  {"lib/foo.ex", :no_return, 42},
  ~r/deps\/some_third_party\/.*/
]
```

---

## Symptom: CPU Pegged to 100%

### 1. Find the busy scheduler

```elixir
# Scheduler utilization
:scheduler.utilization(5)       # 5-second sample
# or with recon:
:recon.scheduler_usage(1000)    # 1-second sample
```

### 2. Find the busy process

```elixir
# Top processes by reductions (execution budget used)
:recon.proc_count(:reductions, 10)

# Top by reductions in a 1-second window
:recon.proc_window(:reductions, 10, 1000)
```

### 3. Profile the busy process

```elixir
# Tprof (statistical sampling; less overhead than fprof)
:tprof.start(%{type: :call_count})
:tprof.enable_trace({:all, :all})
:tprof.set_pattern({MyMod, :_, :_})
# ... let it run ...
data = :tprof.stop()
:tprof.format(data)
```

Common causes:
- Tight CPU loop (infinite recursion without `Process.sleep/1` or inbound messages)
- Regex catastrophic backtracking
- JSON-encoding a very deep/large structure repeatedly
- Compiling the same module at runtime (module cache miss)

---

## `IEx.break!/2` — Breakpoints Without Code Changes

When you can't or don't want to modify source (production-style node, third-party library, debugging a compiled release), set a breakpoint from the IEx shell.

```elixir
# Start IEx with your app loaded:
iex -S mix

# In the shell — break on the next call to MyMod.my_fun/2
iex> break!(MyMod, :my_fun, 2)
# → #PID<0.123.0> is printed; a breakpoint is armed.

# When any process calls MyMod.my_fun/2, execution pauses
# and that process drops into an IEx pry session.
# All local bindings (args + variables in scope) are accessible.
```

### Managing breakpoints

```elixir
# List active breakpoints
iex> breaks()
# [ID: 1, module: MyMod, function: my_fun/2, hits: 0, active: true]

# Break at a specific line
iex> break!(MyMod, 42)   # line number instead of function

# Remove a breakpoint
iex> remove_breaks(MyMod)    # all in module
iex> remove_breaks()         # all everywhere

# Reset hit count (keeps breakpoint armed)
iex> reset_break(id)

# Deactivate without removing
iex> disable_break(id)
iex> enable_break(id)
```

### Hit count

By default, `break!/2` fires every time. Limit to N hits:

```elixir
iex> break!(MyMod, :my_fun, 2, 5)   # fires 5 times, then auto-removes
```

### Conditional breakpoints (pattern match)

`break!/2,3,4` accepts a function with a pattern — pause only when the pattern matches:

```elixir
# Break only when the first arg is :admin
iex> break!(MyMod.my_fun(:admin, _))
# (uses the `defmodule`/`def` capture syntax)
```

### When to use break! vs IEx.pry vs dbg

| Tool | Situation |
|---|---|
| `dbg/1` | You're editing the code and want pipeline-aware inspection. Ship cleanup. |
| `IEx.pry/0` | You're editing the code and want an interactive breakpoint. |
| `break!/2` | You can't edit the code (third-party lib, compiled release, production-shape node). |

**Safety:** `break!/2` is for dev/staging. Do not use in a production node serving real traffic — the paused process blocks its mailbox.

---

## Debugging Tools Cheat Sheet

| Tool | Use for | Safety |
|---|---|---|
| `IO.inspect/2` | Check a single value mid-pipeline | Always safe |
| `dbg/1` | Inspect multiple values in a block | Always safe |
| `IEx.pry/0` | Interactive breakpoint (requires source edit) | Dev only |
| `IEx.break!/2,3,4` | Breakpoint without modifying source | Dev / staging only |
| `:recon.proc_count/2` | Top processes by metric | Safe in production |
| `:recon_trace.calls/3` | Trace live function calls (bounded) | Safe in production (with count limit) |
| `:observer.start()` | GUI inspection | Dev only |
| `:sys.get_state/1` | Peek at a GenServer's state | Safe in production (but may be huge) |
| `:erlang.trace/3` | Raw Erlang tracing | NEVER production — no limits |
| `:dbg.tracer()` | Old-style tracing | NEVER production |
| `mix profile.fprof` | Full call trace profiling | Dev only — very slow |
| `mix profile.eprof` | Time-per-function profiling | Dev only |
| `mix profile.tprof` | Sampling profiler | OK in dev; low overhead |
| Benchee | Comparative benchmarks | Dev only |
| Telemetry | Production metrics | Production |
| `Process.info/2` | Quick process introspection | Always safe |
| `:erlang.memory/0` | System memory breakdown | Always safe |

---

## Cross-References

- **Core reviewing skill:** [SKILL.md](SKILL.md) — rules, severity, workflows
- **Performance pitfalls catalog:** [performance-catalog.md](performance-catalog.md)
- **Profiling tool deep-dive:** [profiling-playbook.md](profiling-playbook.md)
- **Refactor templates:** [refactor-templates.md](refactor-templates.md)
