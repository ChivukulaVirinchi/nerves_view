---
name: quality-gates
description: >
  Quality checks before completing Elixir/Phoenix work. ALWAYS use when finishing a task,
  reviewing code, or running pre-merge checks. Covers formatting, compilation, Credo with
  ex_slop, ex_dna duplication detection, Dialyzer, and test verification. For BEAM runtime
  tools → load beam-introspection. For refactoring decisions → load refactoring.
---

# Elixir Quality Gates

Run these gates before marking any work complete. Each gate catches a different class
of defect. The gates are ordered from fastest to slowest -- fail fast on formatting
before waiting for Dialyzer.

## 1. Rules

1. **Run gates in order: format, compile, credo, ex_dna, dialyzer, tests** -- fastest first; no point running Dialyzer if code does not compile.
2. **`mix format --check-formatted` must pass with zero diff** -- formatting is non-negotiable.
3. **`mix compile --warnings-as-errors` must produce zero warnings** -- unused variables, missing functions, and deprecations are all caught here.
4. **`mix credo --strict` includes ex_slop checks** -- ex_slop adds 40 Credo checks that catch AI-generated code anti-patterns.
5. **`mix ex_dna` detects code duplication** -- runs AST-based clone detection (Type I/II/III clones). Run after any large code addition.
6. **`mix dialyzer` catches type violations** -- run on changed modules at minimum; full project run for significant refactors.
7. **Remove all debug artifacts** -- `IO.inspect`, `dbg`, `IO.puts` for debugging must not ship.
8. **Run relevant tests with `--trace`** -- not just "tests pass" but "the right tests exist and cover the change".
9. **Public functions need `@spec` and `@doc`** -- specs enable Dialyzer; docs enable `get_docs` introspection.

## 2. Decision Table

| Intent / Situation | Gate(s) to Run | Skip? | Why |
|---|---|---|---|
| Quick formatting check | `mix format --check-formatted` | Never skip | Instant; catches style violations |
| After any code change | `mix compile --warnings-as-errors` | Never skip | Catches unused vars, missing functions, deprecations |
| Before completing a task | Full pipeline: format + compile + credo + tests | Never skip | Minimum quality bar |
| After large code addition (50+ lines) | Add `mix ex_dna` to pipeline | Never skip for large additions | Catches copy-paste duplication before it spreads |
| Before merging a PR | Full pipeline + `mix dialyzer` + `mix ex_dna` | Never skip | Type errors and duplication caught pre-merge |
| AI-generated code review | `mix credo --strict` (includes ex_slop) | Never skip for AI code | ex_slop catches 40 LLM-specific anti-patterns |
| Changed a LiveView | Add `smoke_test` + `validate_js_hooks` | Skip only if no template/hook changes | Catches mount failures and broken hooks without a browser |
| Changed JS hooks | `validate_js_hooks` | Never skip for hook changes | Parses bundle, cross-refs templates, validates callbacks |
| Changed Ecto schemas | `mix dialyzer` (at minimum on changed files) | Do not skip | Schema changes ripple through types |
| Quick iteration during development | Format + compile only | OK to defer credo/dialyzer | Fast feedback; run full pipeline before marking done |
| Tidewave available | Use `check_code_quality` instead of `mix credo` | -- | Richer output: Credo + ex_slop combined in one call |
| Tidewave available | Use `find_code_clones` instead of `mix ex_dna` | -- | Same AST engine, richer output with refactoring suggestions |

## 3. Patterns

### 3.1 Skipping Compilation Warnings

**Severity:** BLOCK

```elixir
# BAD -- ignoring the warning
$ mix compile
warning: variable "result" is unused (did you mean to use "_result"?)
  lib/my_app/orders.ex:42

# Just proceeding to tests anyway...

# GOOD -- treat warnings as errors
$ mix compile --warnings-as-errors
# Fix every warning before proceeding
```

**Why:** Compilation warnings indicate real issues: unused variables often mean a logic error (computed but not returned), missing function warnings mean broken call sites, and deprecation warnings mean future breakage.

### 3.2 Debug Artifacts Left in Code

**Severity:** BLOCK

```elixir
# BAD -- shipping debug output
def process_order(order) do
  IO.inspect(order, label: "DEBUG order")
  result = calculate_total(order)
  dbg(result)
  result
end

# GOOD -- clean production code
def process_order(order) do
  calculate_total(order)
end

# Verify with:
$ rg "IO.inspect|dbg\b" lib/ --type elixir
# Must return zero results
```

**Why:** `IO.inspect` and `dbg` write to stdout, which in production goes to log aggregation. They leak internal data structures, slow down hot paths, and signal unfinished work.

### 3.3 Missing ex_slop Integration

**Severity:** WARN

