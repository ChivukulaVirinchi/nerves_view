# Review Checklists — What to Flag

> **Depth file for [SKILL.md](SKILL.md).** Load when reviewing a PR / diff systematically by area.

> For the consolidated catalog of named anti-patterns organized by category (code / process / Ecto / architecture / testing / security / config), each with a BAD/GOOD pair — load [anti-patterns-catalog.md](anti-patterns-catalog.md). Use that when you spot something "off" and want to name it; use this file when you want to scan a diff systematically by area.

Each subsection is a scanning checklist. Read left to right: "if you see this" → "flag it because" → "suggest this" → "severity". Links to the owning skill sections explain *why* for the author.

---

## 7.1 Architectural review

Full reference: `elixir-planning` §14. Flag these if you see them in a diff.

| If you see... | Suggest instead | Severity | Why — see |
|---|---|---|---|
| Directories like `lib/my_app/models/`, `services/`, `helpers/` | Contexts (`lib/my_app/accounts.ex` + `lib/my_app/accounts/*.ex`) | Block | planning §14.1 |
| Domain module aliasing `MyAppWeb.*`, `Phoenix.*`, `Routes.*` | Keep domain framework-agnostic; move URL generation to interface layer | Block | planning §14.2 |
| Controller / LiveView / CLI calling `Repo.X` directly | Call the owning context's public API | Block | planning §14.3 |
| Business logic in a controller action, LiveView handler, or CLI handler | Move to a context function; interface translates + delegates + formats | Block | planning §14.3 |
| `Plug.Router` route block calls another Plug module's `call/2` directly with raw opts (e.g. `get "/", do: Handler.call(conn, [])`) | Pre-initialize at compile time: `@handler_opts Handler.init([])` and `get "/", do: Handler.call(conn, @handler_opts)`. Bypassing `init/1` drops opt normalization — a latent trap that breaks silently the moment `init/1` stops being a no-op | Block | implementing production-patterns §Plug.Router dispatch |
| Two contexts writing to the same table | One owns it; the other reads through owner's API or uses PubSub | Block | planning §14.11 |
| `Repo.preload(:other_context_association)` across contexts | Ask the owning context for assembled data | Request-change | planning §14.12 |
| One context's internal module called from another context | Go through the owning context's public API | Request-change | planning §6.4 |
| `defdelegate` pass-through in a context | Fine if pure pass-through; flag if the context should add telemetry/logging | Nitpick | planning §6.7 |
| Business logic in a GenServer `handle_call` | Extract to pure module; GenServer delegates | Request-change | planning §14.6 |
| Feature being added to a growing "god context" | Does it belong? Consider split criteria | Suggest | planning §6.2 |
| Introducing an umbrella split for "it feels big" | Keep single-app; add contexts | Request-change | planning §14.7 |
| Adding a new inter-context call via PubSub before trying direct function calls | Can direct calls work? Escalate only when justified | Suggest | planning §9.9 |
| Adding Oban / GenStage / event sourcing without a triggering problem | Use the simplest mechanism; escalate only when needed | Request-change | planning §9.9 |
| Missing `@moduledoc` on a public module | Add `@moduledoc` or explicit `@moduledoc false` | Request-change | implementing §8.5 |
| Missing `@spec` on a new public function | Add `@spec` | Request-change | implementing §6.10 |
| `@impl true` implementation with no explicit `@spec` | Add `@spec` on the implementation too — `@impl` links to the behaviour spec but doesn't substitute | Suggest | implementing type-and-docs rule 1 |
| Behaviour callback overloaded with a "reflection" atom (e.g. `execute(:list_instructions, a, b)`) | Give reflection its own callback (`instructions/0`, `describe/0`) | Request-change | planning §4.9 |
| Union type variant with `{:tag, nil}` payload sentinel | Use bare atom: `:tag` — don't carry a nil payload | Nitpick | implementing type-and-docs §Union types |
| Public `@spec` uses a loose type (`atom()`, `map()`, `[term()]`) where a named `@type` is already defined in scope | Reuse the named alias: `MyMod.instruction()`, `MyMod.t()`, `[MyMod.entry()]` | Suggest | implementing type-and-docs rule 7 |
| `@moduledoc` / `@doc` asserts a behaviour (binds to both X and Y, rejects Z, accepts ranges A..B) not exercised by a test | Add a test that pins the claim, OR update the doc to match the code. Stale docs mislead worse than missing docs do | Request-change | implementing type-and-docs rule 13 |
| Two moduledocs that describe the same subsystem disagree (e.g., `App.Application` says "binds IPv4 only" while `Plugs.RequireLoopback` says "binds IPv4 + IPv6") | Reconcile both moduledocs against the code as one atomic change. Cross-file contradictions are Rule 13 distributed — harder to spot, same defect | Block | implementing type-and-docs rule 14 |
| Plug's `init/1` / `call/2` uses `Plug.opts()` when the plug actually accepts specific keys | Define a narrow `@type opts :: [...]` and use it in both specs | Suggest | implementing type-and-docs §Plug signature |
| New feature is a library candidate but uses `Application.compile_env` | For library code, use runtime `get_env` or config-via-args | Block (if library) | planning §10.3 |
| Public context function's moduledoc claims atomicity ("both X and Y, or neither") across a DB write AND a non-DB side effect (process-registration, PubSub broadcast, external API call), but the code just does them sequentially and doesn't roll back | Wrap both in `Ecto.Multi.run/3` so the DB row rolls back on side-effect failure, OR remove the atomicity claim and document the recoverable orphan state. Either way: the moduledoc must match the code — this is Rule 13 applied to a specific anti-pattern | Request-change | implementing type-and-docs rule 13 |
| Moduledoc references a future milestone ("M9 will add Broadway" / "in M12 this becomes atomic") after that milestone has already merged | Rewrite the claim in the present tense describing current behaviour. Milestone-references belong in commit messages and a plan doc, not in each module's `@moduledoc` where they silently decay into lies | Suggest during a rollout; Request-change three milestones after the referenced one merged | implementing type-and-docs rule 13 |
| LiveView `handle_info` handler for a PubSub message reloads the whole collection from the DB to derive a counter / display state that could be updated from the message content + existing assigns | Change the **broadcast payload** to carry everything the subscriber needs (e.g., `{:device_state_changed, id, old, new}` not `{:device_state_changed, id, new}`) so the LV can update assigns in O(1) instead of re-querying. Never pay N queries per message | Request-change | phoenix-liveview rule 2 + implementing production-patterns |
| LiveView stream with a row template that reads from a **separate** assign (`@device_states`, `@cluster_status`, `@presence`), and a `handle_info` that changes that sidecar assign to update the row | Stream row DOM is only re-emitted on `stream_insert/3,4` — the sidecar change does NOT redraw the row. Move the state onto the stream member (virtual schema field, `list_with_state/1` context fn) and re-insert on every change. This is architectural: may require a schema change. See implementing §5.9, planning §14.14 | Block | phoenix-liveview + implementing §5.9 |
| `Repo.insert_all(schema_or_"table", rows)` where a row field is the high-level form of a type that needs dumping: `Ecto.UUID.generate/0` → 36-char hex instead of 16-byte binary; atom for `Ecto.Enum` column; raw `DateTime` for `:utc_datetime_usec` without truncation; custom `Ecto.Type` without `dump/1` | `insert_all` bypasses casts by design. Pass the raw DB representation: `Ecto.UUID.bingenerate/0`, `Atom.to_string/1` for enum columns, `DateTime.truncate(dt, :microsecond)`, `MyType.dump!(value)`. Or use the schema-module form (`Repo.insert_all(Schema, rows)`) so Ecto dumps known fields | Block (silent Postgrex encode errors at runtime) | implementing §10.6.1 |
| `from b in "string_source", ...` (schemaless query) selecting a `:utc_datetime*` column, and downstream code treats the result as `DateTime.t()` | String-source queries return `NaiveDateTime` (no schema metadata to lift to UTC). Either use a schema-bound query, or normalize at the context boundary: `DateTime.from_naive!(n, "Etc/UTC")`. Downstream `DateTime.diff/3` etc. will crash on `NaiveDateTime` | Request-change | implementing §10.6.2 |
| GenServer with boot-time subscription via `:net_kernel.monitor_nodes/1,2`, `Phoenix.Tracker`, `Phoenix.PubSub.subscribe/2`, or `Process.monitor/1` against a long-lived target, **without** replaying current state in `handle_continue/2` | Subscriptions only deliver future events. Existing peers / rows / children are invisible. Use `{:ok, state, {:continue, {:retro_scan, Node.list()}}}` and fire the same handler. Pattern applies across `:net_kernel.monitor_nodes`, `Process.monitor` on DynamicSupervisor children, `Phoenix.Presence` on an already-populated topic | Request-change if the GenServer drives business logic from these events; Suggest if telemetry-only | debugging-playbook.md §8.9 retro-scan template |
| Event or command struct (under `Events`/`Commands` namespace, `defimpl Commanded.Event.Handler`, or persisted via Oban / EventStore) without a `:version`/`:schema_version`/`:event_version` field, no `@version` attribute, AND no `defimpl Commanded.Event.Upcaster` for the type | Pick ONE convention per project: inline `:version` field (small projects) OR `defimpl Commanded.Event.Upcaster, for: MyEvent` (Commanded idiom — one module per event type, upcaster transforms older persisted shapes). The "module-per-version" pattern (`V1.OrderPlaced` / `V2.OrderPlaced` separate modules) is NOT what Commanded recommends. See `elixir-implementing` §5.16. | Request-change | implementing §5.16, §1 #36 |
| Event/command split into separate `V1.<Name>` / `V2.<Name>` modules with an upcaster bridging them | Consolidate into a single event module per type; let `defimpl Commanded.Event.Upcaster, for: <Name>` fill in defaults for the missing fields when older persisted shapes are read. The single-module shape is what Commanded's docs prescribe — quoted from `Commanded.Event.Upcaster`: "Upcaster changes any historical event to the latest version, consumers... only need to support the latest version." | Suggest (refactor toward Commanded idiom) | implementing §5.16 |

