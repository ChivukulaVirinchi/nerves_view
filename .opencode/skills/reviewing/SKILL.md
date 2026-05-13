---
name: elixir-reviewing
description: >
  Code review, debugging, and profiling for Elixir. ALWAYS use when reviewing PRs,
  debugging issues, or profiling performance. For writing code → load implementing.
---

# Elixir — Reviewing

The skill for **inspecting existing Elixir code**. Three distinct modes, all covered here:

- **Review** — proactive audit of a PR or diff, looking for structural and stylistic issues
- **Debug** — reactive investigation of a specific bug or crash
- **Profile** — reactive investigation of a performance problem

This skill is the third in the Elixir family. The three divide labor by phase:

| Phase | Skill | Question it answers |
|---|---|---|
| Plan (before writing) | **[elixir-planning](../planning/SKILL.md)** | What to build, how to structure it |
| Implement (at keyboard) | **[elixir-implementing](../implementing/SKILL.md)** | How to type it idiomatically |
| Inspect (after writing) | **elixir-reviewing** (this) | What's wrong with it / where's the bug / why is it slow |

**Primary mode:** decision tables (where to look, what to flag, which tool) + BAD/GOOD pairs. Anti-pattern catalogs live in the other two skills; this skill cross-references them and frames each pattern as "flag if you see this" rather than "don't output this."

## Subskills

| File | Covers | Load when |
|---|---|---|
| [review-checklists.md](review-checklists.md) | Scanning checklists by area: architecture, control flow, pipelines, collections, error handling, OTP, testing, security, performance, configuration, migrations, composition shape, building-block, LiveView async | Reviewing a PR / diff systematically |
| [debugging-playbook.md](debugging-playbook.md) | Symptom → diagnosis flow for crashes, mailbox buildup, memory growth, slow response, flaky tests, Dialyzer warnings, CPU pegging; IEx.break!, tool cheat sheet | Investigating a specific bug |
| [profiling-playbook.md](profiling-playbook.md) | Tool selection + usage: `:timer.tc`, Benchee, fprof/eprof/cprof/tprof, `:recon`, `:observer`, telemetry, memory analysis, scheduler utilization, common traps | Measuring or optimizing performance |
| [performance-catalog.md](performance-catalog.md) | 32 common pitfalls with symptom → root cause → fix (data structures, Enum/Stream, OTP, Ecto, memory, serialization, Phoenix, process design) | Looking for performance issues in a review |
| [refactor-templates.md](refactor-templates.md) | Top recurring refactors as copy/paste templates: extract pure fn, try/rescue→ok/error, nested case→with, multi-clause, accumulating validation, update_in, start_async, Stream, building-block split | Writing review comments with suggested fixes |
| [harvest-loop.md](harvest-loop.md) | Review comment style guide + the post-review promotion ritual: how to harvest patterned findings into implementing/planning skills and anti-slop hooks | Writing review feedback; closing the review→implementing loop |
| [anti-patterns-catalog.md](anti-patterns-catalog.md) | Organized anti-patterns by category (code, process/OTP, Ecto/data, architecture/design, testing, security, config) with BAD/GOOD for each | General review / scanning a diff for named anti-patterns |
| [security-audit.md](security-audit.md) | Security checklist: input validation, injection, auth/authz, logging, crypto (incl. `:crypto` primitive decision table), Phoenix/Ecto-specific pitfalls | Conducting a security review |

### Domain references (within this folder)

| File | Covers | Load when |
|---|---|---|
| [security.md](security.md) | Auth, sessions, XSS, injection, atom exhaustion | Reviewing auth/security code |
| [quality-gates.md](quality-gates.md) | Formatter, Credo, Dialyzer, ex_slop, ex_dna | Running quality checks |
| [observability.md](observability.md) | Telemetry, profiling, performance measurement | Profiling or adding observability |
| [refactoring.md](refactoring.md) | Tech debt, safe extraction triggers | Assessing refactor candidates |
| [elixir-gotchas.md](elixir-gotchas.md) | LLM-specific mistakes: list bracket access, rebinding, struct access, naming, Enum.each accumulation | Catching LLM-generated code mistakes |
| [beam-introspection.md](beam-introspection.md) | BEAM runtime inspection, eval recipes | Runtime debugging |
| [phoenix-verify.md](phoenix-verify.md) | Web UI verification, auth flow testing (server-side via Tidewave) | Testing UI flows server-side |
| [phoenix-browser.md](phoenix-browser.md) | Real browser verification via agent-browser: LiveSocket, forms, hooks, streams, uploads, responsive, multi-role | Testing UI flows in a real browser |

