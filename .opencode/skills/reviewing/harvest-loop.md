# Review Comment Style + Harvest Loop

> **Depth file for [SKILL.md](SKILL.md).** Load when writing review feedback or closing the review → implementing feedback loop.

---

## 12. Review Comment Style

How to phrase feedback so it's actionable and not annoying.

### 12.1 Good review comment structure

```
[severity] [location] [observation]

[why it matters — 1 sentence]

[suggested fix — code snippet or link]

[link to the skill section for context]
```

### 12.2 Examples

**Bad comment:**
> "This is wrong."

**Good comment:**
> **[request-change]** `lib/my_app/orders.ex:45` — `length(orders) > 0` is O(n); on a large list this scans the whole thing.
> Use pattern-match for O(1): `if match?([_ | _], orders), do: ...`
> (See `elixir-implementing` §7.3.)

**Bad comment:**
> "You should add tests."

**Good comment:**
> **[block]** `register/1` is a new public function without tests. Please add tests covering:
>
> - happy path (valid attrs → `{:ok, user}`)
> - invalid email (→ changeset error)
> - duplicate email (→ constraint error)
> - mailer failure (via `Mox.expect`)

**Bad comment:**
> "Why are you doing it this way?"

**Good comment:**
> **[question]** `lib/my_app/workers/charge.ex:12` — is there a reason this uses `stub` instead of `expect`?
> With `stub`, a test passes even if the function is never called. If the charge MUST happen, `expect` would catch a regression where the call is accidentally removed.

### 12.3 Review-comment rules

1. **Lead with severity** — `[block]`, `[request-change]`, `[suggest]`, `[nit]`, `[question]`. The author reads the tag first.
2. **Say what, not just that it's wrong.** "This is wrong" is worthless; "`length/1` is O(n)" is actionable.
3. **Suggest the fix.** Paste the refactor; don't make the author guess.
4. **Link to the reason.** Pointing at `elixir-implementing` §7.3 or `elixir-planning` §14 tells the author *why* without bloating the PR thread.
5. **Don't pile nitpicks on a junior.** If you have 10 nitpicks, pick 3. Save the rest for a follow-up.
6. **Avoid sarcasm, rhetorical questions, "obviously".** They don't improve the PR; they damage trust.
7. **Praise the good.** A "this is a nice refactor of the error-handling path" costs nothing and keeps reviews from feeling like an interrogation.

### 12.4 When the code is bad but the author can't fix it now

Sometimes a PR introduces a pattern that's wrong, but fixing it properly would grow the PR beyond its scope.

- **Block** if it's a correctness/security bug — scope be damned.
- **Don't block** if it's a pre-existing stylistic issue the PR only touches.
- **Request-change** with "let's file a follow-up issue" for anything in between.
- **File the follow-up yourself** if you care about it happening. Don't leave it to the author.

---

## 12b. Harvesting Findings — The Review → Implementing Feedback Loop

A review pass is not over when the findings are fixed. It's over when
**novel findings are promoted into the implementing catalog** so the
next author doesn't need the review to catch the same pattern.

### The gap this closes

Review findings tend to fall into two populations:

1. **Idiosyncratic** — specific to this PR's logic, one-off mistake,
   non-recurring. Leave in review comments; the diff gets the fix.
2. **Patterned** — this is the third time a `rescue _ ->` slipped
   through on a third-party API boundary, or the fourth time a
   context function returned `{:error, "some string"}` instead of a
   typed reason atom, or the fifth time a test used `Process.sleep/1`
   for synchronization. These are *not* one-offs. They are tells that
   the implementing skill is missing a BAD/GOOD pair, or the anti-slop
   catalog is missing a regex, or `elixir-implementing §1` is missing
   a rule.

Without a promotion ritual, patterned findings stay in review output
and fire again in the next review. The catalog doesn't grow from the
evidence.

### The ritual — post-review promotion

After each review pass that produced >3 findings, walk the findings
list with this question for each:

> *If I saw this pattern in a different PR six months from now, would
> I flag it again? And would it help if this skill / hook caught it
> at write time instead of review time?*