---

## 7.2 Control flow review

Full reference: `elixir-implementing` §7.1. Flag these patterns when you see them.

| If you see... | Suggest instead | Severity |
|---|---|---|
| `if is_map(x) and Map.has_key?(x, :type)` or similar shape-discriminating `if` | Multi-clause function with pattern matching | Request-change |
| `if opts[:flag] do ... else ... end` with value-returning branches | `case Keyword.get(opts, :flag, false) do true -> ...; false -> ... end` | Suggest |
| Nested `case` (2+ levels) on ok/error results | `with` chain | Request-change |
| `with` containing a single clause | Plain `case` | Nitpick |
| `if user != nil do ... if user.name != nil ...` (nil-check cascades) | Multi-clause on shape: `def greet(%{name: name}) when is_binary(name), do: ...; def greet(nil), do: ...` | Request-change |
| `cond` without a `true -> default` branch | Add explicit default; otherwise `CondClauseError` on fall-through | Block |
| `case x do 1 -> :one; 1.0 -> :one_float end` | Use guards (`n == 1`) — integer literal ≠ float literal | Request-change |
| `case` where every branch returns an error-shape (identity case) | Replace with direct return | Suggest |
| `unless x, do: a(), else: b()` | Invert: `if x, do: b(), else: a()` | Nitpick |

---

## 7.3 Pipelines review

Full reference: `elixir-implementing` §5.1, §7.2.

| If you see... | Suggest instead | Severity |
|---|---|---|
| `name \|> String.upcase()` (single-step pipe) | Direct call: `String.upcase(name)` | Request-change |
| Multiple `\|>` on one line: `list \|> Enum.map(f) \|> Enum.sum()` | One pipe per line | Nitpick |
| `data \|> (fn x -> ... end).()` | `data \|> then(&(...))` | Request-change |
| `Enum.reduce_while(...) \|> case do ... end` (single-step pipe into case) | Assign to `result`, then `case result do` | Request-change |
| Piping a literal list: `["a", "b", "c"] \|> Enum.map(&...)` | Direct call: `Enum.map(["a","b","c"], ...)` | Suggest |
| Pipe chain of 5+ steps without intermediate names | Consider extracting the middle into a named helper | Suggest |
| `if cond, do: func(data), else: data` inside a pipeline flow | `maybe_X/2` multi-clause helper or `then(&if/1)` | Suggest |

---

## 7.4 Collections / iteration review

Full reference: `elixir-implementing` §6.4-§6.5, §7.3.