**Cross-phase references:** for HOW to write fixes → `../implementing/SKILL.md`. For WHY it's shaped that way → `../planning/SKILL.md`. Domain skills like ecto and otp live in `../implementing/` — read them for implementation context during review.

## 0. Gate

**Choose the right mode:**

- Pre-merge, proactive → **Review**
- Post-merge, something's broken → **Debug**
- Post-merge, something's slow → **Profile**

**How to use this skill:**

1. **Reviewing a PR / diff?** — Read §1 (Rules), §3 (Workflow), load [review-checklists.md](review-checklists.md). Scan the diff against each checklist.
2. **Debugging a specific bug?** — §4 (Workflow), load [debugging-playbook.md](debugging-playbook.md) (find the symptom).
3. **Profiling performance?** — §5 (Workflow), load [profiling-playbook.md](profiling-playbook.md) (pick the right tool), [performance-catalog.md](performance-catalog.md) (common pitfalls).
4. **Writing review comments?** — §6 (Severity), load [harvest-loop.md](harvest-loop.md) (comment style).
5. **Unsure if something is worth flagging?** — §6 Severity Classification.

**Scope — what this skill does NOT cover:**

- Mechanical issues that `mix format`, `credo`, `dialyzer`, or Archdo catch — run those first (§3.0), don't re-flag their findings in a human review.
- Design from scratch (architecture, context boundaries, supervision tree) → load `elixir-planning`.
- How to write Elixir idiomatically when implementing fixes → load `elixir-implementing`.
- Deep security audits beyond the review checklists → load [security-audit.md](security-audit.md).
- Production ops / live tracing / distributed debugging under load — this skill covers the *review* side; production forensics is separate.

---

## 1. Rules

1. **ALWAYS separate severity from correctness.** A review finds *many* things; not all are worth blocking on. Use §6 to classify each finding as block / request-change / suggest / nitpick.
2. **ALWAYS start debugging with the smallest-scope tool** — `IO.inspect` or `dbg` before reaching for tracing, profiling, or Observer. Most bugs are found by inspecting values at suspect points.
3. **ALWAYS start profiling by measuring, not guessing.** Use `:timer.tc` for one-off timing, Benchee for comparisons, `mix profile.*` for finding the slow function. Never "optimize" without evidence.
4. **ALWAYS use `System.monotonic_time` for duration measurement** — never `System.system_time` (NTP sync causes jumps).
5. **NEVER use `:dbg` or `:erlang.trace` in production** — no safety limits, can crash nodes under load. Use `:recon_trace` or Rexbug with explicit message count limits.
6. **ALWAYS read the symptom before reading the code.** What does "slow" mean — p50, p99, tail? What does "crash" mean — which error, which stack frame, how often? A vague symptom wastes time.
7. **ALWAYS suggest the idiomatic refactor** when flagging an anti-pattern. "This is bad" without "do this instead" is low-value feedback.
8. **ALWAYS cross-reference elixir-implementing and elixir-planning** when flagging a finding — point reviewers to the section that explains *why* the idiomatic form is better.
9. **PREFER letting the supervisor restart a crashing process** over adding defensive `rescue` clauses. Before suggesting new error handling, ask whether the existing supervision tree already handles it.
10. **NEVER flag style issues that `mix format` or `mix credo` would catch.** Reviews are for things tools miss: architecture, idioms, subtle correctness, testability, performance.
11. **ALWAYS flag missing tests and `@spec` on public functions** — these are easy to add, compound in value over time, and are the strongest signal that a change was thought through.
12. **PREFER benchmark-driven refactor suggestions over intuition.** "This could be faster" is weak; "this is 40% slower in the linked Benchee run" is actionable.
13. **ALWAYS check the composition shape on diffs that pipe ok/error or thread state.** Before flagging a `with`-chain, identify which composition mechanism the operation NEEDS: pipeline (transform), railway (`with`, sequential dependency), accumulating reduce (independent validations), threading-builder (Multi/Conn/Socket), protocol/behaviour (dispatch). The wrong shape is the most common architectural smell on diffs that "just look long" — and it's invisible without naming the shape. Cross-reference: `elixir-implementing` §5.10 (composition patterns), `elixir-planning` §4.7 (composition design vocabulary).
14. **ALWAYS check building-block axes when reviewing a module marked `@moduledoc "Building block ..."` or claimed pure.** Walk the seven-axis checklist (input closure, determinism, `@spec`, totality, side-effect freedom, errors-as-values, input guard) for every public function. A building-block module that calls `Logger`, `Repo`, `Phoenix.PubSub`, `:telemetry.execute`, `Application.get_env`, `DateTime.utc_now`, or `:rand.uniform` inside a function body fails axis 5 (effect-free) or axis 1 (input-closure) and is silently lying. Cross-reference: `elixir-planning/building-blocks.md` (the seven-axis checklist), Archdo CE-54..57 (`BlackboxQuadrant`, `UntestedBuildingBlock`, `EffectLeak`, `UnguardedBuildingBlock`).