If the answer to both is yes, promote:

| Finding shape | Where it goes |
|---|---|
| Simple regex catch (e.g., `Process.sleep` in a test, `rescue _ ->` catch-all, `String.to_atom/1` on user input) | **`anti-slop-patterns.json`** as a new check under the `elixir` language group. Severity `warn` unless the pattern is clearly a bug. Write a message that points at the real rule. |
| Idiom violation with a one-line fix | **`elixir-implementing/SKILL.md §7` (anti-patterns Claude commonly produces)** as a new BAD/GOOD pair. Format: 5-10 line BAD block, 5-10 line GOOD block, 1-2 line rationale. |
| Architectural / design-time concern | **`elixir-planning/SKILL.md §1` (as a new rule)** or into the relevant subskill (e.g., `process-topology.md` for a new GenServer-sizing pitfall). |
| Proactive check that complements a reactive review rule | **`elixir-implementing §1` as a new numbered rule**, cross-referenced with the review-time counterpart. Example: the SSOT proactive rule (§1 #23) pairs with the review-time SSOT litmus (this skill's §1 or the `long-running-projects` SSOT-verification section). |

### What NOT to promote

- **Taste preferences.** "I'd name this `handle_message` not
  `on_message`" is not a pattern.
- **One-shot mistakes.** A typo, a misread changeset. Fixed in the
  diff, stays there.
- **Project-specific rules.** "In this codebase, `MyApp.Config` owns
  all timeouts." That belongs in the project's `CLAUDE.md` or
  `continue.md`, not in a global skill.
- **Findings whose fix is still disputed.** If the PR author pushed
  back and the team is still debating, don't codify. Let the
  resolution settle first.
- **Phoenix / Ash / LiveView framework-specific findings.** Those
  belong in the framework skill (`phoenix-liveview`, `ash`, etc.),
  not in the general `elixir-implementing` skill.

### Litmus for "is this repeatable slop?"

Before writing a new anti-slop pattern, check:

1. Have I seen this pattern in more than one session/project? (If no
   and you suspect it's a one-off, don't codify.)
2. Is the pattern detectable by a reasonably simple regex, or does it
   require semantic analysis? (Pure regex wins. Semantic analysis
   means a more sophisticated hook, which is fine but adds cost.)
3. Is there a clear idiomatic fix, not just "this is bad"? (Without a
   fix, the pattern is a complaint, not a rule.)

If all three are yes, write the catch. If any is no, leave it in the
review output and wait for a second occurrence.

### Worked example — `Process.sleep/1` in a test

Three separate review passes caught variants of:

```elixir
test "eventually processed" do
  send(pid, :go)
  Process.sleep(100)
  assert get_state() == :processed
end
```

Each fix was the same: `assert_receive {:done, _}, 500` for a message-
based signal, or `Task.await` / explicit synchronization if the work
is task-based. Three occurrences → promotion criterion met. Result:
new check `elixir-process-sleep-in-test` in
`anti-slop-patterns.json` (severity `warn`, skip unless the file has
`_test.exs` suffix), pointing at the existing §7 BAD/GOOD pair. The
regex catches occurrences; the BAD/GOOD pair explains the why; the
rule references the pair.

This is the target shape: each layer reinforces the others.

### When the catalog should shrink

Patterns rot, too. A check that fires once per review but always gets
a `RULE-EXCEPTION` marker is wrong — either the regex is too broad or
the pattern isn't really slop. Remove checks that:

- Fire only on false positives that nobody actually fixes.
- Were added for a specific project that no longer reflects current
  practice.
- Have been superseded by a more precise check.

A catalog that only grows eventually becomes ignored. Prune when a
check stops paying for itself.

---

## Cross-References

- **Core reviewing skill:** [SKILL.md](SKILL.md) — rules, severity, workflows
- **Refactor templates:** [refactor-templates.md](refactor-templates.md) — suggested fixes for review comments
- **Review checklists:** [review-checklists.md](review-checklists.md) — what to flag
- **Anti-patterns catalog:** [anti-patterns-catalog.md](anti-patterns-catalog.md)
