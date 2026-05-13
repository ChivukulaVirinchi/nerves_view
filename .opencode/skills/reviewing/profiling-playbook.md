# Profiling Playbook

> **Depth file for [SKILL.md](SKILL.md).** Load when measuring or optimizing performance. Quick Reference (inline summary) first, then full depth below.

---

## Quick Reference — picking the right tool

### 9.1 Which profiler?

| Need | Tool | Overhead | When |
|---|---|---|---|
| Time one expression | `:timer.tc/1` | Negligible | Quick sanity check. Unreliable without warmup |
| Compare two implementations | `Benchee.run/2` | Low | **Default for microbenchmarks.** Warmup, statistics, memory |
| Find the slow function in a call tree | `mix profile.fprof` | **High** | Dev/CI only; not production |
| Aggregate time per function | `mix profile.eprof` | Moderate | Slightly cheaper than fprof; ok for focused profiling |
| Just count calls | `mix profile.cprof` | Low | "What's called most?" |
| Modern unified profiler | `mix profile.tprof` | Low-moderate | OTP 27+; prefer for large codebases |
| Per-request production timing | `:telemetry.span/3` + handler | Very low | Always-on, production-safe |
| System-wide interactive view | `:observer.start()` | Moderate | Dev only; GUI |
| Top-N processes programmatically | `:recon.proc_count(:memory \| :message_queue_len \| :reductions, N)` | Low | Production-safe |
| Find binary memory leaks | `:recon.bin_leak(N)` | Moderate (forces GC) | Periodic in prod |

### 9.2 `Benchee` — the default microbench

```elixir
Benchee.run(
  %{
    "impl_a" => fn -> my_function_a() end,
    "impl_b" => fn -> my_function_b() end
  },
  warmup: 2,               # 2 seconds of warmup per input (BEAM JIT settles)
  time: 5,                 # 5 seconds of measurement per input
  memory_time: 2,          # measure memory too
  inputs: %{                # optional: run each variant across multiple inputs
    "small" => 1..100,
    "large" => 1..10_000
  }
)
```

**Rules:**

- Always `warmup` on OTP 24+ (JIT); 2 seconds is fine for most code
- Use `inputs` when performance depends on input size — catches O(n) vs O(n^2)
- Add `memory_time` if memory is suspected; it measures heap allocations
- Benchee results are comparative, not absolute — use the same machine, same load

### 9.3 `mix profile.*` — when

```bash
# Profile a one-off expression (the :do: form)
mix profile.fprof -e 'MyApp.Cold.start()'
mix profile.eprof -e 'MyApp.Search.query("long search string")'

# Profile a test
mix profile.fprof --profile test/my_app/orders_test.exs
```

**Which one?**

- `fprof` — most detailed, shows per-call time with calling context. **Highest overhead**; use in dev/CI to find the slow function.
- `eprof` — aggregate time per function. Lower overhead than fprof.
- `cprof` — just counts calls. Lowest overhead. Use to find "what's called most."
- `tprof` (OTP 27+) — unified interface, lower overhead than fprof. **Prefer this on OTP 27+.**

**Read the output:** Look for the functions with the highest `OWN` (self) time, not `ACC` (accumulated). High `ACC` just means "it called something slow"; high `OWN` means "this function itself is slow."

### 9.4 `:observer` — GUI system view

```elixir
# In IEx (dev)
:observer.start()
# - Applications tab: supervision tree visualization
# - Processes tab: sortable list by memory, reductions, mailbox
# - ETS tab: table sizes
# - Load charts: CPU, memory, IO
```

**Not for production.** Observer is an interactive tool for development. In production, use `:recon` + `:telemetry`.

### 9.5 `:recon` — production-safe

```elixir
# Top processes by memory
:recon.proc_count(:memory, 10)

# Top processes by mailbox length
:recon.proc_count(:message_queue_len, 10)

# Top processes by CPU reductions
:recon.proc_count(:reductions, 10)

# Binary memory leak detection (forces GC, then ranks)
:recon.bin_leak(10)

# Safe tracing with message limit (CRUCIAL in prod)
:recon_trace.calls({MyModule, :my_function, :return_trace}, 100)
# Automatically stops after 100 traces
:recon_trace.clear()
```

