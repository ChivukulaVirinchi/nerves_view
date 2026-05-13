---
name: elixir-planning
description: >
  Elixir architectural planning — the decisions made BEFORE writing code. Covers project
  layout, domain boundaries (contexts, aggregates), data ownership, multi-tenancy, process
  architecture and supervision, inter-context communication (direct call, PubSub, Registry,
  GenStage, Broadway, Oban, event sourcing), configuration, resilience (bulkheads, circuit
  breakers, retries, timeouts), architectural styles (hexagonal, modular monolith, CQRS,
  event-driven), growing from small to large, distributed systems, and anti-patterns.
  ALWAYS use when designing, architecting, structuring, or planning an Elixir application.
  ALWAYS use when choosing between umbrella/single-app, contexts, process placement, or
  supervision strategy.
  ALWAYS use when starting a new Elixir project or major refactor.
  For writing the code itself, also load elixir-implementing.
---

# Elixir — Planning Skill

Architectural decisions made **before** writing implementation code. This skill sits upstream of `elixir-implementing`: planning answers *what to build and how to structure it*; implementing answers *how to type it idiomatically*.

**Skill family:** **elixir-planning** (this) | **[elixir-implementing](../implementing/SKILL.md)** (writing code) | **[elixir-reviewing](../reviewing/SKILL.md)** (reviewing/debugging).

## Subskills — deep references

This SKILL.md covers decision tables and quick-reference rules. For depth, load the relevant subskill:

| Subskill | Load when |
|---|---|
| [architecture-patterns.md](architecture-patterns.md) — principles, composition primitives, hexagonal/modular-monolith/CQRS/event-driven, boundary opacity | Deciding architectural style or composition shape |
| [data-ownership.md](data-ownership.md) — ownership rules, aggregates, multi-tenancy, sagas, idempotency | Designing data model, tenant isolation, cross-context transactions |
| [process-topology.md](process-topology.md) — "need a process?" table, supervision strategy, error kernel, process-per-entity | Designing supervision tree; placing processes |
| [integration-patterns.md](integration-patterns.md) — 6 inter-context mechanisms, escalation path, capacity planning, sagas | Designing how contexts communicate |
| [growing-evolution.md](growing-evolution.md) — stage 1-2-3 evolution, refactoring decision tree | Growing an existing app; deciding whether to refactor |
| [project-layout.md](project-layout.md) — single app, umbrella, poncho, library vs app | Choosing project structure at start |
| [domain-boundaries.md](domain-boundaries.md) — when to create contexts, aggregates, ACL, context API design | Designing context boundaries and relationships |
| [configuration.md](configuration.md) — compile-time vs runtime, runtime.exs validation, config accessor | Designing configuration strategy |
| [resilience.md](resilience.md) — bulkheads, circuit breakers, retry/backoff, degradation, timeouts, trace context | Designing for failure and degradation |
| [architectural-anti-patterns.md](architectural-anti-patterns.md) — 14 anti-patterns with BAD/GOOD, Severity, Why | Verifying designs against known failure modes |
| [building-blocks.md](building-blocks.md) — seven-axis checklist, module classification, refactor decision tree, Archdo | Deciding what's pure vs orchestrator; property-test-friendly design |
| [otp-design.md](otp-design.md) — GenServer vs Task vs Agent vs `:gen_statem` vs ETS vs GenStage/Broadway vs Oban | Picking the OTP primitive for a use case |
| [test-strategy.md](test-strategy.md) — test pyramid, mock boundaries, factory architecture, CI strategy | Planning test infrastructure; fixing slow/flaky suites |
| [networking-design.md](networking-design.md) — TCP/UDP server architecture, protocol framing, connection supervision | Designing a network server or protocol |
| [distributed-elixir.md](distributed-elixir.md) — cross-node communication, distributed registries, state distribution, netsplit | Designing multi-node / clustered deployments |
| [long-running-projects.md](long-running-projects.md) — three-document model, milestone checklist, SSOT verification | Starting/resuming a long-running project |

**Cross-references:** subskills link to each other and to the other main skills' subskills (when they exist) via relative paths.

