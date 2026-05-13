# Elixir/Phoenix Skill System

Three-phase LLM skill guide for Elixir and Phoenix development. Everything lives under three folders — `planning/`, `implementing/`, `reviewing/` — matching the development workflow.

## Phase Workflow

```
planning --> implementing --> reviewing --> (next feature or back to planning)
```

**planning/** — Load BEFORE writing code. Architectural decisions: contexts, supervision trees, OTP boundaries, module classification (building-block vs orchestrator).

**implementing/** — Load AT the moment of writing. Idiomatic templates, BAD/GOOD pairs, construct-choice tables. Domain and framework depth files (ecto, otp, phoenix, liveview, etc.) live here.

**reviewing/** — Load AFTER writing code. Severity-classified checklists, debugging playbooks, anti-pattern detection. Quality and security depth files live here.

## Folder Structure

```
planning/          Phase 1 — architecture & design
  SKILL.md           routing core (rules, decision tables, gate)
  *.md               depth files (process-topology, data-ownership, etc.)

implementing/      Phase 2 — writing code
  SKILL.md           routing core (rules, decision tables, TDD gate)
  *.md               depth files (tdd-workflow, critical-patterns, etc.)
  ecto.md            domain: schemas, changesets, queries, migrations
  otp.md             domain: GenServer, Task, supervision, Registry, ETS
  testing.md         domain: ExUnit, Mox, factories, property tests
  heex.md            domain: HEEx template syntax, components, slots
  oban.md            domain: background jobs, worker design
  phoenix-forms.md   domain: LiveView forms, validation
  phoenix-uploads.md domain: file uploads in LiveView
  phoenix/           framework: controllers, plugs, routing, channels
  liveview/          framework: lifecycle, streams, components, async

reviewing/         Phase 3 — review, debug, profile
  SKILL.md           routing core (rules, checklists, severity)
  *.md               depth files (debugging-playbook, refactor-templates, etc.)
  security.md        domain: auth, sessions, XSS, injection
  quality-gates.md   domain: formatter, Credo, Dialyzer, ex_slop, ex_dna
  observability.md   domain: telemetry, profiling, measurement
  refactoring.md     domain: tech debt, safe extraction
  elixir-gotchas.md  domain: common LLM mistakes
  beam-introspection.md  domain: BEAM runtime inspection
  phoenix-verify.md  domain: web UI verification (server-side)
  phoenix-browser.md domain: browser verification via agent-browser
```

## Skill Composition

Load the phase SKILL.md, then read domain depth files as needed:

| Task | Load | Cross-phase references |
|---|---|---|
| Plan a new feature | `planning/SKILL.md` | |
| Plan OTP supervision | `planning/SKILL.md` + `planning/process-topology.md` | |
| Write a LiveView form | `implementing/SKILL.md` + `implementing/liveview/liveview.md` + `implementing/phoenix-forms.md` | |
| Write an Oban worker | `implementing/SKILL.md` + `implementing/oban.md` | |
| Add file uploads | `implementing/SKILL.md` + `implementing/liveview/liveview.md` + `implementing/phoenix-uploads.md` | |
| Write tests for Ecto | `implementing/SKILL.md` + `implementing/testing.md` + `implementing/ecto.md` | |
| Review a controller | `reviewing/SKILL.md` + `reviewing/security.md` | Also read `implementing/phoenix/phoenix.md` |
| Review an Oban worker | `reviewing/SKILL.md` | Also read `implementing/oban.md` |
| Review Ecto code | `reviewing/SKILL.md` | Also read `implementing/ecto.md` |
| Debug a LiveView | `reviewing/SKILL.md` + `reviewing/beam-introspection.md` | Also read `implementing/liveview/liveview.md` |
| Profile a slow page | `reviewing/SKILL.md` + `reviewing/observability.md` | |
| Verify UI in browser | `reviewing/SKILL.md` + `reviewing/phoenix-browser.md` | Also read `implementing/liveview/liveview.md` |
| Dogfood/QA a feature | `reviewing/SKILL.md` + `reviewing/phoenix-browser.md` | |
| Refactor a context | `reviewing/SKILL.md` + `reviewing/refactoring.md` | Also read `implementing/ecto.md` |

**Rules:**
1. Always load exactly one phase SKILL.md
2. Read domain depth files within that phase as needed
3. Cross-phase reads are for reference only — don't mix phase guidance
4. Never load two phase SKILL.md files simultaneously

## Quality Gate Protocol

Run before every commit and after completing a feature:

```bash
# Mandatory gates (every task)
mix format --check-formatted && \
mix compile --warnings-as-errors && \
mix credo --strict && \
rg "IO.inspect|dbg\b" lib/ --type elixir && \
mix test test/path/relevant_test.exs --trace

# Architecture scripts (enforce what markdown can only suggest)
for f in .claude/skills/reviewing/scripts/check_*.exs; do elixir "$f" || exit 1; done

# Extended gates (before merge)
mix ex_dna && mix dialyzer
```

The 13 scripts in `reviewing/scripts/` catch: N+1 queries, SQL injection, XSS, atom exhaustion, LiveView anti-patterns, form issues, Oban serialization bugs, Repo in web layer, oversized templates, missing validate action, exposed secret structs, missing @spec, complex `with` chains, list bracket access, and raw HTML elements. Load `reviewing/quality-gates.md` for the full checklist.

## Rationale Marker Convention

When a skill drives a code decision, mark it with `# §§`:

```elixir
# §§ implementing: §2.4 -- rescue at system boundary
# §§ planning: §8.6 -- DynamicSupervisor for per-device workers
# §§ reviewing: §7.12 -- false-negative class, intentional bypass
```

**Format:** `# §§ <phase>: §<section> -- <why>`

**When to add:** On any non-trivial decision: try/rescue, if/else with value branches, cross-context calls, OTP design choices, boundary crossings.

**Hook enforcement:** The `rationale-marker.py` hook fires on Write/Edit of `.ex`/`.exs` files when `[use-skills]` is active.

## Multi-Session Protocol

For projects spanning multiple sessions, maintain three documents:

| Document | Purpose | Update cadence |
|---|---|---|
| `PLAN.md` | Design intent, scope, decisions | At milestone boundaries |
| `continue.md` | Current state for cold pickup | Rewrite at every milestone finish |
| Commit messages | Historical record with `M\d+:` prefix | Every commit |

Load `planning/long-running-projects.md` for the full protocol.

## Tool Integration

Add to `mix.exs`:

```elixir
{:ex_slop, "~> 0.2", only: [:dev, :test], runtime: false},
{:ex_dna, "~> 1.3", only: [:dev, :test], runtime: false}
```

## Activation

Add `[use-skills]` to your prompt to activate skill enforcement and rationale marker hooks. Use `[no-skills]` to disable for casual/prototype work.