**Rule:** `:recon_trace` always sets a message limit. **Never use `:dbg.tp` / `:erlang.trace` in production** — they have no limits and can crash the node under load.

### 9.6 Telemetry — always-on, zero-overhead production measurement

```elixir
# Emit a span around the work
:telemetry.span([:my_app, :orders, :fulfill], %{order_id: order.id}, fn ->
  result = do_fulfill(order)
  {result, %{items: length(order.items)}}
end)

# Handle events and feed them to a metrics store
:telemetry.attach(
  "orders-fulfill",
  [:my_app, :orders, :fulfill, :stop],
  fn _event, %{duration: d}, _meta, _config ->
    :telemetry_metrics.histogram(:orders_fulfill_duration, d)
  end,
  nil
)
```

**Production-grade profiling:** telemetry → metrics backend (Prometheus, StatsD, PromEx). Gives you always-on p50/p95/p99 latency per operation with no overhead.

### 9.7 Memory profiling — specific symptoms

| Symptom | Command | What to look for |
|---|---|---|
| Total memory growing | `:erlang.memory()` over time | Which category (processes/binary/ets) is growing |
| Specific process growing | `:erlang.process_info(pid, [:memory, :total_heap_size, :heap_size])` | Growing heap = accumulating state |
| Binary memory large | `:recon.bin_leak(10)` | Who's holding large binary refs |
| ETS large | `for t <- :ets.all(), do: {t, :ets.info(t, :memory)}` | Sort by size |
| Atom table growing | `:erlang.system_info(:atom_count)` | Unsafe `to_atom`? |

### 9.8 Profiling decision tree

```
Where is the slowness?
├── I don't know → telemetry on request level, find the slow operation
├── Known operation → Benchee to measure, fprof/eprof/tprof to find the hot function
├── One specific function → Benchee with `warmup` + `inputs` at multiple sizes
└── Multiple processes → :observer (dev) or :recon.proc_count (prod)

What's causing memory growth?
├── Don't know which category → :erlang.memory() over time
├── Binaries → :recon.bin_leak/1
├── A specific process → :erlang.process_info(pid, [:memory, :total_heap_size])
├── ETS → :ets.info(table, :memory)
└── Atom table → stop calling String.to_atom/1 on user input
```

---

# Deep Reference

How to pick and use each Elixir/BEAM profiling tool. Phase-focused on **investigating performance issues** in existing code. Covers measurement, tool selection, interpreting output, and the specific cases each tool serves best.

---

## Profiling Principles

1. **Measure, don't guess.** Without evidence, "optimization" usually changes the code without improving it — or makes it worse.
2. **Establish a baseline before changing anything.** Record numbers; you can't claim improvement without a before/after.
3. **Profile closest to the symptom.** If production is slow, profile production-similar workloads. A dev benchmark at 100 items won't surface a production bug at 100K items.
4. **Use monotonic time.** `System.monotonic_time/1` or `:erlang.monotonic_time/0` — never `System.system_time` for durations (NTP can jump).
5. **Pick the right granularity.** One-shot timing → `:timer.tc`. Comparative → Benchee. Deep dive → `fprof`/`eprof`/`tprof`. System-wide → `:observer` + `:recon`.

---

## Tool Selection Decision Table