## How to use this skill

| Situation | Start here |
|---|---|
| Resuming long-running project | Load `long-running-projects.md` first |
| New project | §0 -> §1 -> §2 -> `project-layout.md`. Classify each module via `building-blocks.md` |
| New feature | §0 -> §2 -> §3. Load `domain-boundaries.md` + `process-topology.md` |
| Refactoring | `growing-evolution.md` -> `architectural-anti-patterns.md` -> `domain-boundaries.md` |
| Inter-context communication | `integration-patterns.md` |
| Designing for failure | `resilience.md` |
| About to write code | Verify plan passes §0, then load `elixir-implementing` |

**Not covered:** construct choice -> `elixir-implementing`; debugging -> `elixir-reviewing`; library selection; ADR format.

---

## 0. The Plan-Completeness Gate

**A plan is not a plan until every item below has a concrete answer.** If any answer is "TBD", "we'll pick later", or "depends", resolve it before coding.

**Layout & boundaries**
- [ ] Project layout chosen: single app, umbrella (name each sub-app), or poncho (`project-layout.md`).
- [ ] Every context named with its responsibility in one sentence (`domain-boundaries.md`).
- [ ] Data ownership: every table/entity has exactly one owning context (`data-ownership.md`).
- [ ] Context relationships mapped: caller -> callee, and the public API function names that bridge them (`domain-boundaries.md`).
- [ ] **For every struct crossing a context boundary**: opacity decision made — "opaque handle" (`@opaque` + accessors) or "public data structure" (fields as API). See `domain-boundaries.md` + `architecture-patterns.md`.

