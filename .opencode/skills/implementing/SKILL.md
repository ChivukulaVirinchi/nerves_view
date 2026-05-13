---
name: elixir-implementing
description: >
  Elixir implementation — decision tables, templates, anti-patterns for idiomatic code.
  ALWAYS use when writing Elixir code, choosing control-flow constructs, writing OTP callbacks,
  writing tests/TDD, or refactoring toward idiomatic form.
---

# Elixir — Implementing Skill

One of three Elixir skills: **implementing** (this — what to type), **planning** (what to build), **reviewing** (how to critique). Decision tables carry the most weight here.

### Subskills — deep implementation references

This file carries the always-loaded decision tables and core rules. Load a subskill for depth:

| File | Covers | Load when |
|---|---|---|
| [tdd-workflow.md](tdd-workflow.md) | TDD cycle, test templates, Mox, sandbox, factories | Writing tests |
| [critical-patterns.md](critical-patterns.md) | Pipelines, `with`, comprehensions, recursion, composition, security | Writing pipelines or composition patterns |
| [anti-patterns.md](anti-patterns.md) | BAD/GOOD pairs across all categories | Validating code against LLM mistakes |
| [daily-ops.md](daily-ops.md) | ok/error, module structure, naming, config, logging, Mix, IEx | Module structure, naming, config |
| [otp-decisions.md](otp-decisions.md) | GenServer, Task, ETS, supervisors, memoization | OTP/process code |
| [architecture-decisions.md](architecture-decisions.md) | Contexts, behaviour/protocol, config, Ecto boundary, layout | Where code lives, polymorphism |
| [idioms-reference.md](idioms-reference.md) | Pattern matching, guards, Enum/Stream, reduce, recursion, protocols, behaviours | Idiomatic control flow |
| [data-reference.md](data-reference.md) | Maps, structs, keywords, tuples, lists, binaries | Data-structure manipulation |
| [otp-callbacks.md](otp-callbacks.md) | GenServer/Task/Agent/gen_statem templates, GenStage/Broadway | OTP callback code |
| [ecto-impl.md](ecto-impl.md) | Schemas, changesets, queries, migrations, Multi | Ecto code |
| [type-and-docs.md](type-and-docs.md) | @spec, @type, @doc, Dialyzer, gradual typing | Types and documentation |
| [networking-patterns.md](networking-patterns.md) | TCP/UDP, protocol framing, Ranch, TLS, HTTP | Network code |
| [code-style.md](code-style.md) | Formatter, Credo, module organization, style | Style compliance |
| [production-patterns.md](production-patterns.md) | Production Phoenix patterns, NimbleOptions, library authoring | Production-ready code |
| [stdlib-cheatsheet.md](stdlib-cheatsheet.md) | Enum/Map/String/File/Process/Erlang stdlib signatures | Quick signature lookup |
| [beam-databases.md](beam-databases.md) | ETS, DETS, Mnesia, CubDB, :persistent_term | BEAM-native storage |

### Domain & framework references (within this folder)

| File | Covers | Load when |
|---|---|---|
| [ecto.md](ecto.md) | Schemas, changesets, queries, migrations, race-safe upserts | Writing Ecto code |
| [otp.md](otp.md) | GenServer vs Task vs Agent, supervision, Registry, ETS | Choosing/writing OTP constructs |
| [testing.md](testing.md) | ExUnit, Mox, factories, LiveView testing, async safety | Writing tests |
| [heex.md](heex.md) | HEEx interpolation, class lists, conditional rendering | Writing templates |
| [oban.md](oban.md) | Worker design, queues, uniqueness, error handling | Writing Oban workers |
| [phoenix-forms.md](phoenix-forms.md) | LiveView forms, validation, changeset integration | Writing forms |
| [phoenix-uploads.md](phoenix-uploads.md) | File uploads, progress, storage destinations | Adding uploads |
| [phoenix/phoenix.md](phoenix/phoenix.md) | Controllers, plugs, routing, channels, deployment | Writing Phoenix code |
| [liveview/liveview.md](liveview/liveview.md) | Lifecycle, streams, components, async, hooks | Writing LiveView code |