---

## 2. Decision Table

The three modes of this skill are not interchangeable. Each has a different question, different tools, different output.

| Mode | Question | Primary artifact | Primary output |
|---|---|---|---|
| **Review** | "What's wrong with this diff?" | PR / branch diff | Comments with severity + suggested fix |
| **Debug** | "Why is this bug happening?" | Failing test, crash report, observed misbehavior | Root cause + the minimum fix |
| **Profile** | "Why is this slow / heavy?" | Production telemetry, benchmark, complaint | Identified bottleneck + measured improvement |

**They share one method:** read existing code, form hypotheses about what is wrong, verify with evidence (static — read the code; dynamic — run it with inspection). They differ in what "wrong" means and what "evidence" means.

Mixing modes wastes time: full review on a bug report, ad-hoc debugging on a PR diff, micro-optimization without measurement.

---

## 3. Patterns — Review Workflow (PR / diff review)

### 3.0 Layered review — run mechanical tools first

A human review should only contain findings a tool can't produce. Before opening the diff, run (or confirm CI ran) the full mechanical stack:

| Tool | Catches | Out of scope for human review |
|---|---|---|
| `mix format --check-formatted` | Formatting | Never flag formatting by hand |
| `mix compile --warnings-as-errors` | Undefined functions, unused vars, unreachable clauses | These become blocking errors, not review comments |
| `mix credo --strict` | Style, complexity, consistency, naming | Only flag if Credo misses a pattern that *matters* |
| `mix dialyzer` | Type mismatches, unreachable patterns, missing `@spec` | See debugging-playbook.md §8.6 for Dialyzer-specific workflow |
| `mix deps.unlock --check-unused` | Unused deps | Don't review dependencies by hand |
| Structural / metric tools (Archdo, `:observer_cli`, inch) | Zone-of-Pain / Martin metrics, dead code, cyclic dependencies | Out of human-review scope — delegate |

**Golden rule:** if a tool flags it, don't re-flag it. Your review capital is scarce; spend it on architecture, idiom, subtle correctness, and testability that the tools CAN'T see.

Every review finding should answer: "why wouldn't a linter catch this?" If the answer is "it could", delete the finding.

### 3.1 Step-by-step