```elixir
# BAD -- standard Credo without AI-pattern checks
# mix.exs
{:credo, "~> 1.7", only: [:dev, :test], runtime: false}

# .credo.exs -- default checks only

# GOOD -- Credo + ex_slop for AI code detection
# mix.exs
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:ex_slop, "~> 0.2", only: [:dev, :test], runtime: false}

# .credo.exs -- ex_slop checks are auto-discovered by Credo
# No config changes needed; ex_slop registers its 40 checks automatically
```

**Why:** Standard Credo catches general Elixir style issues. ex_slop adds 40 checks specifically designed to catch patterns that AI/LLM code generators produce: over-abstraction, unnecessary wrappers, redundant type checks, and more. If your project uses AI-assisted development, ex_slop is essential.

### 3.4 Missing ex_dna Integration

**Severity:** WARN

```elixir
# BAD -- no duplication detection
# (relying on manual code review to catch copy-paste)

# GOOD -- AST-based clone detection
# mix.exs
{:ex_dna, "~> 1.3", only: [:dev, :test], runtime: false}

# Run after any large code addition:
$ mix ex_dna

# ex_dna detects three types of clones:
# Type I:  Exact copies (ignoring whitespace/comments)
# Type II: Renamed variables, changed literals
# Type III: Statements added/removed/reordered
```

**Why:** Copy-paste duplication is the most common form of tech debt in AI-assisted codebases. ex_dna uses AST analysis to detect clones that text-based tools miss (renamed variables, reordered statements). Catching duplication early prevents it from spreading.

### 3.5 No Tests for New Code

**Severity:** BLOCK

```elixir
# BAD -- "it compiles and works manually"
# (no test file created for the new module)

# GOOD -- tests exist and cover the change
$ mix test test/my_app/orders_test.exs --trace
# Verify:
# - Happy path tested
# - Error cases tested
# - Edge cases tested (empty input, nil, boundary values)
```

**Why:** Code without tests is code with unknown behavior. It cannot be safely refactored, and regressions are discovered by users instead of CI. `--trace` shows each test name, confirming coverage of the intended scenarios.

### 3.6 Missing @spec on Public Functions

**Severity:** SUGGEST

```elixir
# BAD -- no spec; Dialyzer cannot check callers
def create_order(user, params) do
  # ...
end

# GOOD -- spec enables Dialyzer and documents the contract
@spec create_order(User.t(), map()) :: {:ok, Order.t()} | {:error, Changeset.t()}
def create_order(user, params) do
  # ...
end
```

**Why:** `@spec` serves two purposes: Dialyzer uses it to detect type mismatches at call sites, and it documents the function contract for other developers (and for `get_docs`/`get_type_specs` introspection).

## 4. Checklist

### Mandatory Gates (every task)

- [ ] `mix format --check-formatted` -- zero diff
- [ ] `mix compile --warnings-as-errors` -- zero warnings
- [ ] `mix credo --strict` -- zero issues (includes ex_slop if installed)
- [ ] `rg "IO.inspect|dbg\b" lib/ --type elixir` -- zero results
- [ ] Relevant tests pass: `mix test test/path/relevant_test.exs --trace`

### Extended Gates (before merge / large changes)

- [ ] `mix ex_dna` -- no new Type I/II clones
- [ ] `mix dialyzer` -- zero errors on changed modules
- [ ] `rg "TODO|FIXME" lib/ --type elixir` -- all tracked or resolved

### LiveView Gates (when UI changed)

- [ ] `smoke_test` -- server-side mount succeeds
- [ ] `validate_js_hooks` -- hooks parse, match templates, have correct callbacks
- [ ] `browser_inspect` -- full browser render (if Lightpanda available)

### Code Quality (all code)

- [ ] Public functions have `@spec` and `@doc`
- [ ] `@impl true` on all callbacks
- [ ] Contexts are focused (not monolithic)
- [ ] Associations preloaded (no N+1)
- [ ] Error tuples for user-facing, bang functions for internal

### Frontend Quality (when templates changed)

- [ ] Uses existing components (searched shared/ first)
- [ ] LiveView templates are composition only (no business logic)
- [ ] Streams for collections (not list assigns)
- [ ] Class syntax uses `{[...]}` for conditionals
- [ ] No inline `<script>` tags

## 5. Routing

| If you need... | Load instead |
|---|---|
| BEAM runtime introspection tools | `beam-introspection` |
| Refactoring based on duplication findings | `refactoring` |
| Performance measurement | `observability` |
| LiveView page verification | `phoenix-verify` |
| HEEx template syntax | `heex` |
| Security audit | `security` |

## Gate Pipeline Reference

Run in this order (fastest to slowest):