**Navigation:** §0 (gate) before any code → §1 (rules) → §2 (decision tables) → depth files as needed. For architecture, load `../planning/SKILL.md`. For review, load `../reviewing/SKILL.md`.

---

## 0. The TDD Gate — Read Before Any Implementation

**This gate fires BEFORE §1 or §2.** If you're about to type `def some_new_function`, answer these four questions first:

1. What is the function's name and module?
2. What is the test file and test name that covers its happy path?
3. Does that test exist on disk **right now**?
4. Did that test fail for the expected reason when you last ran it?

If ANY answer is "no" or "I'll write it after", STOP. Write the test, run `mix test path/to/test.exs`, confirm red. Then implement.

**No exceptions** for public API, business logic, refactors, changeset validations, `with` chains, or context-boundary crossings — those are why this gate exists.

### Milestone-boundary checklist

Before committing a milestone or multi-module change: name every new public function, its test file, and its error-path test. If any answer is "no", write the tests first, then commit.

### Bug-fix rule

Every bug-fix commit MUST include a regression test that would have caught the original bug. Shipping a fix without a regression test is not a fix.

### Autonomous-mode warning

**Tests later is tests never.** TDD compounds across milestones. This gate overrides session-level velocity pressure. If you're reasoning "I'll batch tests after M5", you are the failure mode this section prevents.

### Audit from git, not self-report

```bash
git log --format="%H %s" --name-status -- path/to/module.ex path/to/module_test.exs
# If test file appears AFTER impl file, TDD did not happen.
```

### Tests-after exceptions

Only: HEEx/EEx templates, CSS/styling, one-off scripts outside `lib/`. A `def` in `lib/` is production code — no exemptions.

---

## 1. Rules for Writing Elixir (LLM)

1. **ALWAYS pass the TDD gate (§0) before writing production code.** This rule overrides all others.
2. **ALWAYS consult §2** when choosing between `if`, `case`, `cond`, `with`, multi-clause functions.
3. **NEVER `if`/`else` for structural dispatch.** Use multi-clause with pattern matching.
4. **NEVER `try`/`rescue` for expected failures.** Return `{:ok, _}`/`{:error, _}` tuples. Reserve `rescue` for system boundaries; prefer `catch :exit` for processes you don't own.
5. **ALWAYS `with` for 2+ ok/error chains.** Single operation → `case`.
6. **NEVER imperative loops.** Use `Enum.*`, `for` comprehensions, or tail recursion.
7. **NEVER rebind inside `Enum.each`** — use `Enum.map`/`Enum.reduce` to collect.
8. **ALWAYS data-first arguments** for pipe-ability. Return transformed data.
9. **NEVER pipe a single step.** `String.upcase(name)` not `name |> String.upcase()`.
10. **NEVER `|> case do` after a single step.** Only at end of a multi-step pipeline.
11. **ALWAYS pattern match in function heads** over `case` in the body for shape dispatch.
12. **ALWAYS use guards** to constrain function heads rather than body validation.
13. **ALWAYS IO lists** for string building in loops — never `<>` concatenation (O(n²)).
14. **ALWAYS `@spec` on public functions** + `@doc`/`@moduledoc`.
15. **ALWAYS pure functions for domain computation.** OTP callbacks orchestrate effects; computation lives in pure modules.
16. **ALWAYS supervise long-running processes.** Never bare `spawn`/`spawn_link`.
17. **ALWAYS narrowest OTP construct.** Pure fn → struct → Task → Agent → GenServer → gen_statem.
18. **ALWAYS go through context modules.** No direct `Repo` calls from controllers/LiveViews/CLI.
19. **ALWAYS `@impl true`** on behaviour callbacks.
20. **ALWAYS `%{struct | key: val}`** not `Map.put` for struct updates.
21. **ALWAYS latest stable deps** with recommended `mix.exs` setup.
22. **ALWAYS `mix format` + `mix credo --strict` + test suite** before declaring done.
23. **ALWAYS bare `with` (no `else`)** — add `else` ONLY to translate error shapes. Use tagged-tuple `with` when steps share error shapes. 2-4 steps healthy, 7+ split into phases. See [critical-patterns.md](critical-patterns.md) §5.10.
24. **ALWAYS distinguish short-circuit (`with`) from accumulating validation.** Independent validations → reduce-accumulate, not `with`. See [critical-patterns.md](critical-patterns.md) §5.10.6.
25. **ALWAYS pass capabilities as arguments** (clock, random, config) — never read inside building-blocks.
26. **ALWAYS subject-first arguments.** `def discount(price, rate)` not `def discount(rate, price)`. Opts last.
27. **PREFER `update_in`/`put_in`/`get_in`** over nested `Map.update` chains (2+ levels).
28. **ALWAYS check SSOT** before introducing magic literals — grep config/runtime.exs first.
29. **NEVER bare `:erlang.binary_to_term` on untrusted input.** Use `Plug.Crypto.non_executable_binary_to_term/2`.
30. **NEVER `Code.eval_string` on runtime data.** Use a bounded command registry.
31. **NEVER `apply(mod, fun, args)` with externally-tainted `mod`/`fun`.** Config-sourced is fine.
32. **ALWAYS propagate `Logger.metadata` across async boundaries.**
33. **ALWAYS `@derive {Inspect, only: [...]}`** on structs with secret fields.
34. **NEVER `__STACKTRACE__` in response bodies.** Drain to Logger; return sanitized errors.
35. **NEVER `IO.inspect`/`dbg` in `lib/`.** Use `Logger.*` with structured metadata.
36. **ALWAYS plan event/command schema evolution** from day one (`:version` field or Commanded Upcaster).