1. **Read the PR description.** What is the stated intent? Does the diff match?
2. **Read the tests first.** Tests describe behavior; code describes implementation. If the tests are missing or weak, that's the first finding.
3. **Scan the diff for architectural smells** — wrong layer, cross-context `Repo` calls, framework references from domain. These are block-severity by default. → [review-checklists.md §7.1](review-checklists.md)
4. **Scan for correctness issues** — control flow, pipelines, error handling, pattern matching. → [review-checklists.md §7.2–§7.5](review-checklists.md)
5. **Scan for OTP/process issues** — unsupervised work, blocking callbacks, call vs cast, state shape. → [review-checklists.md §7.6](review-checklists.md)
6. **Scan for security issues** — `String.to_atom` on user input, SQL injection via interpolation, leaked secrets in logs, unvalidated external data. → [review-checklists.md §7.8](review-checklists.md)
7. **Scan for testing gaps** — missing tests, tests that check implementation details, `Process.sleep` for async behavior. → [review-checklists.md §7.7](review-checklists.md)
8. **Scan for documentation gaps** — missing `@spec` / `@doc` / `@moduledoc` on public API.
9. **Scan for performance** — obvious quadratic patterns, N+1 queries, GenServer bottlenecks, string concat in loops. → [review-checklists.md §7.9](review-checklists.md), [performance-catalog.md](performance-catalog.md)
10. **Classify each finding** (§6) — block / request-change / suggest / nitpick.
11. **Write review comments** → [harvest-loop.md §12](harvest-loop.md) — specific, actionable, linked to the skill section that explains *why*.
12. **Check that the suggested fix is correct** before posting. An incorrect suggestion is worse than no suggestion.

### 3.2 Review decision — what to flag

| Observation | Action |
|---|---|
| Architectural smell | Flag. Severity: block if it crosses a boundary; request-change if it reinforces a bad pattern |
| Control-flow anti-pattern | Flag. Severity: request-change or suggest depending on reach |
| Missing `@spec` / `@doc` on new public function | Flag. Severity: request-change |
| Missing test for new behavior | Flag. Severity: block |
| Test that asserts implementation, not behavior | Flag. Severity: request-change — brittle test, blocks future refactors |
| Style inconsistency `mix format` / `credo` would catch | **Do NOT flag.** Let the tools handle it |
| `mix credo` finding already present | **Do NOT flag in the PR** — raise it separately or add to baseline |
| Taste preference with no evidence of harm | **Do NOT flag** — save capital for real findings |
| Security issue | Flag. Severity: block |
| Performance issue with no measurement | Flag as question: "have you measured this?" — do not block on speculation |
| Performance issue with measurement | Flag. Severity depends on impact |

### 3.3 What to check in every review

- [ ] Tests exist for the new behavior, and they pass
- [ ] Tests assert behavior, not internal calls
- [ ] `@spec` and `@doc` on every new or modified public function
- [ ] No `@moduledoc` missing on public modules (`@moduledoc false` is fine for internal)
- [ ] No cross-context `Repo` calls
- [ ] **No cross-context struct destructure** — flag `%OtherContext.Struct{field: f}` in caller code unless the struct is a documented public data type (Plug.Conn / Date style). Severity: request-change if private; suggest if undocumented
- [ ] No `String.to_atom(user_input)`
- [ ] No `try/rescue` for expected failures
- [ ] No `Process.sleep` in tests
- [ ] Idempotent for retried operations (Oban workers, webhook handlers)
- [ ] Timeouts set where appropriate
- [ ] **Composition shape matches intent** — `with` for sequential dependency, accumulating reduce for independent validations, threading-builder for state, pipeline for transforms
- [ ] **Building-block modules are pure** — seven-axis checklist: no side effects, no hidden inputs, has `@spec`, errors as values
- [ ] **Subject-first arg order** — first arg is data being transformed, options last
- [ ] **LiveView `handle_event/3` does not block** — wrap HTTP/heavy work in `start_async/3`

---

## 3b. Patterns — Debugging Workflow (finding a specific bug)

### Step-by-step

1. **Reproduce the bug** — a bug you can't reproduce can't be fixed with confidence. If you can't reproduce, the first goal is to find a reproduction. Try: exact inputs from the report, similar inputs, boundary conditions, concurrent access.
2. **Write the failing test** (TDD-for-bugs) — the reproduction IS a regression test. See `elixir-implementing` §3.6.
3. **Read the error** — full stack trace, module, function, line. Is it an exception (raise), exit signal (`:exit`), crash (supervisor restart)?
4. **Form a hypothesis** about which code path produces the bug.
5. **Verify with evidence** — add `IO.inspect`/`dbg` at the hypothesized point. Run. Is the value what you expected?
6. **If the hypothesis is wrong**, widen the inspection outward. Walk backwards through the call chain.
7. **For process-level bugs** (timeouts, mailbox buildup, crashes), use `:sys.trace`, `:observer`, or `Process.info`.
8. **For concurrent/flaky bugs**, check test async isolation, shared state, timing assumptions.
9. **Once found, consider whether other places have the same bug.** A single bug often has family members.
10. **Commit the failing test alongside the fix** so the bug is guarded against regression.