| Need | Tool | Overhead | Production-safe |
|---|---|---|---|
| Time a single function call once | `:timer.tc/1` | None | Yes |
| Compare two or more implementations | `Benchee` | Low | Dev only |
| Find where time is spent inside a function | `:fprof` | **HIGH** (10-50x) | No |
| Aggregate time per function (call profile) | `:eprof` | Medium | No |
| Aggregate call counts per function | `:cprof` | Medium | No |
| Sampling profiler (prod-grade) | `:tprof` (OTP 27+) | Low | Yes, with caution |
| Top processes by memory/reductions/mailbox | `:recon.proc_count` | Very low | Yes |
| Trace specific function calls (bounded) | `:recon_trace.calls` | Low (limited) | Yes |
| System-wide introspection (GUI) | `:observer.start()` | Low (but opens remote shell) | Staging only |
| Memory breakdown by allocator | `:erlang.memory/0` | None | Yes |
| Binary leak detection | `:recon.bin_leak` | Medium (triggers GC) | Careful — pauses procs |
| Scheduler utilization | `:scheduler.utilization` | None | Yes |
| Per-query DB timing | Telemetry `[:my_app, :repo, :query]` | None | Yes |

---

## `:timer.tc/1` — Quick Timing

```elixir
# Single call
{time_us, result} = :timer.tc(fn -> MyMod.slow_fun(arg) end)
IO.puts("#{div(time_us, 1000)}ms")

# MFA form (slightly less overhead)
{time_us, result} = :timer.tc(MyMod, :slow_fun, [arg])
```

**Returns microseconds**. Divide by 1000 for ms, 1_000_000 for seconds.

**Caveat:** First run often includes JIT warm-up / module load. Discard the first sample for steady-state analysis.

```elixir
# Warm up, then measure 5 runs
_ = MyMod.slow_fun(arg)
times = for _ <- 1..5, do: elem(:timer.tc(fn -> MyMod.slow_fun(arg) end), 0)
IO.inspect(times, label: "runs (us)")
```

---

## Benchee — Comparative Benchmarking

### Basic

```elixir
Benchee.run(%{
  "old_impl" => fn -> Old.sort(large_list) end,
  "new_impl" => fn -> New.sort(large_list) end
})
```

### With inputs

```elixir
Benchee.run(
  %{
    "old" => fn input -> Old.process(input) end,
    "new" => fn input -> New.process(input) end
  },
  inputs: %{
    "small (100)" => Enum.to_list(1..100),
    "medium (10k)" => Enum.to_list(1..10_000),
    "large (1M)" => Enum.to_list(1..1_000_000)
  },
  time: 5,              # seconds per scenario
  warmup: 2,            # warmup seconds
  memory_time: 2,       # measure memory usage
  print: %{configuration: false}
)
```

### Reading output

Benchee reports:

- **ips** — iterations per second. Higher = faster.
- **average** — mean time per iteration.
- **deviation** — stability (low % = consistent).
- **median** — robust central tendency.
- **99th %** — tail latency.
- **Memory Usage** — bytes allocated per iteration.

**Comparison table** shows relative speed: `1.5x slower` means `new` is 1.5x slower than the fastest.

### Formatters

```elixir
Benchee.run(%{...},
  formatters: [
    {Benchee.Formatters.Console, comparison: true},
    {Benchee.Formatters.HTML, file: "bench.html"}
  ]
)
```

---

## `:fprof` — Full Call Tree Profile

**Use when:** you need to see every function call and the time spent in each, including callees.

**Cost:** 10-50x slowdown. Dev/staging only.

```elixir
:fprof.apply(&MyMod.slow_fun/1, [arg])
:fprof.profile()
:fprof.analyse(dest: ~c"/tmp/fprof.txt", sort: :own)

# Read it
File.read!("/tmp/fprof.txt")
```

**Key columns:**
- `CNT` — number of calls
- `ACC` — accumulated time (self + children)
- `OWN` — own time (excluding children)

Sort by `:own` to find the slowest functions; sort by `:acc` to find the heaviest call chains.

---

## `:eprof` — Time Per Function

**Use when:** you want a summary of "which functions consumed the most time" without the call tree.

**Cost:** Lower than fprof, still not production-safe.

```elixir
:eprof.start()
:eprof.profile(fn -> MyMod.do_work(data) end)
:eprof.analyze()          # prints to stdout
:eprof.stop()

# Or analyze to a file
:eprof.log(~c"/tmp/eprof.txt")
:eprof.analyze(:total)
:eprof.stop_profiling()
```