---

## 2. Master "Which Construct?" Decision Guide

This is the single most important section to consult at the moment of writing. Each row maps an **intent** (what you're trying to do) to the idiomatic construct and the common anti-pattern to avoid. Read left-to-right when you're about to type code: "I need to X" → use Y, not Z.

### 2.1 Control flow

| When you need to... | Use this | NOT this |
|---|---|---|
| Branch on the *shape* of data (struct type, tuple tag, map keys) | Multi-clause function with pattern in head | `if is_struct(x, Mod)` / `case ... do` |
| Branch on **membership** in a compile-time list/set | Multi-clause with `when x in @list` guard + catch-all | `if x in @list, do: yes(), else: no()` |
| Branch on a **computed value** (size, length, type check) | Multi-clause with guard on the computation | `case byte_size(v) do n when ... -> ... end` |
| Chain 2+ `{:ok, _}` / `{:error, _}` operations | `with ... do ... else ... end` | Nested `case`, nested `if` |
| Handle a single ok/error result | `case ... do` | `with` with one clause, `if` |
| Boolean side-effect, no value returned | `if cond, do: side_effect()` | `case bool do true -> ...; false -> ... end` |
| Boolean branch, both paths return values | `case bool do true -> ...; false -> ... end` | `if/else` (truthy, not strict) |
| Multiple boolean conditions (else-if chain) | `cond do ... end` | Nested `if/else` |
| Dispatch on value range / thresholds | `cond do` or multi-clause with guards | `if a < x, do: ...; if x < b, do: ...` |
| Early-exit from a reducer | `Enum.reduce_while/3` with `{:cont, acc}` / `{:halt, acc}` | `Enum.reduce` with `throw`/`catch` |
| Lookup-then-act with fallback | Multi-clause function or `case Map.fetch/2` | `map[:key] != nil` check |
| Check for `nil` | Multi-clause on the value, or `case` on `Map.fetch/2` | `if x == nil` / `if is_nil(x)` |
| Dispatch on one field of a large struct | Pattern-match just that field, or guard `struct.field` | Destructure whole struct in head |
| Execute a block conditionally in a pipeline | `then(&if/1)` or a `maybe_X/N` helper | Break the pipeline with `case` |
| Exit early on first error in a pipeline | `with` chain | `Enum.reduce_while` + `case` on result |

### 2.2 Collection operations

| When you need to... | Use this | NOT this |
|---|---|---|
| Transform each element | `Enum.map/2` with function capture `&fun/1` | `Enum.map(xs, fn x -> fun(x) end)` |
| Filter a list by predicate | `Enum.filter/2` | `Enum.reduce` that conditionally conses |
| Filter AND transform in one pass | `for x <- xs, pred.(x), do: transform(x)` | `xs \|> Enum.filter(pred) \|> Enum.map(t)` |
| Reduce to single value | `Enum.reduce/3` | manual recursion |
| Build a map from an enumerable | `Map.new/2` or `for x <- xs, into: %{}, do: {k, v}` | `Enum.reduce(xs, %{}, fn ... end)` |
| Build a MapSet | `MapSet.new/1,2` or `for ..., into: MapSet.new()` | `Enum.reduce` into a list then dedupe |
| Build a concatenated binary | IO list + `IO.iodata_to_binary/1`, or `Enum.map_join/3` | `Enum.reduce(..., "", &<>/2)` — O(n²) |
| Early-exit accumulation | `Enum.reduce_while/3` | `throw`/`catch`, flag variable |
| Iterate with index | `Enum.with_index/1,2` | `for i <- 0..length(xs)-1` |
| Process items in parallel (side effects) | `Task.async_stream/3,5` with `ordered: false` | `Enum.map(&Task.async/1) \|> Enum.map(&Task.await/1)` |
| Dedupe by key | `Enum.uniq_by/2` | `MapSet` + manual loop |
| Partition by predicate | `Enum.split_with/2` | Two `Enum.filter` passes |
| Group by derived key | `Enum.group_by/2,3` | `Enum.reduce` into `Map.update` |
| Chunk into batches | `Enum.chunk_every/2,4` | manual recursion |
| Count by frequency | `Enum.frequencies/1` / `Enum.frequencies_by/2` | `Enum.group_by` + `map_size` per bucket |
| Process large/infinite data lazily | `Stream.*` + one `Enum.*` at the end | `Enum.*` on full collection |
| Pattern-match while iterating (silent skip on mismatch) | `for {:ok, v} <- results, do: v` | `Enum.filter(...) \|> Enum.map(...)` |

### 2.3 Pattern matching and dispatch

| When you need to... | Use this | NOT this |
|---|---|---|
| Extract a field from a struct | Pattern match: `def f(%User{name: name} = u)` | `u.name` (fine for access, not for asserting presence) |
| Assert a map key exists | Match: `%{key: v} = map` or in head | `Map.get(map, :key) \|\| raise` |
| Match against an existing variable | Pin: `case x do ^expected -> ...` | Bare name (rebinds!) |
| Check non-empty list | `match?([_ \| _], xs)` or pattern in head | `length(xs) > 0` (O(n)) |
| Check empty map | `map == %{}` or `map_size(map) == 0` | `%{} = map` (matches ANY map) |
| Match JSON / params (string keys) | `%{"key" => v} = params` | `%{key: v}` — atom ≠ string |
| Match internal data (atom keys) | `%{key: v} = internal_map` | `%{"key" => v}` |
| Constrain by type / range in a head | Guard clause: `when is_integer(n) and n > 0` | Body `if` + validation |
| Match against a `0` or `nil` base case | Separate clause: `def f(0)`, `def f(nil)` | Body `if x == 0` |

### 2.4 Error handling

| Situation | Use |
|---|---|
| Can you check the condition BEFORE the call? | Check first (`Process.whereis/1`, `Map.fetch/2`) |
| Calling a process you don't own? | `try ... catch :exit, _` at the boundary |
| Input from untrusted / external source? | `rescue` specific exception at the boundary (e.g. `:erlang.binary_to_term` on network bytes) |
| Error is an expected business case? | Return `{:ok, _}` / `{:error, _}` from the function |
| Everything else? | Let it crash — the supervisor handles it |

| When you need to... | Use this | NOT this |
|---|---|---|
| Return success + data | `{:ok, value}` | `value` (can't distinguish from nil / :ok) |
| Return failure with a reason | `{:error, reason}` (atom or struct) | `nil`, raise, boolean false |
| Side-effect success (no data) | `:ok` | `{:ok, nil}` |
| Fail-fast on wrong input in a script | Bang variant (`File.read!/1`) | `case` + raise |
| Offer both strict and lenient API | Pair: `fetch/1` (ok/error) + `fetch!/1` (raises) | Only bang, or only non-bang |
| Wrap an external library that raises | `try/rescue` at the adapter boundary, convert to ok/error | Let exceptions leak out of your context |
| Propagate unknown errors | Let them crash; supervisor restarts | Catch-all `rescue _` |
| Decode an ETF payload from another node or signed cookie | `Plug.Crypto.non_executable_binary_to_term(payload, [:safe])` | Bare `:erlang.binary_to_term/1` (RCE class on attacker bytes) |
| Decode a payload from outside the cluster (HTTP body, broker, upload) | JSON / Protobuf / explicit format + `MyDTO.new/1` | Any form of `:erlang.binary_to_term` |
| Dispatch on a string command from external input | `Map.fetch(@commands, name)` against a compile-time registry | `apply(String.to_existing_atom(name), :run, args)` / `Code.eval_*` |
| Need to invoke a function whose name is config-supplied | `apply(mod, fun, args)` is fine when `mod`/`fun` came from `init/1`-validated config (Plug pattern) | Same `apply` shape with `mod`/`fun` reaching from request params or channel messages |
| Chain 2+ ok/error operations | Bare `with` (railway, no `else`) | Nested `case`, `if` |
| Translate error shapes for callers | `with` + targeted `else` clauses | `else` that handles success values |
| Distinguish which step failed when shapes overlap | Tagged-tuple `with` (`{:fetch, {:ok, x}} <- {:fetch, fn()}`) | Catch-all error and reverse-engineer the cause |
| Validate independent fields, accumulate errors | Reduce that collects errors into a list | `with` (short-circuits — wrong UX for forms) |
| Transform success value, leave error untouched | `with {:ok, v} <- f(), do: {:ok, transform.(v)}` | `case ... do {:ok, v} -> {:ok, transform.(v)}; e -> e end` |
| Communicate "this should happen" without doing it | Return events list `{:ok, value, [events]}` | Inline `Logger`/`Repo`/`PubSub` from a building-block |

### 2.5 Strings and binaries

| When you need to... | Use this | NOT this |
|---|---|---|
| Build a string from parts | Interpolation `"#{a} and #{b}"` | `a <> " and " <> b` |
| Build a string in a loop | IO list + `IO.iodata_to_binary/1` | `Enum.reduce(xs, "", &<>/2)` |
| Join list into string with separator | `Enum.join(xs, ", ")` or `Enum.map_join/3` | `Enum.reduce` with `<>` |
| Parse a known binary layout | Binary pattern matching `<<a::8, b::16, rest::binary>>` | `String.split` on byte boundaries |
| Parse a known-shape header / fixed prefix | Binary pattern matching: `<<"Bearer ", token::binary>>` | `Regex.run(~r/Bearer\s+(.+)/, header)` |
| Split on a single-character delimiter | `String.split(value, ":", parts: 2)` | `Regex.run(~r/^([^:]+):(.+)$/, value)` |
| Parse a real grammar (TLS handshake, DSL, query language) | `NimbleParsec` parser combinator | A regex chain |
| Convert integer to string | `Integer.to_string/1,2` | `"#{n}"` (allocates, slower) |
| Convert to atom from user input | `String.to_existing_atom/1` | `String.to_atom/1` (exhausts atom table) |
| Coerce unknown-type value for display | `inspect/1` | `to_string/1` (raises for some types) |
| Compare case-insensitively | `String.downcase/1` both sides | manual `String.equivalent?` check |

### 2.6 Data updates

| When you need to... | Use this | NOT this |
|---|---|---|
| Update an existing struct field | `%{struct \| field: value}` | `Map.put(struct, :field, value)` |
| Update an existing map key (known present) | `%{map \| key: value}` | `Map.put(map, :key, value)` |
| Set / create a map key (maybe absent) | `Map.put(map, key, value)` | `%{map \| key: value}` (raises if absent) |
| Update a nested field | `put_in(data, [path], value)` or `update_in/3` | Manual get-modify-put chain |
| Increment a counter in a map | `Map.update(map, :k, 1, & &1 + 1)` | Get + 1 + Put |
| Merge two maps (right wins) | `Map.merge/2` | `Enum.reduce(other, map, & Map.put(&2, ...))` |
| Merge with custom conflict resolution | `Map.merge/3` | Manual reduce |
| Delete a key | `Map.delete/2` | `Map.drop(map, [key])` for one key |
| Check key presence (nil is a valid value) | `Map.has_key?/2` or `Map.fetch/2` | `map[:key] != nil` |

### 2.7 Function design

| When you need to... | Use this | NOT this |
|---|---|---|
| Expose a function unchanged from another module | `defdelegate name(args), to: Other` | `def name(args), do: Other.name(args)` |
| Accept optional config | Keyword list last arg + `Keyword.validate!/2` | Multiple overloads with many args |
| Provide a default for an arg | `def f(x, opts \\ [])` | Multiple clauses setting defaults |
| Return transformed data in a pipeline | First arg = data, return new data | Mutation-style (non-existent in Elixir) |
| Chain mutation-like configuration | Return the subject: `mock \|> expect(...) \|> allow(...)` | Separate `config_X` / `config_Y` calls |
| Implement a callback from a behaviour | Mark with `@impl true` above the function | Bare `def` (loses compile-time check) |
| Disambiguate multiple behaviours | `@impl SomeBehaviour` | `@impl true` when ambiguous |

### 2.8 Module boundaries

| When you need to... | Use this | NOT this |
|---|---|---|
| Expose domain API from a context | `def` with `@doc` + `@spec` | Thin wrappers that forward to internal modules unchanged |
| Hide an internal helper | `defp` | `def` + `@doc false` (still callable) |
| Swap implementations (test/prod) | `@callback` behaviour + `Application.compile_env` | `if Mix.env() == :test` |
| Provide data-level polymorphism | Protocol (`defprotocol` + `defimpl`) | Giant `case` on struct type |
| Reuse a default implementation | `use Module` with `defoverridable` | Copy-paste |
| Share constants across modules | Module with `defmacro` or `def` returning value | Global mutable state |

### 2.9 Process and concurrency

| When you need to... | Use this | NOT this |
|---|---|---|
| Fire-and-forget async side effect | `Task.Supervisor.start_child/2` | `spawn/1` (unsupervised) |
| Await parallel results | `Task.async_stream/3,5` | Manual `Task.async` + `Task.await` list |
| Long-running stateful worker | GenServer | Infinite-loop `spawn` |
| Shared read-heavy state (no single writer bottleneck) | ETS (`:public`, `read_concurrency: true`) | GenServer.call for every read |
| Cross-process counter | `:counters` / `:atomics` | GenServer.call for `+1` |
| Rarely-changing global config | `:persistent_term` | `Application.get_env` on hot path |
| Serialize access to an external resource | GenServer (one writer) | Multiple processes racing to the resource |
| Explicit state machine with transitions | `:gen_statem` | GenServer with large `case` on state |
| Supervise dynamically created workers | DynamicSupervisor + Registry | Named GenServers per entity |
| Scheduled / periodic work | `Process.send_after` loop, or Oban for persistence | `:timer.sleep` in a loop |
| Pub/sub within a node | Registry with `:duplicate` keys, or `Phoenix.PubSub` | `Process.send` to a list of pids you maintain |
| Backpressured pipeline | GenStage / Broadway | Manual message passing |
| Optional call to a maybe-missing process | `GenServer.whereis/1` + `try ... catch :exit` | `GenServer.call` without guard |

### 2.10 Pipelines

| When you need to... | Use this | NOT this |
|---|---|---|
| Apply 2+ transformations | Pipeline: `data \|> step1() \|> step2()` | `step2(step1(data))` (less readable for chains) |
| Apply exactly 1 function | Direct call: `String.upcase(name)` | `name \|> String.upcase()` |
| Branch at the end of a pipeline (multi-step) | Pipe into `case`: `... \|> case do ...` | Assign to var, then `case` |
| Branch after a single call | Assign to `result`, then `case` | `single_call() \|> case do` (single-step pipe) |
| Optionally apply a step | `maybe_X/2` helper: multi-clause with `true`/`false` arg | `if` inside the pipeline |
| Inspect without changing value | `tap(&IO.inspect/1)` | Assign to var, inspect, reuse |
| Transform for a single non-pipable step | `then/2`: `data \|> then(&some_fn.(&1, extra))` | Break pipeline, assign, call, re-enter |
| Log / emit telemetry mid-pipeline | `tap(&Logger.info/1)` | Pipeline break |
| Define a public function so callers can pipe into it | First arg = data; opts last (`def f(data, opts \\ [])`) | First arg = opts; data later (breaks every pipeline) |
| Compose deep nested updates | `update_in(struct.a.b.c, &fn/1)` / `put_in/2` | Nested `Map.update` lambdas (>2 levels) |

### 2.11 Testing

| When you need to... | Use this | NOT this |
|---|---|---|
| Test a pure function | ExUnit `test` with input → expected output | Setup `start_supervised!` when not needed |
| Test the happy path | `assert {:ok, value} = function(...)` | `assert function(...) == {:ok, ...}` (worse failure messages) |
| Test an error case | `assert {:error, _} = function(bad)` | `assert_raise` unless the function really raises |
| Test a changeset error | `errors_on/1` helper: `%{field: ["msg"]} = errors_on(cs)` | Dig into `cs.errors` manually |
| Mock an external service | Define `@callback` → `Mox.defmock` → `expect` | Monkey-patch module, redefine at runtime |
| Isolate DB writes per test | `Ecto.Adapters.SQL.Sandbox` with `async: true` | Truncate tables between tests |
| Test a GenServer | Test the client API (`MyServer.call/1`) against a `start_supervised!` instance | Call `handle_call` directly |
| Wait for an async message | `assert_receive pattern, 500` | `Process.sleep(500) && assert ...` |
| Use fresh data per test | Factory (`insert(:user)`) | Fixture module with shared instances |
| Property test invariants | `StreamData` with `check all` | Hand-generate edge cases |
| Assert function shouldn't be called | `refute_called` equivalent: `Mox.expect` N=0 | Omit and hope |

---

## 6. Idiomatic Elixir Constructs

> **Depth:** [idioms-reference.md](idioms-reference.md) has full syntax reference + examples for every construct below. This section is an index — load the subskill for templates.

| Construct | When | Depth |
|---|---|---|
| `if` / `unless` | Boolean guard with side effect, no else value | idioms §`case`/`cond`/`if` |
| `case` | Dispatch on one value's shape; can pipe into at end of multi-step pipeline | idioms §`case`/`cond`/`if` |
| `cond` | Multiple independent booleans, no single subject | idioms §`case`/`cond`/`if` |
| `with` | Chain 2+ ok/error steps — BUT note `with ... else` breaks LCO | idioms §`with` Chains |
| Multi-clause function | Dispatch on argument shape/type | idioms §Pattern Matching in Function Heads |
| Guards | Constrain function head; custom via `defguard` | idioms §Guards |
| `Enum` | Bounded collection transformations — see function reference | idioms §`Enum` |
| `Stream` | Lazy / I/O-sourced / infinite / stop-early | idioms §`Stream` |
| `for` comprehension | Filter + transform in one pass; `into:`, `reduce:`, `uniq:`, binary | idioms §`for` Comprehensions |
| `&` capture | Function reference when arity matches | idioms §Captures |
| Recursion | Long-running loops, trees, binary decoders, state machines | idioms §Recursion |
| Protocols | Dispatch on data type | idioms §Protocols |
| Behaviours | Dispatch on module identity (swap at config time) | idioms §Behaviours |

### Three templates worth keeping inline

**Piping into `case` (end of multi-step pipeline only):**

```elixir
resource
|> lookup_transitions(action_name)
|> Enum.find(&match_transition?(&1, state, target))
|> case do
  nil -> {:error, :no_matching_transition}
  t -> {:ok, apply_transition(t)}
end
```

**`cond` with binding in condition (priority resolution):**

```elixir
cond do
  val = Map.get(overrides, key) -> val
  val = Map.get(config, key) -> val
  true -> default
end
```

**Keyword options + validation:**

```elixir
def start_link(opts) do
  opts = Keyword.validate!(opts, [name: __MODULE__, timeout: 5_000, retries: 3])
  GenServer.start_link(__MODULE__, opts, name: opts[:name])
end
```

---

## 11. Domain Handoffs

Load these skills *in addition* to this one when entering their domain:

| Trigger | Skill |
|---|---|
| Phoenix controllers, routers, plugs, forms | `phoenix` |
| LiveView mount/handle_event, streams, uploads | `phoenix-liveview` |
| Ash resources, actions, policies | `ash` |
| Nerves firmware, VintageNet, GPIO | `nerves` |
| Rustler NIFs | `rust-nif` |
| State machines | `state-machine` |
| Event sourcing / Commanded | `event-sourcing` |
| Deep testing (property-based, ExVCR, Wallaby) | `elixir-testing` |
| GenStage, Broadway, hot upgrades | `otp` |
| Desktop apps | `elixir-desktop` |
| Membrane streaming | `membrane` |
| Code generation / Igniter | `igniter` |
| Deployment (releases, Docker, K8s) | `elixir-deployment` |
| Livebook notebooks | `livebook` |
| Multi-node / AtomVM | `erpc` |
| TCP/UDP, protocol framing | `elixir` skill's `networking.md` |
| Ecto deep (CTEs, custom types, multi-tenancy) | `elixir` skill's `ecto-*.md` |

---

## 12. Quick References

> **Depth:** [stdlib-cheatsheet.md](stdlib-cheatsheet.md) — signatures for `Enum`, `Map`, `Keyword`, `List`, `String`, `File`/`Path`, `Regex`, `Date`/`Time`, `Process`, Erlang picks, `JSON`/`Jason`, `URI`/`Base`, `Access`, `Logger`, child specs. For the full stdlib reference, load the `elixir` skill's `quick-references.md`.

---

## 13. Related Skills

| Skill | Focus |
|---|---|
| `elixir-planning` | Architecture: contexts, supervision, layout, data ownership |
| `elixir-reviewing` | Review checklist, anti-pattern catalog, idiomatic audits |
| `elixir` | Comprehensive reference (deep topic dives beyond this skill) |
| `elixir-testing` | Deep testing: property-based, ExVCR, Wallaby, channel/LiveView |
| `phoenix` | Controllers, plugs, forms, router, channels, PubSub |
| `phoenix-liveview` | Lifecycle, components, streams, uploads, hooks, async |
| `ash` | Declarative resources, policies, actions, extensions |
| `state-machine` | `gen_statem`, `GenStateMachine`, AshStateMachine |
| `event-sourcing` | Commanded, aggregates, projections, process managers |
| `otp` | GenStage, Broadway, hot upgrades, distribution |
| `nerves` | Embedded Elixir firmware |
| `rust-nif` | Rustler NIFs |
| `igniter` | Code generation and project patching |
| `elixir-deployment` | Mix releases, Docker, Kubernetes, observability |

---

## 14. Before You Commit — 60-Second Self-Review

Grep your diff for these top recurring issues:

1. **`rescue` without `__STACKTRACE__`?** Use `Exception.format(:error, e, __STACKTRACE__)`.
2. **`File.read!` in `lib/`?** Use `File.read/1` + ok/error match. Reserve `!` for scripts/seeds.
3. **Pattern match assuming 3-tuple?** Add a fallback clause — not all values are 3-tuples.
4. **Overbroad predicate?** Narrow to the specific call site, not variable name substrings.
5. **Public function without `@spec`?** Every `def` needs `@spec`. `@doc false` internals exempt.
6. **Context boundary crossing?** Should the call go through the context's facade?
7. **Unsupervised process?** Any `spawn`/`Task.async` without a supervisor.
8. **Simplest inter-context mechanism?** Direct call > PubSub > GenStage > Oban > event sourcing.
9. **Every new `def` in `lib/` has a test?** Name the test file and function.
10. **Test asserts behavior, not implementation?** `assert {:ok, %User{}} = register(attrs)` not `assert Repo.insert was called`.

---

**End of SKILL.md.** Decision tables first, templates second, BAD/GOOD as validators. Load `elixir-planning` for design, `elixir-reviewing` for review, subskills for depth.