### Debug decision — which tool

| Question | Tool | Load for detail |
|---|---|---|
| What is this value at this point? | `IO.inspect/2` or `dbg/1` | — |
| What does this pipeline produce at each step? | `dbg()` at the end of the pipeline | — |
| Can I pause execution and inspect? | `IEx.pry/0` (needs `iex -S mix`) | — |
| What messages is this GenServer receiving? | `:sys.trace(pid, true)` | — |
| What is this process's state right now? | `:sys.get_state(pid)` | — |
| How long is this process's mailbox? | `Process.info(pid, :message_queue_len)` | — |
| What's the memory / CPU use of each process? | `:observer.start()` (GUI) or `:recon.proc_count/2` | — |
| What pattern of calls is hitting this module in prod? | `:recon_trace.calls(...)` with a message limit | — |
| Why does this test fail intermittently? | See [debugging-playbook.md](debugging-playbook.md) (flaky tests) | — |

### Start small, escalate only when needed

- **First reach**: `IO.inspect` / `dbg`. Most bugs found here.
- **Next**: `IEx.pry` or `break!` to pause execution.
- **Next**: `:sys.trace` or `:sys.get_state` for OTP processes.
- **Next**: `:observer` for system-wide view.
- **Last resort**: `:recon_trace` or Rexbug for production tracing (with message limits!).

**NEVER skip straight to tracing/profiling when a single `IO.inspect` would show the bug.**

---

## 3c. Patterns — Profiling Workflow (finding a performance problem)

### Step-by-step

1. **Define what "slow" means.** p50, p95, p99? Per-request? Whole-pipeline? Steady-state or cold-start? A vague "slow" wastes time.
2. **Measure before changing anything.** Set a baseline: `Benchee`, `:timer.tc`, `:telemetry` histogram. Without a baseline you cannot prove you made it faster.
3. **Profile to find the bottleneck** — which function / process is actually slow? Don't guess.
4. **Form a hypothesis** — *why* is this slow? Common causes in [performance-catalog.md](performance-catalog.md).
5. **Apply one change at a time.** Measure after each. If the change didn't help, revert it.
6. **Verify the improvement** at the same level the symptom was observed (e.g., if users complained about request latency, measure request latency — not just the inner function).
7. **Keep the measurement in CI** as a regression guard, or at minimum document the baseline and improvement.

### Profile decision — which tool

| Need | Tool | Notes |
|---|---|---|
| One-off duration of a block | `:timer.tc(fn -> ... end)` | Returns `{microseconds, result}`. No warmup — misleading alone |
| Compare two implementations | `Benchee.run(%{...})` | Warmup, statistics, memory |
| Find which function in a call tree is slow | `mix profile.fprof` | High overhead, detailed — use for dev, not prod |
| Time spent per function | `mix profile.eprof` | Moderate overhead — profile tests or dev requests |
| Call counts only | `mix profile.cprof` | Low overhead — which functions are called most |
| Unified modern profiler | `mix profile.tprof` | OTP 27+, lower overhead — prefer for large code bases |
| System-wide CPU/memory per process | `:observer.start()` (GUI) | Interactive |
| Top-N processes | `:recon.proc_count(:memory \| :message_queue_len, 10)` | Safe in prod |
| Binary memory leaks | `:recon.bin_leak(10)` | Forces GC, returns top hoarders |
| Production request timing | `:telemetry.span/3` + handlers | Low overhead, production-safe |

### Rules specific to profiling

- **Always warm up before measuring.** The BEAM JIT (OTP 24+) needs several runs to reach steady state. Benchee handles this; `:timer.tc` does not.
- **Always measure at the right granularity.** Micro-benchmarking a function that's called once per hour is wasted effort. Macro-benchmark the request / job / pipeline first, then zoom in.
- **Never optimize without profiling first.** You'll optimize the wrong thing.
- **Beware the heisenberg effect.** Heavy profilers (fprof, especially under tracing) change timing characteristics — microbenchmark results may not match production.
- **Production profiling must be bounded.** Message-limit every trace. A runaway trace can exhaust a node.