**Processes & supervision**
- [ ] The full supervision tree drawn (ASCII, Mermaid, or list — doesn't matter which, but it must be drawn). Every supervised process named with its restart strategy (`process-topology.md`).
- [ ] Start order justified by dependency order (`process-topology.md`).
- [ ] Every GenServer/Task/Agent/`:gen_statem`/Broadway/Oban worker has a concrete child spec in mind — not "some GenServer" (`process-topology.md`).
- [ ] Registry / DynamicSupervisor decisions named if the app has dynamic processes (`process-topology.md`).

**State**
- [ ] For every piece of state: where it lives (process, ETS, DB, `:persistent_term`, cache) and why (`process-topology.md`).
- [ ] What survives a crash vs what's volatile — explicit per piece of state (`process-topology.md`).
- [ ] Multi-tenancy strategy chosen if applicable — row-level / schema-per-tenant / DB-per-tenant (`data-ownership.md`).

**Communication**
- [ ] Every inter-context call path chosen from `integration-patterns.md` decision guide: direct call / PubSub / Registry / GenStage / Oban / event-sourced.
- [ ] Every payload (PubSub topic, Oban job args, GenStage event) has a concrete shape — field names and types.
- [ ] Every cross-context transaction either fits in one aggregate or has a named saga/idempotency strategy (`data-ownership.md`).

**External boundaries**
- [ ] Every external dependency behind a `@callback` behaviour with the exact callback names and signatures listed (`architecture-patterns.md`). No "we'll introduce the behaviour later."
- [ ] Config keys named for each adapter swap (test/stub vs prod) — including the exact `config :my_app, MyBoundary, ...` line.
- [ ] Every external call's failure mode classified: retry / circuit break / degrade / propagate (`resilience.md`).
- [ ] **Every external payload format is named** (JSON / Protobuf / Avro / line-delimited / fixed binary). ETF reserved for trusted intra-cluster traffic only via `Plug.Crypto.non_executable_binary_to_term/2`. No `Code.eval_string`/`eval_quoted`/`compile_string` on runtime data.
- [ ] **Logger.metadata propagation strategy named per async boundary.** Endpoint sets `Plug.RequestId`; Channel `join/3` calls `Logger.metadata/1`; Oban worker hydrates from args; Task captures parent metadata. Cross-node: explicit `TraceContext` struct. See `resilience.md`.
- [ ] **Every secret-bearing struct declares `Inspect` shape** at the `defstruct` block (`@derive {Inspect, only: [...]}` or `defimpl Inspect`). Same for `Jason.Encoder` if serialized.
- [ ] **Response boundaries drain stacktraces to Logger/telemetry, never return them.** Domain errors mapped through one error-translator module.

**Configuration**
- [ ] Every config value classified as compile-time vs runtime (§3.10, `configuration.md`).
- [ ] runtime.exs validation strategy chosen: which env vars are required, what the error message says (`configuration.md`).
- [ ] Config-accessor module named (`configuration.md`).

**Resilience**
- [ ] Every timeout chain cascaded: endpoint -> GenServer.call -> HTTP client — with numbers (`resilience.md`).
- [ ] Every retryable operation either idempotent by design or has a dedup/idempotency key strategy (`data-ownership.md`).

**Test strategy**
- [ ] For each context: which functions are unit-tested, which are property-tested, which need integration tests against the boundary (`test-strategy.md`).
- [ ] Mock boundaries chosen (Mox for behaviours, sandbox for Repo) — not "we'll mock something."

### 0.2 Banned phrases

Grep the plan for these — any hit means incomplete: `TODO`, `TBD`, `later`, `figure out`, `decide when`, `something like`, `probably`, `maybe`, `we'll pick`, `to be determined`. Replace each with a concrete noun (a name, a type, a number, a function signature).

### 0.3 Milestone splits are not placeholders

Milestones are fine — but **decisions** for all milestones must be made now. "We'll design M3 when we get there" means you haven't planned.

### 0.4 Completion check

Read the plan end-to-end. Grep for banned phrases (§0.2). Confirm every item above has a concrete noun. Pass -> implement. Fail -> resolve.

---

## 1. Rules for Architecting Elixir Applications (LLM)

1. **ALWAYS start with the simplest architecture**: single Mix application + contexts + one-level supervision. Add complexity (umbrella, PubSub, GenStage, Oban, event sourcing) only when the specific problem it solves is present.
2. **ALWAYS think in three modes of content** — this skill itself follows them: rules (constrain design at review), decision tables (guide at moment of designing), BAD/GOOD (verify). For each planning decision, check the relevant decision table in §3 first.
3. **ALWAYS sketch the supervision tree before writing code.** The supervision tree IS the architecture. Start order = dependency order. Strategy encodes coupling. If you cannot draw it, you cannot build it.
4. **ALWAYS put external dependencies behind a `@callback` behaviour.** Database, HTTP, email, payment gateway, hardware — every boundary that crosses out of your app. Config picks the implementation. This gives you hexagonal architecture for free.
5. **NEVER split a modular monolith into microservices for "loose coupling" or "fault isolation"** — OTP already provides both. Only split for different languages, compliance isolation, wildly different scaling needs, or genuinely separate teams/release cycles.
6. **ALWAYS use single Mix application over umbrella** until you need hard compile-time boundaries across teams or separate deployment targets. "Feels like it's getting big" is not a reason to split.
7. **ALWAYS name modules after the domain**, not the framework (`Accounts`, `Catalog`, `Billing` — not `Controllers`, `Models`, `Services`). Scream the domain.
8. **NEVER organize code into `models/`, `services/`, `helpers/` directories.** These are anti-patterns from other ecosystems. Elixir uses contexts (boundary modules) with internal modules marked `@moduledoc false`.
9. **NEVER call `Repo` across context boundaries.** Each table is owned by exactly one context. Other contexts read through the owning context's public API.
10. **NEVER put business logic in interface modules** (controllers, LiveViews, CLI handlers, GenServer callbacks). Interfaces translate input, delegate to a context, format output. Business logic lives in pure functions inside contexts.
11. **PREFER pure functions over processes.** Use a GenServer only when you need shared mutable state, serialized access to a resource, or scheduled work. If two concepts always change together in the same flow, they belong in the same process (or no process at all).
11b. **ALWAYS classify every new module as `building_block` / `orchestrator` / `interface` BEFORE typing the moduledoc.** A building-block is a module whose every public function passes the seven-axis checklist. An orchestrator connects building-blocks to side effects. An interface translates IO. Mixing the three in one module produces hard-to-test code. **Maximize building-block coverage**: aim for >= 60% of `lib/my_app/` modules to be building-blocks; >= 80% of pure-domain modules. Depth: `building-blocks.md`.
12. **ALWAYS design for replaceability.** Can you swap this component's implementation without changing business logic? If not, introduce a behaviour at the boundary.
13. **ALWAYS define the aggregate consistency boundary** for domain operations. One aggregate per transaction. Cross-aggregate operations are sagas or eventual consistency, never multi-aggregate `Repo.transaction`.
14. **ALWAYS identify which operations can be retried** (Oban workers, webhook handlers, event handlers, distributed calls) and design them to be idempotent from the start.
15. **ALWAYS choose a multi-tenancy strategy before starting** if the app is tenant-aware. Retrofitting multi-tenancy is painful. Row-level (tenant_id) is the default; escalate to schema-per-tenant or DB-per-tenant only when isolation requirements demand it.
16. **NEVER place circuit breakers or retry logic in domain modules.** They belong in infrastructure adapters, wrapping external calls.
17. **ALWAYS cascade timeouts correctly**: outer > middle > inner (endpoint > GenServer.call > HTTP client). Otherwise outer timeouts fire before inner ones with meaningless errors.
18. **ALWAYS start with direct function calls** between contexts. Escalate to PubSub when you need decoupling, GenStage when you need backpressure, Oban when events must survive restarts, event sourcing when you need audit/replay. Don't pre-select the complex solution.
19. **NEVER introduce distribution (multi-node clustering) until single-node is maxed out.** `Task.async_stream`, process pools, Broadway, read replicas — exhaust these first. Distribution brings network partitions, split-brain, and eventual consistency.
20. **ALWAYS hand off to `elixir-implementing` for the actual code.** This skill decides *what to build*; the implementing skill covers *how to type it idiomatically*.
21. **ALWAYS pass the plan-completeness gate (§0) before handing off.** A plan with TODOs, "TBD", "we'll pick later", or unresolved decisions is not a plan — it's a partial plan that will force decisions under pressure mid-implementation. Every checklist item in §0.1 must have a concrete noun answer before implementation begins. This rule has priority over all others.
22b. **ALWAYS pick a composition primitive at the design stage** for every multi-step operation. The four mechanisms — pipeline, railway (`with`-chain), protocol/behaviour, process — compose different kinds of things and must NOT be mixed in one operation. Split the *monadic* (`with`) and *applicative* (accumulating reduce) cases at planning time. Depth: `architecture-patterns.md`.
22c. **ALWAYS pass capabilities (clock, random, config, secrets) as arguments** in modules destined to be building-blocks. Hidden reads (`Application.get_env`, `:rand.uniform`, `DateTime.utc_now`) fail axis 1 of the building-block checklist. Depth: `building-blocks.md`, `architecture-patterns.md`.
22d. **ALWAYS plan effects-as-data when a building-block must signal "this should happen"** but isn't allowed to do it. Return events as a list; the orchestrator interprets and dispatches. Depth: `architecture-patterns.md`.
23. **ALWAYS use battle-tested libraries for authentication, password hashing, session management, cryptography, JWTs, OAuth, secret comparison, and access tokens — NEVER hand-roll these.** Canonical Elixir picks: `phx.gen.auth`, Guardian, Ueberauth, `bcrypt_elixir` / `argon2_elixir`, `Plug.Crypto.secure_compare/2`.
24. **ALWAYS design observability in from the start, with explicit Logger.metadata propagation across every async boundary.** `Logger.metadata` is per-process. Pick the propagation strategy at planning time. Depth: `resilience.md`.
25. **NEVER plan a system that converts external string identifiers to atoms.** Atoms are not garbage-collected; a request -> atom path is a remote DoS primitive. The only safe path from external string to atom is `String.to_existing_atom/1` against a closed compile-time allowlist. **`Ecto.Enum` is the canonical bounded-vocabulary pattern.**

---

## 2. The Planning Workflow

Walk through this sequence before starting any Elixir project or significant feature. Answer each question; defer to the named depth file for detail.

### 2.1 Opening questions for a new project

| Question | Defer to |
|---|---|
| What IS the domain? Name the business concepts (the contexts). | `domain-boundaries.md` |
| What are the inputs (interfaces) and outputs (side effects / external systems)? | `architecture-patterns.md`, `configuration.md` |
| Is this a library or an application? Who owns the supervision tree? | `project-layout.md` |
| Single Mix app, umbrella, or poncho? | `project-layout.md` |
| Does the app have tenants? Which isolation strategy? | `data-ownership.md` |
| What state needs to survive a crash? What's volatile? | `process-topology.md` |
| What state lives in processes vs. in the database? | `process-topology.md` |
| How will contexts communicate? Any cross-context consistency needs? | `integration-patterns.md` |
| What external services are involved? What happens when they fail? | `resilience.md` |
| What failure modes must the system tolerate gracefully? | `resilience.md` |

### 2.2 Opening questions for a new feature in an existing project

| Question | Defer to |
|---|---|
| Does this feature belong in an existing context, or does it warrant a new one? | `domain-boundaries.md` |
| Which context owns the data this feature operates on? | `data-ownership.md` |
| Does the feature cross context boundaries? If yes, how? | `integration-patterns.md` |
| Does it need a new process, or pure functions in an existing context? | `process-topology.md` |
| Is there a retry / failure path? Is the operation idempotent? | `data-ownership.md` |
| Does the feature need to degrade gracefully when a dependency is down? | `resilience.md` |

### 2.3 Opening questions when refactoring

| Question | Defer to |
|---|---|
| Which growth stage is this app at? | `growing-evolution.md` |
| Are there contexts doing more than one job (mixed responsibilities)? | `domain-boundaries.md` |
| Are there cross-context Repo calls, or contexts reaching into each other's internals? | `data-ownership.md` |
| Are there GenServers doing CRUD-y stuff that could be pure functions? | `process-topology.md`, `architectural-anti-patterns.md` |
| Is the supervision tree expressing the architecture, or is it flat? | `process-topology.md` |
| Are there processes simulating objects (agent-per-entity)? | `architectural-anti-patterns.md` |

### 2.4 The "what's needed now vs later" test

Elixir architecture is **additive**. The progression is:

```
Phase 0 (MVP):     Contexts + supervision + one behaviour (Repo)
Phase 1:           + PubSub for UI updates / decoupling
Phase 2:           + Oban for guaranteed async work
Phase 3:           + GenStage / Broadway for backpressured pipelines
Phase 4:           + Event sourcing for audit / replay (only if needed)
Phase 5:           + Distributed architecture (only if single-node maxed)
```

**Never adopt a phase before its triggering problem appears.** Each phase adds complexity; unjustified complexity compounds.

---

## 3. Master "Planning Decision" Table

This is the spine of the skill. Every major architectural question maps to a row. Find your question in the left column; the right columns show the decision and the defer-to depth file.

### 3.1 Project layout

| Question | Answer | Details |
|---|---|---|
| New project, one team, one deployable | Single Mix application + contexts | `project-layout.md` |
| New project, multiple teams with hard boundaries | Umbrella | `project-layout.md` |
| New project, cleanly separate runtime deployables | Umbrella with one app per deployable + shared `*_wire` app | `project-layout.md` |
| New project, apps need different dep versions | Poncho | `project-layout.md` |
| Building a reusable library (will be a Hex dep) | Single Mix application, NO supervision tree, behaviour-based extension points | `project-layout.md` |
| "Should I split this monolith?" | **Almost certainly no.** Add contexts first. | `growing-evolution.md` |
| Feels like it's getting big | Add contexts, do NOT split | `growing-evolution.md` |

### 3.2 Domain boundaries & data ownership

| Question | Answer | Details |
|---|---|---|
| New context needed? | Different business domain, team, or data lifecycle | `domain-boundaries.md` |
| Where does this function live? | In the context that OWNS the primary data | `data-ownership.md` |
| Context too big? | Multiple unrelated aggregates = too big | `domain-boundaries.md` |
| Two contexts need the same table? | One owns it; the other reads through owner's API | `data-ownership.md` |
| Entities must stay consistent | Same aggregate, same context, one `Repo.transaction` | `domain-boundaries.md` |
| Entities MAY be consistent | Different aggregates -> saga or eventual consistency | `data-ownership.md` |
| Cross-context transaction? | Missing boundary OR saga pattern | `data-ownership.md` |
| External system / legacy | Anti-corruption layer at the adapter | `domain-boundaries.md` |
| Idempotency needed? | Yes for anything retryable (Oban, webhooks, events, distributed calls) | `data-ownership.md` |
| Multi-tenant isolation? | Row-level (default), schema-per-tenant, or DB-per-tenant | `data-ownership.md` |

### 3.4 Processes & supervision

| Question | Answer | Details |
|---|---|---|
| Do I need a process? | **Probably not.** Most code is pure functions | `process-topology.md` |
| Shared mutable state | GenServer (one writer) | `otp-design.md` |
| Fast concurrent reads | ETS (one writer, many readers) | `otp-design.md` |
| State per entity (user, game, device) | DynamicSupervisor + Registry | `process-topology.md` |
| State must survive crash | Database + stateless process, OR recovery strategy | `process-topology.md` |
| Background work / scheduled | Task (transient) or Oban (persistent/cron) | `otp-design.md` |
| State machine with transitions | `gen_statem` | `state-machine` skill |
| Supervision strategy | `:one_for_one` (independent), `:rest_for_one` (depends on earlier), `:one_for_all` (tightly coupled) | `process-topology.md` |
| Startup order | Infrastructure (Repo, PubSub) -> Domain -> Endpoint last | `process-topology.md` |

### 3.6 Communication & integration

| Question | Answer | Details |
|---|---|---|
| Synchronous, need result | Direct function call via public API | `integration-patterns.md` |
| Fire-and-forget, loss OK | `Phoenix.PubSub` / `:pg` | `integration-patterns.md` |
| Per-entity subscriptions | `Registry` with `:duplicate` keys | `integration-patterns.md` |
| Backpressure needed | GenStage / Broadway | `integration-patterns.md` |
| Event must survive restart | Oban (persistent queue) | `integration-patterns.md` |
| Full audit trail / replay | Event sourcing (Commanded) | `integration-patterns.md` |
| Kafka / SQS / RabbitMQ | Broadway | `integration-patterns.md` |
| Multi-step with compensation | Saga or process manager | `integration-patterns.md` |
| External HTTP API / email / payment / gRPC | `@callback` behaviour + adapter + config switch | `architecture-patterns.md` |
| Swap implementation in tests | Behaviour + Mox | `test-strategy.md` |

### 3.8 Resilience

| Question | Answer | Details |
|---|---|---|
| External service may be slow/flaky | Circuit breaker in the adapter | `resilience.md` |
| Operation may fail transiently | Retry at the right layer (HTTP client, Oban, supervisor) | `resilience.md` |
| External service is down | Graceful degradation — return partial / cached / default | `resilience.md` |
| Timeouts across layers | Outer > middle > inner | `resilience.md` |
| Prevent one subsystem from failing another | BEAM processes as bulkheads (separate supervisors) | `resilience.md` |
| Prevent retries from duplicating | Idempotency | `data-ownership.md` |

### 3.9 Architectural style

| Question | Answer | Details |
|---|---|---|
| Default Elixir app | Contexts + supervision + behaviours (modular monolith, hexagonal, MVC all at once) | `architecture-patterns.md` |
| Separate read path from write path | Light CQRS (same context, both kinds of functions) | `architecture-patterns.md` |
| Reads need very different optimization | Separated read path (query module, optional read replica) | `architecture-patterns.md` |
| Full audit trail + replay + multiple read projections | Event sourcing + full CQRS | `architecture-patterns.md` |
| Decouple contexts with async notifications | PubSub (event notification or event-carried state transfer) | `architecture-patterns.md` |
| Split into microservices | Last resort — only for different languages, compliance, or org boundaries | `architecture-patterns.md` |

### 3.10 Configuration

| Question | Answer | Details |
|---|---|---|
| Value fixed at build, app-owned | `config/config.exs` + `Application.compile_env` | `configuration.md` |
| Env var, per-deployment | `config/runtime.exs` + `System.fetch_env!` | `configuration.md` |
| Library consumer configures | Accept runtime config via options; NEVER `compile_env` in a library | `configuration.md` |
| Test-specific overrides (Mox wiring, small pool sizes) | `config/test.exs` | `configuration.md` |
| Feature flag, toggleable at runtime | External (FunWithFlags, Flagsmith, database row) | `configuration.md` |

---

## 4. Distributed Architecture — Mostly Don't

Most Elixir apps don't need distribution. Exhaust single-node options first. **Depth:** [distributed-elixir.md](distributed-elixir.md).

| Problem | Single-node solution | Distribute only when... |
|---|---|---|
| More throughput | `Task.async_stream`, Broadway, more cores | One machine maxed out |
| High availability | Supervisor restarts + blue/green deploy | Zero-downtime across regions required |
| Data locality | ETS caching, read replicas | Users in multiple regions |
| Background jobs | Oban (shares Postgres) | CPU-heavy work exceeds one node |
| WebSocket scale | Single node handles ~1M | More concurrent connections than one machine |

**When to distribute** — at least two of these must be true:
1. Single-node CPU / memory / IO is saturated.
2. Zero-downtime rolling deploys that survive single-node loss are required.
3. Geographic distribution needed (data locality).
4. State naturally partitions and doesn't fit on one node.
5. HA required for persistent in-memory state (presence, game state).

If fewer than two apply, don't distribute. See `distributed-elixir.md` for the full framework.

---

## 5. Handoff to `elixir-implementing`

Once the plan passes §0, load `elixir-implementing` and write the code.

| Planning decision | Implementation detail |
|---|---|
| Context ownership (`domain-boundaries.md`, `data-ownership.md`) | Context module structure |
| Process need (`process-topology.md`) | GenServer callbacks, state structure |
| Supervision (`process-topology.md`) | Application module + child specs |
| Communication (`integration-patterns.md`) | GenStage/Broadway/Oban templates |
| Boundary behaviour (`architecture-patterns.md`) | `@callback` + Mox wiring |
| Config (`configuration.md`) | `compile_env!` vs `get_env` |
| Multi-tenancy (`data-ownership.md`) | `prepare_query`, tenant_id |
| Idempotency (`data-ownership.md`) | `Oban.insert(unique: ...)` / `on_conflict:` |
| Resilience (`resilience.md`) | `:fuse`, retries, fallback values |

**Workflow:** Plan here -> `elixir-implementing` -> write -> test -> review. Revisit planning when structure needs change.

---

## 6. Related Skills

- **[elixir-implementing](../implementing/SKILL.md)** — decision tables for constructs, idiomatic templates, TDD, OTP callback patterns. Load when planning transitions to implementation.
- **[elixir-reviewing](../reviewing/SKILL.md)** — review checklist, anti-pattern catalog, debugging/profiling playbooks. Load when reviewing PRs.
- **`phoenix`** — contexts, controllers, plugs, router, channels, PubSub, security.
- **`phoenix-liveview`** — LiveView lifecycle, streams, hooks, uploads, components.
- **`ash`** — Ash Framework declarative resources, policies, actions, extensions.
- **`state-machine`** — `gen_statem`, `GenStateMachine`, AshStateMachine.
- **`event-sourcing`** — Commanded library, aggregates, projections, process managers.
- **`otp`** — GenStage, Broadway, hot upgrades, deeper distribution patterns.
- **`nerves`** — Embedded Elixir firmware.
- **`rust-nif`** — Rustler NIFs.
- **`elixir-testing`** — Deep testing reference beyond `elixir-implementing`.
- **`elixir-deployment`** — Mix releases, Docker, Kubernetes, observability.
- **`erpc`** — Distributed Elixir between nodes.

---

**End of SKILL.md.** Plan here, then load `elixir-implementing` to write the code.