**Key columns:**
- `CALLS` — number of calls
- `% TIME` — proportion of total time

Use when the top-3 slowest functions are suspected — less detail than fprof, faster to read.

---

## `:cprof` — Call Counts

**Use when:** you want to know "which functions run the most," regardless of time.

Good for finding code hot paths that might not be slow individually but run very often.

```elixir
:cprof.start()
_ = MyMod.do_work(data)
analysis = :cprof.analyse()
:cprof.stop()

analysis
|> Enum.take(20)
|> Enum.each(fn {mfa, count, _} -> IO.puts("#{inspect(mfa)}: #{count}") end)
```

---

## `:tprof` — Statistical Sampling (OTP 27+)

**Use when:** you need production-safe profiling, or want low-overhead analysis in dev.

```elixir
:tprof.start(%{type: :call_count})
:tprof.set_pattern({MyMod, :_, :_})
_ = MyMod.do_work(data)
result = :tprof.stop()
:tprof.format(result)
```

Three modes:
- `:call_count` — how many times each function was called
- `:call_time` — time spent in each function (similar to eprof)
- `:call_memory` — memory allocated per call

---

## `:observer.start()` — GUI Inspector

**Use when:** you need to explore a live system interactively — running processes, applications, ETS tables, tracing.

**Staging/dev only.** Not for production (GUI requires remote shell access).

```elixir
iex> :observer.start()
```

Tabs worth knowing:
- **System** — version, schedulers, memory
- **Applications** — supervision tree
- **Processes** — sortable list; right-click → inspect state
- **ETS** — tables and sizes
- **Trace Overview** — wire up ad-hoc tracing

---

## `:recon` — Production-Safe Introspection

`:recon` is the production toolbox. Bounded, deadlock-free, won't crash your node.

### Top processes

```elixir
# Top 10 by memory
:recon.proc_count(:memory, 10)

# Top 10 by message queue
:recon.proc_count(:message_queue_len, 10)

# Top 10 by reductions (CPU budget)
:recon.proc_count(:reductions, 10)

# Window sampling (top 10 that consumed most reductions in last 1s)
:recon.proc_window(:reductions, 10, 1000)
```

### Binary leak

```elixir
# Force GC on top 10 processes, report freed binary memory
:recon.bin_leak(10)
```

### Trace live function calls

```elixir
# Trace 100 calls to MyMod.fun/* (any arity), with their args
:recon_trace.calls({MyMod, :fun, :_}, 100)

# Trace with a match spec — only calls where first arg is :active
:recon_trace.calls({MyMod, :handle, [{[:active, :_], [], []}]}, 10)

# Stop tracing
:recon_trace.clear()
```

Always pass an explicit count limit — unbounded tracing can overwhelm a node.

---

## Memory Analysis

### System-wide breakdown

```elixir
:erlang.memory()
# [
#   total: 80_000_000,    # total used
#   processes: 20_000_000,
#   system: 60_000_000,
#   atom: 1_200_000,
#   atom_used: 1_100_000,
#   binary: 5_000_000,
#   code: 25_000_000,
#   ets: 8_000_000
# ]

# Human-readable
:erlang.memory() |> Enum.map(fn {k, v} -> {k, div(v, 1024 * 1024)} end)
```

### Per-process

```elixir
Process.info(pid, [:memory, :heap_size, :stack_size, :total_heap_size, :message_queue_len, :binary])
```

### ETS

```elixir
:ets.all()
|> Enum.map(fn tab ->
  {:ets.info(tab, :name), :ets.info(tab, :size), :ets.info(tab, :memory)}
end)
|> Enum.sort_by(fn {_, _, m} -> -m end)
|> Enum.take(10)
```

### Binary reference tracking

A process holds a "ref" to a refcounted binary (>64 bytes) until it GCs. Processes that don't GC often can hold many refs.