---

## 4. Checklist — Severity Classification

Every review finding needs a severity. Without it, the reviewer defaults to "everything is equally important" — which devalues every comment.

| Severity | Meaning | Examples |
|---|---|---|
| **Block** (must fix before merge) | Correctness bug, security issue, missing test, architectural violation | `String.to_atom(user_input)`; domain module importing web; business logic in controller; no test for new feature |
| **Request-change** (should fix, negotiable) | Clear idiom violation, missing `@spec`/`@doc`, brittle test, sub-optimal pattern | `length(list) > 0`; if/else for structural dispatch; `try/rescue` for ok/error flow; test asserting mock was called |
| **Suggest** (nice to have, author's call) | Refactor that would improve readability / maintainability | Extract a helper; prefer `for` comprehension over `reduce`; use `Map.new/2` instead of `Enum.reduce` into `%{}` |
| **Nitpick** (take-it-or-leave-it) | Style, naming, comment wording — things that don't affect behavior | Prefer `current_user` to `user`; this docstring could be clearer |
| **Question** (need info) | Clarification needed before you can assess | "Have you measured this?" / "Why not use existing X?" |

**Rules:**

1. Each block-severity finding must be fixed before merge.
2. Prefer suggest over request-change when you're unsure. Request-change is a stronger claim.
3. Explicitly label nitpicks as "(nit)" so the author can safely ignore them.
4. Don't block on taste. Block on facts.
5. Don't block on things the author didn't touch. File a separate issue.

**Severity by PR size:**

- Small PR (<100 LoC) — pick your battles; probably only block-severity comments + a handful of suggests
- Medium PR (100-500 LoC) — full review; classify everything
- Large PR (500+ LoC) — ask for a split first. Reviewing large PRs well is hard; reviewing them badly is worse than not reviewing them

---

## 5. Routing

### Related Skills — Elixir family

- **[elixir-planning](../planning/SKILL.md)** — architectural decisions. References: §14 (anti-patterns), §4.7 (composition vocabulary), building-blocks.md (seven-axis checklist).
- **[elixir-implementing](../implementing/SKILL.md)** — writing idiomatic code. References: §7 (anti-patterns), §5.10 (composition), §8 (daily ops), §9 (OTP).
- **`elixir-testing`** — deep testing reference (property-based, LiveView, channels, Oban, Wallaby).

### Claude Code slash commands

- **`/review`** — slash command for general PR review. This skill provides the Elixir-specific domain knowledge; the command provides the workflow frame.
- **`/security-review`** — slash command for security-specific audit. review-checklists.md §7.8 is the Elixir-specific security checklist; combine with the broader security-review command.

### Framework / domain

When reviewing code from these domains, load the specialized skill alongside this one:

- **`phoenix`** — Phoenix contexts, controllers, plugs, router, channels.
- **`phoenix-liveview`** — LiveView lifecycle, streams, hooks.
- **`ash`** — Ash Framework resources, policies, actions.
- **`state-machine`** — `gen_statem`, `GenStateMachine`, AshStateMachine.
- **`event-sourcing`** — Commanded aggregates, projections, process managers.
- **`otp`** — deeper OTP patterns (GenStage, Broadway, hot upgrades, distribution).
- **`nerves`** — embedded Elixir / firmware review patterns.
- **`rust-nif`** — Rustler NIF review.
- **`elixir-deployment`** — Mix releases, Docker, Kubernetes observability in deploy-related PRs.

### Post-Review: Run the Harvest Loop

After every review pass that produced 3+ findings, **run the promotion ritual** from [harvest-loop.md](harvest-loop.md): walk each finding, ask "would I flag this again in 6 months?", and promote patterned findings to the implementing/planning skills or anti-slop hooks. This is not optional — skipping it means the same patterns recur session after session. See [harvest-loop.md](harvest-loop.md) for the full ritual.

---

**End of SKILL.md.** This skill inspects code that already exists — in review, in debug, or in profile mode. For writing new code idiomatically, load `elixir-implementing`. For designing new systems, load `elixir-planning`. The three skills together cover plan → implement → review as a complete development cycle.