| If you see... | Suggest instead | Severity |
|---|---|---|
| `Enum.each(xs, fn x -> result = ... end)` then using `result` | `Enum.map` or `Enum.reduce` — `each` rebind doesn't escape | Block (correctness bug) |
| `length(list) > 0` or `length(list) == 0` (O(n)) | `list == []` / pattern match `[_ \| _]` / `[]` | Request-change |
| `Enum.filter(xs, pred) \|> Enum.map(f)` (two passes) | `for x <- xs, pred.(x), do: f.(x)` | Suggest |
| `Enum.reject(xs, pred) ++ Enum.filter(xs, pred)` (two filters for partition) | `Enum.split_with(xs, pred)` — one pass | Request-change |
| `Enum.reduce(xs, %{}, fn ... -> Map.put(...) end)` | `Map.new/2` or `for ..., into: %{}, do: ...` | Suggest |
| `Enum.map(xs, fn x -> Mod.fun(x) end)` (anon fn wrapping named fn) | `Enum.map(xs, &Mod.fun/1)` | Nitpick |
| Manual index tracking: `Enum.reduce(xs, {[], 0}, ...)` | `Enum.with_index/1,2` | Request-change |
| `Enum.reduce(xs, "", &(&2 <> &1))` (string concat in loop, O(n^2)) | IO list + `IO.iodata_to_binary/1`, or `Enum.map_join/3` | Block (performance) |
| `Enum.map/filter/etc.` on a large dataset or stream | `Stream.*` + terminal `Enum.*` | Suggest (performance) |
| `Enum.find` + `if` pattern | `Enum.find_value/2` or `Enum.find/2` with match | Suggest |
| `Enum.group_by(xs, &key/1) \|> Enum.(each\|map)(fn {k, group} -> f(k, length(group)) end)` (materializes per-key lists just to count them) | `Enum.frequencies_by(xs, &key/1) \|> Enum.each/map(...)` — one pass, integer counts, no intermediate list allocation | Request-change on hot paths; Suggest otherwise |

---

## 7.5 Error handling review

Full reference: `elixir-implementing` §7.4, §8.1-§8.2.

| If you see... | Suggest instead | Severity |
|---|---|---|
| `try do ... rescue ArgumentError -> ...` around `String.to_integer` / similar | Use `Integer.parse/1` / `Integer.parse/2` which returns ok/error | Request-change |
| `try do GenServer.call(...) rescue _ -> ...` (rescue around GenServer.call) | `catch :exit, _` — GenServer.call raises exits, not exceptions | Block |
| Non-bang function named `X` that `raise`s on error | Rename to `X!`, add a non-raising `X` returning ok/error | Request-change |
| `rescue _ -> nil` (swallow all errors) | Rescue specific exceptions; for truly unknown, let the supervisor restart | Block |
| `raise "..."` inside a non-bang public function | Return `{:error, reason}` | Request-change |
| Bang function with no non-bang counterpart in a library | Provide both where it makes sense | Suggest |
| `catch` for expected business failures | Return ok/error tuples | Request-change |
| Missing `{:error, reason}` shape documentation in `@spec` | Tighten the `@spec` with concrete error types | Request-change |
| Operation in Oban / webhook / event handler that's not idempotent | Make idempotent (see planning §7.3) | Block |
| Compound error reason squashing distinct failures (e.g. `{:out_of_range_or_wrong_type, v}`) | Split into distinct tags: `{:wrong_type, v}` + `{:out_of_range, v, range}` | Request-change |
| Public module mixes raise and `{:error, _}` for same failure class (e.g. `describe/1` raises but `execute/4` returns `{:error, _}`) | Pick one per boundary. Safe name returns ok/error; `!` variant raises | Request-change |
| `with` chain validates data inputs before dispatch key, forcing dummy data for reflection calls | Validate dispatch key first; reflection paths then bypass data validation | Suggest |
| `with` chain mixes sentinel-valued short-circuits (`:noop`, `:skip`) and `{:error, _}` tuples, with an `else` clause `:noop -> :noop; other -> other` passing everything else through untyped | Give `:noop` / `:skip` explicit `else` clauses separately from `{:error, _}=e -> e`, OR split into two functions: a "should-we-run" predicate on top, a `with` chain only for actual work. Current shape lets future `{:error, _}` returns leak unreviewed into callers | Suggest |

---

## 7.6 Process / OTP review

Full reference: `elixir-implementing` §9, `elixir-planning` §8.