```elixir
Process.info(pid, :binary)  # List of binary refs this process holds
length(Process.info(pid, :binary) |> elem(1))  # How many
```

---

## Telemetry — Production Metrics

Lightweight, production-safe metrics via `[:app, :subsystem, :event]` names.

```elixir
# Instrument an operation
:telemetry.span([:my_app, :search], %{query: q}, fn ->
  result = do_search(q)
  {result, %{result_count: length(result)}}
end)
# Emits :start and :stop events with duration measured in :native time units

# Attach a handler (ideally in application.ex or a dedicated module)
:telemetry.attach(
  "slow-search-log",
  [:my_app, :search, :stop],
  fn _event, %{duration: d}, meta, _cfg ->
    if System.convert_time_unit(d, :native, :millisecond) > 500,
      do: Logger.warning("Slow search: #{inspect(meta)}")
  end,
  nil
)
```

Common auto-emitted events:
- `[:phoenix, :endpoint, :stop]` — request duration
- `[:phoenix, :router_dispatch, :stop]` — controller-level time
- `[:ecto, :my_app, :repo, :query]` — SQL query timings
- `[:oban, :job, :stop]` — job durations

---

## Scheduler Utilization

```elixir
# Sample utilization for 5 seconds
samples = :scheduler.utilization(5)
# [{1, 0.42}, {2, 0.38}, ...]  # scheduler id → fraction busy

# Or with recon
:recon.scheduler_usage(5000)
```

High (>0.8) and sustained → CPU-bound. Check:
- Busy processes via `:recon.proc_count(:reductions, 10)`.
- Tight loops (a function that never yields to the scheduler).
- NIF overuse (NIFs can't be preempted under 1ms).

---

## Common Profiling Traps

### 1. Measuring only first run

JIT warmup, module loading, and caches aren't representative. Always do a warm-up run first.

### 2. Measuring with `Process.sleep` in the target

Sleeping doesn't consume CPU — don't benchmark a function that sleeps; you'll measure wall-clock not work.

### 3. Benchmarking in release vs dev build

Dev build has `--warnings-as-errors`, no optimizations. Release build has consolidated protocols. Measure in `MIX_ENV=prod`:

```sh
MIX_ENV=prod mix run bench.exs
```

### 4. Ignoring GC pauses

Large-heap processes may show artificially consistent timing because GC happens between benchmarks. Use `memory_time: 2` in Benchee to surface allocation patterns.

### 5. Profiling the benchmark harness

`fprof` captures everything — including the wrapping function. Filter to your target modules:

```elixir
:fprof.apply(&MyMod.target/1, [arg], procs: [self()], trace: [:call])
:fprof.profile()
```

### 6. Measuring end-to-end time with external deps

If the function calls `HTTPoison.get!`, you're timing the network. Separate:
- `MyMod.transform_response(pre_fetched_body)` — pure code
- full end-to-end — including network

### 7. Hot vs cold cache

Database/page cache, connection pool warm-up, etc. Decide which scenario you want to measure and configure accordingly.

---

## Workflow: Suspected Performance Bug

1. **Reproduce** — get a repeatable trigger (fixture, prod-similar workload).
2. **Baseline** — measure end-to-end time with `:timer.tc` or Benchee.
3. **Localize** — run `:fprof`/`:eprof` to find the hot functions.
4. **Hypothesize** — pick ONE suspected bottleneck.
5. **Fix** — apply the minimum change.
6. **Verify** — rerun the exact baseline measurement; record improvement.
7. **Repeat** — pick the next bottleneck if SLO not met.

**Don't skip step 6.** Without an after-measurement, you don't have evidence the fix helped.

---

## Cross-References

- **Core reviewing skill:** [SKILL.md](SKILL.md) — rules, severity, workflows
- **Symptom → diagnosis playbook:** [debugging-playbook.md](debugging-playbook.md)
- **Common performance pitfalls + fixes:** [performance-catalog.md](performance-catalog.md)
- **Refactor templates:** [refactor-templates.md](refactor-templates.md)