```bash
# 1. Format (< 1s)
mix format --check-formatted

# 2. Compile (2-10s)
mix compile --warnings-as-errors

# 3. Credo + ex_slop (3-15s)
mix credo --strict

# 4. Debug artifact check (< 1s)
rg "IO.inspect|dbg\b" lib/ --type elixir

# 5. Architecture scripts (< 5s each)
elixir .claude/skills/reviewing/scripts/check_ecto.exs
elixir .claude/skills/reviewing/scripts/check_security.exs
elixir .claude/skills/reviewing/scripts/check_liveview.exs
elixir .claude/skills/reviewing/scripts/check_forms.exs
elixir .claude/skills/reviewing/scripts/check_oban.exs
elixir .claude/skills/reviewing/scripts/check_architecture.exs
elixir .claude/skills/reviewing/scripts/check_templates.exs
elixir .claude/skills/reviewing/scripts/check_validate_action.exs
elixir .claude/skills/reviewing/scripts/check_secrets.exs
elixir .claude/skills/reviewing/scripts/check_specs.exs
elixir .claude/skills/reviewing/scripts/check_with_complexity.exs
elixir .claude/skills/reviewing/scripts/check_list_access.exs
elixir .claude/skills/reviewing/scripts/check_components.exs

# 6. Duplication check (5-20s)
mix ex_dna

# 7. Type checking (30s-5min, cached after first run)
mix dialyzer

# 8. Tests (varies)
mix test test/path/relevant_test.exs --trace
```

### Architecture Scripts

These scripts enforce rules that markdown guidelines can only suggest. Each scans `lib/` statically and exits non-zero on violations:

| Script | Catches |
|---|---|
| `check_ecto.exs` | N+1 queries, missing on_delete, float for money, SQL injection |
| `check_security.exs` | String.to_atom, raw() XSS, hardcoded secrets |
| `check_liveview.exs` | Deprecated phx-update, stream misuse, missing connected? guard |
| `check_forms.exs` | Missing form id, bracket access on structs, missing phx-change, no phx-disable-with |
| `check_oban.exs` | Atom keys in args, struct args, missing @impl, no error handling |
| `check_architecture.exs` | Repo calls in web layer |
| `check_templates.exs` | Oversized render functions and templates |
| `check_validate_action.exs` | Missing `action: :validate` in validate handler's `to_form()` |
| `check_secrets.exs` | Structs with sensitive fields missing `@derive {Inspect, only: [...]}` |
| `check_specs.exs` | Public functions missing `@spec` annotation |
| `check_with_complexity.exs` | `with` expressions with 7+ arrow clauses |
| `check_list_access.exs` | Bracket index access on lists (`list[0]`) |
| `check_components.exs` | Raw HTML elements instead of Phoenix components |

Run all scripts at once:
```bash
for f in .claude/skills/reviewing/scripts/check_*.exs; do elixir "$f" || exit 1; done
```

## Setup Reference

### Adding ex_slop to a project

```elixir
# mix.exs deps
{:ex_slop, "~> 0.2", only: [:dev, :test], runtime: false}
```

ex_slop registers its checks with Credo automatically. No `.credo.exs` changes needed. Run `mix credo --strict` as usual -- ex_slop checks appear alongside standard Credo checks.

### Adding ex_dna to a project

```elixir
# mix.exs deps
{:ex_dna, "~> 1.3", only: [:dev, :test], runtime: false}
```

Run `mix ex_dna` to scan for code clones. Output shows clone groups with file locations, similarity percentage, and suggested refactoring targets.

## Tidewave Equivalents

When Tidewave MCP tools are available, use these for richer output:

| CLI Gate | Tidewave Equivalent | Advantage |
|---|---|---|
| `mix credo --strict` | `check_code_quality` | Credo + ex_slop combined; formatted output |
| `mix ex_dna` | `find_code_clones` | AST-aware; includes refactoring suggestions |
| `rg "IO.inspect"` | `ast_search pattern="IO.inspect(_)"` | Structural match; no false positives in strings |
| Manual LiveView test | `smoke_test path="/route"` | Server-side mount verification; no browser |
| Manual JS hook check | `validate_js_hooks` | Parses bundle, cross-refs templates |
| Manual browser test | `browser_inspect path="/route"` | Full render with hooks and WS checks |

### LiveView Verification Chain (in order)

1. `smoke_test path="/my-page"` -- server mounts without crashing?
2. `validate_js_hooks` -- JS hooks parse and match templates?
3. `browser_inspect path="/my-page"` -- full browser renders correctly?

## Review Output Format

```markdown
## Review: {task}
**Status**: PASS | NEEDS WORK

### Gates
- [PASS] format
- [PASS] compile
- [FAIL] credo: 2 issues (ex_slop: unnecessary_wrapper at lib/foo.ex:12)
- [PASS] ex_dna: no new clones
- [PASS] tests: 14 passed

### Issues
- [High] Description - file:line
- [Medium] Description - file:line
- [Low] Description - file:line

### Recommendation
Ready to complete | Needs fixes: {list}
```

**Severity guide:** High = blocking/crashes, Medium = patterns/conventions, Low = style/suggestions