| If you see... | Suggest instead | Severity |
|---|---|---|
| `spawn(...)` or `spawn_link(...)` for long-running work | Supervised Task (`Task.Supervisor.start_child/2`) or GenServer | Block |
| GenServer callback doing I/O (HTTP, DB, `Process.sleep`) | Offload to a Task; use `handle_continue/2` for init | Request-change |
| Business logic in `handle_call`/`handle_cast`/`handle_info` | Extract to pure module; callback delegates | Request-change |
| `GenServer.call(pid, :msg)` without explicit timeout | Pass `timeout` arg explicitly (default 5000ms is often wrong) | Request-change |
| `GenServer.call` to a variable pid without `catch :exit` | Wrap with `try ... catch :exit, _ -> {:error, :down}` — the process may die mid-call | Request-change |
| Hardcoded timeout literal like `GenServer.call(pid, msg, 30_000)` | Extract to `@default_X_timeout` module attribute | Suggest |
| Registry + DynamicSupervisor under `:one_for_one` | Dedicated `:one_for_all` sub-supervisor so both restart together when Registry dies | Block |
| GenServer with large state (> ~100KB) | Move large data to ETS / `:persistent_term` | Request-change |
| GenServer just wrapping a map (get/put) | Use ETS directly (no serialization bottleneck) | Suggest |
| Registry-registered process called as `GenServer.call(:name, msg)` | Use `{:via, Registry, {Reg, name}}` or helper `via/1` | Block |
| Unsupervised `Task.async(fn -> ... end) \|> Task.await/2` in a GenServer callback | `Task.Supervisor.async_nolink/3` + handle `:DOWN` | Request-change |
| Agent-per-entity (simulating objects) | Pure functional modules for thought concerns; processes only for runtime concerns | Request-change |
| Missing catch-all clause in `handle_info` | Add `def handle_info(msg, state) do Logger.warning(...); {:noreply, state} end` | Request-change |
| Missing `@impl` on behaviour callback | Add `@impl true` (or `@impl BehaviourModule`) | Request-change |
| Raw `%{}` / `Map.put` on a struct (silently accepts typos) | Struct update `%{struct \| field: val}` | Request-change |
| No `format_status/1` on GenServer holding secrets | Implement `format_status/1` to scrub tokens/passwords | Request-change |
| GenServer calls `:net_kernel.monitor_nodes(true)` in `init/1` without replaying `Node.list()` in `handle_continue/2` | Node connections that formed before this GenServer started are invisible — monitor_nodes only delivers future events. Retro-scan pattern: `{:ok, state, {:continue, {:retro_nodeup, Node.list()}}}` then fire the same handler. Same pattern applies to `Process.monitor/1` against a pre-existing DynamicSupervisor's children | Request-change if the GenServer drives business logic from nodeup; Suggest if audit-only |
| Synchronous call into another OTP app's API inside `init/1` (e.g. `:fuse.install/2`, shared `:ets.new/2`, `:persistent_term.put/2` for boot config) | Defer to `handle_continue/2`. Listing the dep in `extra_applications` gives a partial order within the current app but not across apps — a GenServer in app A doing `B.init_table/1` in its own `init/1` can race with app B's own boot | Request-change |
| Async closure (`Task.async`, `Task.Supervisor.start_child`, `Task.async_stream`, `Task.Supervisor.async_nolink`) calls `Logger.<level>` or `:telemetry.execute/3` inside the closure body, but does NOT call `Logger.metadata/0,1` to restore parent metadata (and does not receive an explicit context struct as an argument) | Capture parent metadata before the closure (`md = Logger.metadata()`), restore inside (`Logger.metadata(md)`); for cross-Oban / cross-node hops, pass an explicit `TraceContext` struct. See `elixir-implementing` §5.13 / §7.12 and `elixir-planning` §11.7. | Request-change |
| Oban worker's `perform/1` calls `Logger.<level>` or `:telemetry.execute/3` without `Logger.metadata/1` set first from the job's `args` | Worker hydrates metadata from args at the top of `perform/1`: `Logger.metadata(trace_id: args["trace_id"], order_id: args["order_id"])`. Producer side (the `Oban.insert/2` caller) writes the trace IDs into args from its own `Logger.metadata()`. | Request-change |
| `:telemetry.execute/3` from inside an async closure where the metadata map does NOT include `trace_id` (or the project's correlation key) | Add the correlation ID to the telemetry metadata explicitly. Telemetry handlers run in the *emitting* process; cross-process re-publish (e.g. to a remote sink) does not preserve the emitter's `Logger.metadata`. | Request-change |

---

## 7.7 Testing review

Full reference: `elixir-implementing` §3-§4.

| If you see... | Suggest instead | Severity |
|---|---|---|
| New public function without a test | Add tests — block until done | Block |
| Test using `Process.sleep` before asserting on async behavior | `assert_receive pattern, timeout` | Request-change |
| Test asserting a specific internal function was called | Test observable behavior, not call sequence | Request-change |
| `use MyApp.DataCase` with `async: false` for no clear reason | Use `async: true` — Ecto sandbox supports it | Suggest |
| Test calls `handle_call` directly | Test via the client API | Request-change |
| `Mox.stub` where `expect` is appropriate (must-be-called behavior) | Use `expect` — stub gives no verification | Request-change |
| Mocking a module the project owns (Accounts, Pricing) | Test directly; mock only system boundaries | Block |
| No `setup :verify_on_exit!` with Mox | Add `setup :verify_on_exit!` in test module | Request-change |
| Test using `assert result == {:ok, ...}` (stringified) | `assert {:ok, %User{...}} = result` (pattern match, better failure) | Suggest |
| Factory creating hardcoded unique values | Use `sequence(:email, &"user-#{&1}@x.com")` | Request-change |
| Test with 10+ lines of setup for a pure function test | The function needs a boundary — pure tests shouldn't need this much setup | Suggest (architectural) |
| Test that "sometimes" fails | Never leave flaky tests — find the root cause | Block |
| Parametrized test loop using `@attr bad` rebinding to smuggle the loop variable into each generated `test` | Use a single `test` with `for` loop inside the body (rich assertion messages), or `unquote(Macro.escape(bad))` in the test body (which IS inside a quote) | Suggest | implementing testing-patterns §Parametrized Tests |
| Canonicalizer / validator / parser function with only example-based tests | Add StreamData property tests. Tables miss adversarial edge cases — port suffixes, case variants, IPv4-mapped IPv6, trailing whitespace, Unicode homoglyphs | Suggest | implementing testing-patterns §Property-Based |
| Duplicated fixture data / lookup maps across multiple tests in the same file (e.g., same `valid_pairs = %{...}` copied into two tests) | Extract to a `@module_attribute` or a `setup` callback that returns it in the context | Suggest | implementing testing-patterns |

---

## 7.8 Security review

> **Depth:** For the full security audit checklist (input validation/injection, authn/authz, logging, crypto, Phoenix/Ecto-specific, dependency & operational concerns), load [security-audit.md](security-audit.md).

Commonly overlooked. Flag any of these.

| If you see... | Suggest instead | Severity |
|---|---|---|
| `String.to_atom(user_input)` or `Jason.decode!(json, keys: :atoms)` | `String.to_existing_atom/1`, or decode to string keys and convert explicitly | Block (atom table exhaustion) |
| SQL built with string interpolation (raw query) | Parameterized query via `Ecto.Query` or `Ecto.Adapters.SQL.query/3,4` with args | Block (SQL injection) |
| User-supplied data passed to `:erlang.binary_to_term/1,2` | Use `:safe` mode or prefer JSON / well-defined format | Block |
| Untrusted HTML interpolated into a template | Use LiveView's default safe rendering; only `raw/1` with known-safe content | Block (XSS) |
| Secrets, tokens, passwords in logs or error messages | Filter via `Logger.metadata`, `format_status/1`, or redact explicitly | Block |
| Secrets in `config/config.exs` or `config/dev.exs` | Move to `config/runtime.exs` + env vars | Block |
| Secret committed in a migration / seed / test file | Block; rotate the secret; move to env | Block |
| `File.read!("/user/#{user_input}")` (path interpolation) | Validate path; use `Path.expand/1` + check it stays within a safe root | Block (path traversal) |
| External HTTP call without timeout | Set `receive_timeout`; default may be infinite | Request-change |
| Endpoint without CSRF protection (non-API) | Phoenix's `:protect_from_forgery` plug | Block |
| Cookie without `secure`, `http_only`, `same_site` | Set them in endpoint config | Block (production) |
| No rate limiting on auth / password-reset / OTP endpoints | Add rate limiting (Plug, ex_rated, Hammer, or custom) | Request-change |
| Auth check in the controller, not in the context | Auth is cross-cutting — a plug or the context's public API should enforce it | Request-change |

---

## 7.9 Performance review (scan level)

**Flag obvious issues here. For measured performance investigation, use [profiling-playbook.md](profiling-playbook.md).**

| If you see... | Suggest instead | Severity |
|---|---|---|
| N+1 query pattern: `Enum.map(xs, fn x -> Repo.get!(...) end)` | `Repo.preload/2,3` or batch query | Block |
| `Enum.reduce(xs, "", &(&1 <> &2))` in a hot path | IO list pattern | Block (O(n^2)) |
| GenServer on the hot path serving reads | ETS `:public` + `read_concurrency: true` | Request-change |
| `length/1` used for "is non-empty" checks | Pattern match `[_ \| _]` vs `[]` (O(1)) | Request-change |
| `Enum.sort` followed by `Enum.take(1)` or `Enum.take(-1)` | `Enum.min`, `Enum.max`, `Enum.min_by`, `Enum.max_by` | Request-change |
| Large data in `Application.get_env` on a hot path | `:persistent_term` | Suggest |
| `Ecto.Repo` per-request query building with identical queries | Consider compile-time query module or `prepare: :named` | Suggest |
| Repeated `Jason.decode!` of the same JSON in a loop | Decode once outside the loop | Request-change |
| `Task.async` + `Task.await` for bounded parallelism | `Task.async_stream` with `max_concurrency` | Suggest |
| Missing index on a queried foreign key | Add index in migration | Request-change (if queried often) |
| Streaming large files via `File.read!` | `File.stream!` + `Stream.*` | Request-change |

**Patterns worth request-change even WITHOUT measurement:** some code shapes make the performance impact obvious from the diff alone — don't block on "have you measured this?" for these. Flag them as request-change with a brief why:

- `Application.get_env` inside a tight loop or per-request hot path (read once at boot into `:persistent_term` / module attribute).
- `<>` binary concatenation inside `Enum.reduce` / recursion (O(n^2) — use IO lists).
- `Enum.*` on a large known-to-be-large list where only early results are consumed (`Enum.take(..., k)` without `Stream.*`).
- `Repo.get(...)` inside `Enum.map` on a caller-supplied list (classic N+1).
- `Jason.decode!` of the same JSON string in a loop (decode once outside).

For p95/p99 latency, memory-over-time, GC pressure — those still need measurement. But for algorithmic-shape issues visible in the diff, measurement is the author's responsibility at merge time, not the reviewer's gate.

---

## 7.10 Configuration review

Full reference: `elixir-implementing` §8.6, `elixir-planning` §10.

| If you see... | Suggest instead | Severity |
|---|---|---|
| `System.get_env(...)` in `config/config.exs` | Move to `config/runtime.exs` | Request-change |
| `Application.compile_env` in a library | Runtime `get_env` or accept config via options | Block (if library) |
| Missing default in `Application.get_env(:app, :key)` | Provide default (`get_env(:app, :key, default)`), or use `fetch_env!` if required | Request-change |
| Config value read on every call (hot path) | Cache in module attribute (app), `:persistent_term` (library hot path), or `Application.compile_env` (app) | Suggest |
| Application code uses `Application.get_env` for a value that's truly frozen at compile time (no `runtime.exs` override, no test `put_env`) | Switch to `Application.compile_env` — Dialyzer sees the concrete type, missing-key crashes at compile, recompile triggers on config change. **Don't blindly switch:** if `config/runtime.exs` or any test overrides the key at runtime, `compile_env` silently freezes the default and breaks those flows. Verify both paths before changing | Suggest | implementing §10.5 |
| `config/runtime.exs` parses an env var with `String.to_integer/1`, `String.to_atom/1`, etc. on raw input | Wrap with explicit validation: `case Integer.parse(val) do {n, ""} when n in range -> n; _ -> raise "VAR_NAME must be X, got: #{inspect(val)}" end`. A raw conversion exception at boot gives ops a stacktrace instead of a message | Request-change | implementing production-patterns §runtime.exs |
| `runtime.exs` splits a comma-separated env var and `String.to_atom/1` on each element (`NODEPULSE_NODES="a@h1,b@h2"` → list of atoms) | Even for operator-controlled inputs this is unbounded atom creation on typos. Validate each element against a regex like `~r/^[a-z][\w]*@[\w\-.]+$/i` BEFORE converting, OR cap the list size, OR use `String.to_existing_atom/1` with a raise-on-unknown fallback. A CI pipeline accidentally generating a list of 10k node names can permanently exhaust the atom table | Block if from CI/untrusted; Request-change if strictly operator-controlled | implementing production-patterns §runtime.exs |
| Hardcoded URLs / credentials / secrets | Move to config + env var | Block |
| Test config imported into runtime code | Keep `config/test.exs` isolated; production should never import test config | Block |
| `Application.get_env`/`fetch_env!`/`compile_env` scattered across many modules (> ~3 files outside the config accessor module) | Centralize in `MyApp.Config` — every module routes config reads through zero-arg accessors. In an umbrella, one Config module per deployable. Grep `Application.get_env\|fetch_env\|compile_env` lib/ should only hit the Config module | Request-change | implementing §10.5.1, planning §10.5 |
| `==` comparison of a secret (API token, HMAC digest, verifier code, dev-path password) coming from an untrusted source | `Plug.Crypto.secure_compare/2` — `==` is variable-time and leaks byte-position via timing. For cleartext password verification specifically, use the password lib's verifier (`Bcrypt.verify_pass/2`) — it's already constant-time | Block | implementing §8.2.1 |

---

## 7.11 Ecto migration review

Migrations are a distinct artifact class. The bugs are bigger (production data loss, broken rolling deploys) and the lint stack is thinner (no `mix format` or `credo` rule catches most migration issues). Review with an explicit checklist:

- [ ] **Reversible** — has an explicit `def up` / `def down`, or `def change` that Ecto can auto-reverse. Irreversible migrations (e.g. `execute("...")` with no down version) must include a comment explaining why.
- [ ] **No schema module inside the migration** — migrations must NOT `alias MyApp.Schema`. Schema modules evolve over time; the migration's semantics must stay pinned. Use raw SQL or a migration-local schema.
- [ ] **New foreign keys are indexed** — `add :thing_id, references(:things)` without a matching `create index(:table, [:thing_id])` is a deadlock waiting to happen (FK lookup table-scans).
- [ ] **NOT NULL columns have defaults OR use two-step backfill** — adding `add :field, :string, null: false` to a populated table crashes the migration. Two-step pattern: (1) add nullable + backfill; (2) later migration adds `NOT NULL`.
- [ ] **Wrapped queue-library migrations are pinned** — `Oban.Migration.up(version: 12)` (not `up()`) so future Oban versions don't silently add migrations when you re-run.
- [ ] **Precision-sensitive columns match the schema** — `:utc_datetime_usec` column → schema declares `timestamps(type: :utc_datetime_usec)`. Mismatches cause round-trip bugs that are invisible until production.
- [ ] **Concurrent index creation for large tables** — `create index(..., concurrently: true)`; ALTER TABLE locks long enough to stall writes otherwise. Requires `@disable_ddl_transaction true` + `@disable_migration_lock true`.
- [ ] **`execute("...")` with user-like strings is parameterized safely** — migrations run in a privileged context; SQL injection via migration is rare but devastating. Prefer `execute(&up/0, &down/0)` with structured code over string interpolation.
- [ ] **Data backfill goes through a separate script or Oban job for large tables** — in-migration `Repo.update_all(...)` on a 50M-row table will time out or lock production. Consider: migrate schema first, backfill in a follow-up job.
- [ ] **Rolling-deploy compatible** — during deploy, old code runs against the new schema (and vice-versa). Columns can't be renamed in one step: (1) add new; (2) deploy code reading both; (3) backfill; (4) deploy code reading only new; (5) drop old.

Block-severity: missing down, NOT NULL without backfill, schema module aliased in the migration, unindexed FK. Request-change: precision mismatch, un-pinned Oban migration. Suggest: adding `@moduledoc` explaining the non-obvious parts.

---

## 7.12 Composition shape review

Full reference: `elixir-implementing` §5.10 (composition patterns), `elixir-planning` §4.7 (composition design vocabulary). The most common architectural smell on diffs is **the wrong composition shape** for the operation — not bad code, just the wrong primitive. Six mechanisms cover most production code: Pipeline (transform), Stream (lazy pipeline), Threading-builder (Multi/Conn/Socket — subject type fixed, state accumulates), Railway (`with` for sequential ok/error), Protocol/Behaviour (dispatch), Process (concurrent state). Mixing them in one operation, or picking the wrong one, is what makes diffs "look long" without being clearly bad.

**Diagnosis approach when reviewing a chain:** name the shape the code *uses* (rebind chain, `with` chain, manual recursion, eager `Enum`). Then name the shape the operation *needs* (independent validators? sequential dependency? lazy stream?). Mismatches are the findings.

| If you see... | Suggest instead | Severity | Archdo rule |
|---|---|---|---|
| `with` chain (>=2 `<-`) inside `validate_*` / `import_*` / `bulk_*` / `check_*` function whose success body combines 2+ bound values into a struct/map | Replace with **error-accumulating reduce** — short-circuit gives bad UX (user fixes one field, resubmits, sees next error). Wrap each validator in a reducer that collects errors into a list; return `{:error, errors}` if non-empty. Cross-ref `elixir-implementing` §5.10.6, `elixir-planning` §4.7.2. | Request-change for form/UX-facing flows; Suggest for internal | 6.95 ShortCircuitOverAccumulating |
| `case fetch() do {:ok, v} -> {:ok, transform(v)}; {:error, _} = e -> e end` (verbose Result.map) | `with {:ok, v} <- fetch(), do: {:ok, transform(v)}`, OR a `Result.map/2` helper if the shape recurs in 3+ places. The `case` shape buries the intent. | Suggest | 6.96 ResultMapOpportunity |
| Public 2-arg function with first arg named `opts`/`options`/`config` and last arg looking like the data subject (named `data`/`list`/`map`/`subject` or destructured `%Schema{} = subject`) | Reorder to subject-first: `def fun(data, opts)`. The stdlib (`Enum.map(coll, fn)`, `String.replace(s, pat, rep)`) is rigorous; backwards order silently breaks every downstream pipeline. Renaming arguments is a 5-minute refactor that pays off forever. Cross-ref `elixir-implementing` §5.10.10. | Request-change in domain APIs; Suggest in adapters | 6.97 PipeSubjectPosition |
| 2+ levels of nested `Map.update` / `Map.put` lambdas reaching into a known structure | `update_in(state, [:a, :b], &fn)` / `put_in(state, [:a, :b], v)`. Nested-lambda form obscures the path; `update_in` says it in one line and composes. **Caveat 1**: `Map.update/4` with a non-trivial default (`Map.update(req, :body, %{name => v}, &Map.put(&1, name, v))`) cannot be replaced by `put_in` — `put_in` requires the path to already exist. Use `update_in` only when the path is guaranteed populated, OR keep `Map.update/4`. **Caveat 2**: Archdo 6.98 has FP class — flagging "two `Map.put` calls where the second is in the value-arg of the first" includes cases where they operate on DIFFERENT maps (`Map.put(outer, :k, Enum.reduce(xs, %{}, fn _, acc -> Map.put(acc, ...) end))`). Read the diagnostic, verify both `Map.put`s actually mutate the same structure. Cross-ref `elixir-implementing` §5.10.9. | Suggest | 6.98 NestedMapUpdateAsUpdateIn |
| Pipeline starting with `File.stream!` / `Repo.stream` / `Stream.resource` / `Stream.unfold` followed by 3+ eager `Enum.*` steps | Replace intermediate `Enum.*` with `Stream.*`; only the terminal step (`reduce`/`count`/`into`) must be eager. Each eager step materializes the whole intermediate list, defeating the lazy producer. Order-of-magnitude memory difference on large inputs. Cross-ref `elixir-implementing` §5.10.11. | Request-change if input may be large; Suggest otherwise | 6.99 StreamOverEnumOpportunity |
| Two-clause private function: `defp f([], acc), do: acc; defp f([h \| t], acc), do: f(t, transform(h, acc))` | `Enum.reduce(xs, init, fn h, acc -> transform(h, acc) end)` — or one of `reduce_while` / `map_reduce` / `flat_map_reduce` / `Enum.sum` / `Enum.frequencies` depending on shape. Manual recursion is only needed for non-fold shapes (tree traversal, mutual recursion). Cross-ref `elixir-implementing` §5.10.12. | Suggest | 6.100 ManualRecursionAsReduce |
| 3+ consecutive `subject = Mod.fun(subject, ...)` rebindings to the same name (Multi/Conn/Socket/Changeset builder pattern) | Thread with pipes: `Mod.new() \|> Mod.fun1(...) \|> Mod.fun2(...)`. The rebind form is imperative-flavored — forces the reader to verify each line refers to the previous binding. Cross-ref `elixir-implementing` §5.10.13. | Suggest | 6.101 BuilderPatternNotThreaded |
| Public `to_X/1` (encoder: `to_string`, `to_json`, `to_url`, `to_iodata`) without a matching `from_X` / `parse_X` / `decode_X` in the same module | Either add the inverse (with a round-trip property test asserting `decode(encode(x)) == x`), OR if the output is for human display only, implement `String.Chars` / `Inspect` instead — those don't imply a round-trip contract. **Cross-checked against production: 6.102 has high FP rate** — three classes of legitimate one-way encoders that should NOT be flagged: (1) **external-API serializers** (`to_stripe`, `to_intercom`, `to_segment`) — output is for an HTTP request, the receiving system sends back its own shape; (2) **lossy projections** (`to_minor_units :: Money.t() -> integer` — drops currency; `to_stripe_currency :: Money.t() -> String.t()` — drops amount); (3) **stdlib decoder wrappers** (`to_date!` — `Date.from_iso8601` exists; `to_atom` — `String.to_existing_atom` exists). Skip the diagnostic if the encoder fits any of these classes. Cross-ref `elixir-planning` §4.7.5, `architecture-patterns.md` §4.12.8. | Suggest (low confidence — high FP class) | 6.102 EncoderWithoutDecoder |
| Module with `defstruct` + smart constructor (`validate`/`parse`/`build`/`new` returning `{:ok, %__MODULE__{}}`) + functions taking `%__MODULE__{}` as input | Consider phantom types: split into `%UnverifiedEmail{}` (raw input) and `%Email{}` (validated). Consumers signed for `%Email{}` are statically guaranteed validated. Defensive answer: keep the single struct + add a property test asserting validate's invariant. Cross-ref `elixir-planning/architecture-patterns.md` §4.12.8. | Suggest (judgment-soft); Request-change only if validation is non-trivial AND consumers should not accept raw input | 6.103 PhantomTypeOpportunity |
| `with` chain >=7 `<-` clauses in one function | Architectural drift signal — investigate, don't auto-flag. 2-4 healthy, 5-6 approaching limit, 7+ deserves a look. **Genuine exceptions** to the "split it" advice (verified against production code): a deliberate **filter cascade** where every `<-` is a "should we proceed?" predicate (e.g., social-feed filtering — Pleroma's `streamer.ex:198` runs 11 filter checks; splitting would harm clarity); a **threading-builder disguised as `with`** where every step is `%{error: nil} = subject <- step(subject)` (e.g., logflare's `logs_search.ex:60`). Read the chain before flagging. Cross-ref `elixir-implementing` §5.10.4. | Suggest (with note "verify this isn't a deliberate filter / state-machine") | n/a (judgment) |
| `with` `else` clause that handles success values, OR catch-all `else` clauses re-raising errors (`else x -> x`) | Bare `with` (no `else`) is the LCO-safe railway form — errors propagate transparently. Add `else` ONLY to translate error shapes for callers; never to handle success. Catch-all `else` adds nothing the bare form doesn't already do. Cross-ref `elixir-implementing` §5.10.1, §5.10.2. | Request-change for new code; Suggest for legacy | n/a (idiom) |
| Building-block-flavored function (per axes 1-6) with capabilities read inline (`DateTime.utc_now`, `:rand.uniform`, `Application.get_env`, `:persistent_term.get`) | Pass the capability as an argument. For 2+ capabilities, bundle into a `ctx` struct threaded through the call chain. The orchestrator resolves and provides the capability. Cross-ref `elixir-implementing` §5.10.8, `elixir-planning` rule 22c. | Request-change for modules claiming building-block status; Suggest otherwise | n/a (related to 5.74) |

---

## 7.13 Building-block module review

Full reference: `elixir-planning/building-blocks.md`. Modules that claim building-block status (via `@moduledoc`) — or modules that the diff intends to make building-block-shaped — get reviewed against the seven-axis checklist. Each axis is binary: pass or fail.

**The seven axes:**

| Axis | Means | Failed when... |
|---|---|---|
| 1. Input closure | Output is a function of arguments only | Reads `Application.get_env`, `DateTime.utc_now`, `:rand.uniform`, `:persistent_term.get`, `Process.get`, `:ets.lookup` (anything not in the parameter list) |
| 2. Determinism | Same inputs → same outputs | Same as axis 1 — usually overlap |
| 3. `@spec` | Public functions have type contracts | Missing `@spec` on a public function |
| 4. Totality | Function returns for every input in the documented domain | Raises on inputs the spec accepts; or accepts inputs not documented |
| 5. Side-effect freedom | No observable effect besides the return value | Calls `Logger.*`, `Phoenix.PubSub.broadcast`, `Repo.insert/update/delete`, `:telemetry.execute`, `:ets.insert`, `:persistent_term.put`, sends messages, writes files |
| 6. Errors as values | Failures returned as `{:error, _}`, not raised | `raise` for an expected failure (e.g., not-found, invalid format); use `!` variant if raise is intended |
| 7. Input guard | Input domain narrowed by guards / pattern match / changeset / `Ecto.Enum` | Public function accepting `term()` or unconstrained `map()` without runtime validation |

**What to flag in review:**

| If you see... | Severity | Archdo rule |
|---|---|---|
| Module with `@moduledoc "Building block ..."` (or matching `@moduledoc "building-block ..."`) AND a `Logger.*` / `Phoenix.PubSub.*` / `Repo.*` / `:telemetry.execute` / `:ets.insert` / `:persistent_term.put` call inside any function body | Block — the moduledoc is lying. Either remove the side effect (extract to orchestrator) OR remove the building-block claim. Pure logic + side effects in one module is the textbook anti-pattern. Cross-ref `elixir-planning/building-blocks.md` §3.1 axis 5. | 5.74 InlineEffectInBuildingBlock |
| Building-block module with expensive call (`Regex.compile!`, `Jason.decode!`, `:crypto.hash`, `DateTime.from_iso8601`) on a literal argument inside a function body | Suggest — hoist to a module attribute (`@valid_re Regex.compile!("^[a-z]+$")`). The expensive work should run once at compile time, not every call. For boot-time large values use `:persistent_term.put`. Cross-ref `elixir-implementing` §9.13, `elixir-planning` §4.7.8. | 5.75 MemoizeOpportunity |
| Building-block module with public functions that lack `@spec` | Request-change — building-block status implies a contract. `@spec` IS the contract. | n/a (axis 3) |
| Building-block module with public function that takes an unconstrained `term()` / `any()` without guard or pattern-match narrowing | Request-change — input guard is axis 7. A function whose input domain is unbounded cannot be property-tested. | n/a (axis 7) |
| Building-block module with `raise` on an expected failure path (not bang variant) | Request-change — return `{:error, reason}`. Raises break axis 6 (errors-as-values). The `!` variant is for the explicit-raise contract. | n/a (axis 6) |
| Module that mixes obvious building-block functions (pure transforms) with obvious orchestrator functions (DB writes, PubSub, HTTP) — no `@moduledoc` classification, no boundary | Suggest — split into `MyApp.Pricing` (building block) + `MyApp.Pricing.Workflow` (orchestrator). Mixing the two in one module fails Archdo's `Blackbox` analyzer (CE-54..57) and makes property-testing impossible. Cross-ref `elixir-planning` rule 11b, `building-blocks.md` §3.5. | Suggest (architectural) | n/a (CE-54 BlackboxQuadrant) |
| New module added without classification (no `@moduledoc` indicating `building_block` / `orchestrator` / `interface`) | Suggest — explicit classification clarifies what the module is FOR. The `@moduledoc` doesn't have to literally use those words, but the description should make the type clear ("Pure pricing functions", "Orchestrates checkout flow", "LiveView for the cart"). | Suggest | n/a (rule 11b) |

**Severity calibration**: a building-block claim is a *contract*. Breaking it is request-change minimum, block if the claim is load-bearing for property tests or downstream reasoning. A module without the claim isn't held to these rules — only flagged if it would obviously benefit from being one.

---

## 7.14 LiveView async / CPS review

Full reference: `phoenix-liveview/SKILL.md` "Async as Continuation-Passing Style". A LiveView is a single GenServer per user session. Synchronous work in `handle_event/3` freezes the session — clicks queue, the UI feels unresponsive, and a single slow API call hangs the whole user.

| If you see... | Suggest instead | Severity | Archdo rule |
|---|---|---|---|
| `handle_event/3` calling `Req.get/post/...` / `HTTPoison.*` / `Tesla.*` / `Finch.request` / `:httpc.request` synchronously | Wrap with `start_async/3` + `handle_async/3`. The handler returns `{:noreply, start_async(socket, :name, fn -> work end)}` and a separate `handle_async(:name, {:ok, result}, socket)` callback receives the result. LV stays responsive throughout. | Block (production smell) | 5.76 InlineHttpInLiveViewEvent |
| `handle_event/3` calling a **context function that internally performs HTTP** (e.g. `MyClient.fetch_user(id)` which wraps `Tesla.get`, `Github.get_repo(token, name)`) without `start_async`. The context call hides the HTTP underneath but the LV process still freezes for the request duration | Same fix as the direct-HTTP row: wrap the context call in `start_async/3`. **Archdo rule 5.76 has a known false-negative class for indirect HTTP** — it only detects direct calls to HTTP-lib modules (`Tesla.*`, `Req.*`, etc.). A reviewer reading the actual code must trace context calls that perform I/O underneath. Verified production case: logflare's `vercellogdrains_live/index.ex:120` calls `Vercel.Client.delete_log_drain(drain_id)` synchronously — wraps Tesla internally, not flagged by Archdo, but same UX freeze. | Block (production smell) | 5.76 (FN class) |
| `handle_event/3` calling a long-running `Repo.*` query (full-table scan, complex aggregation) without `start_async` | Same fix as above. `Repo.transaction` / `Repo.all` on slow queries blocks the LV identically to HTTP. | Request-change | n/a |
| `mount/3` doing blocking work without `connected?(socket)` guard | Move to `if connected?(socket), do: assign_async(socket, :data, ...)`. Mount runs twice (HTTP then WebSocket) — blocking work runs twice. The assign_async pattern handles both cleanly. | Request-change | n/a (LiveView rule 1) |
| `start_async` lambda capturing the full `socket` | Capture only what the lambda needs: `id = socket.assigns.user_id; start_async(socket, :load, fn -> Accounts.get(id) end)`. Capturing the socket pulls all assigns into the spawned process; if any contain large data (streams, big lists), memory bloats. | Request-change for LV with large assigns; Suggest otherwise | n/a |
| `assign_async`/`start_async` result rendered without `<.async_result>` wrapper for loading/error states | Use `<.async_result :let={data} assign={@data}>` with `<:loading>` and `<:failed>` slots. Direct rendering shows nothing during load, breaks on error. | Request-change | n/a |
| `handle_async/3` callback discarding `{:exit, reason}` (only handling `{:ok, result}`) | Add the failure clause: `def handle_async(:name, {:exit, reason}, socket)` — otherwise `Process.exit` from the spawned task is unhandled. Crash flows back as an error tuple, not an unhandled exit. | Request-change | n/a |

**Why this matters more than other "async" review**: LiveView's single-process-per-session shape makes blocking visible to the user immediately. A 2-second HTTP call in a controller is a 2-second response; a 2-second HTTP call in a LiveView `handle_event` is a 2-second freeze where every other click queues. The blast radius is one user, but the perception is "the app is broken."

---

## Cross-References

- **Core reviewing skill:** [SKILL.md](SKILL.md) — rules, severity, workflows
- **Anti-patterns catalog:** [anti-patterns-catalog.md](anti-patterns-catalog.md) — named patterns by category
- **Security audit depth:** [security-audit.md](security-audit.md)
- **Refactor templates:** [refactor-templates.md](refactor-templates.md) — copy/paste fixes for review comments
- **Performance catalog:** [performance-catalog.md](performance-catalog.md) — 32 pitfalls with fixes
