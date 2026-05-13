---
name: elixir-ecto
description: >
  Comprehensive Ecto skill covering schemas, changesets, migrations, queries,
  race-safe inserts, locks, upserts, Multi flows, and query composition.
  ALWAYS use when writing Ecto schemas, migrations, changesets, queries, or
  any database-layer code. For Phoenix forms that use changesets -> load
  phoenix-forms. For testing Ecto code -> load testing.
---

# Ecto: Schemas, Changesets, Queries & Concurrency

Ecto is the database wrapper and query generator for Elixir. LLMs consistently
make mistakes around cast vs put_change boundaries, preload strategies, migration
safety, race conditions in insert flows, and lock selection. This skill covers
the full surface from basic schemas through production-grade concurrency patterns.

## 1. Rules

1. **Cast external, put_change internal.** Never `cast/4` server-generated values (slugs, timestamps, computed fields). Never `put_change/3` user-supplied params.
2. **Always specify `on_delete` for references.** The default `:nothing` silently creates orphan rows. Choose `:delete_all`, `:nilify_all`, or `:restrict` explicitly.
3. **Never use `:float` for money.** Use `:integer` (cents) or `:decimal` with explicit `precision` and `scale`.
4. **Pin all variables in queries.** Every external value in a `from` expression must use `^`. No exceptions.
5. **Never interpolate into `fragment/1` or `Repo.query/2`.** Always use parameterized placeholders (`?` for fragment, `$1` for raw SQL).
6. **Preload explicitly.** Never manually query associations inside `Enum.map` (N+1). Use inline, separate, join, or subquery preloads.
7. **Use `on_conflict` for race-safe get-or-create.** Never do `Repo.get` then `Repo.insert` for uniqueness-sensitive flows.
8. **Use `Ecto.Multi` when multiple writes must succeed or fail together.** Never scatter related `Repo.insert/update` calls outside a transaction.
9. **Prefer unique indexes over app-side read-then-insert checks.** The database is the only reliable arbiter of uniqueness under concurrency.
10. **Use `dynamic/2` for composable optional filters.** Never build filter trees with repeated `if/else` branching around full query rewrites.

## 2. Decision Tables

### 2.1 Changeset Function Selection

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Accept user params for known fields | `cast(changeset, params, fields)` | `put_change` with raw params | `cast` filters, converts types, tracks changes from untrusted input |
| Set a server-computed value (slug, hash) | `put_change(changeset, field, value)` | `cast` with server values in field list | Server values are trusted; `cast` would expose them to override |
| Build changeset from known Elixir data | `change(struct, attrs)` | `cast` when source is internal | `change` skips filtering since data is already trusted |
| Replace a full association | `put_assoc(changeset, assoc, value)` | Manual foreign-key writes | `put_assoc` handles association lifecycle |
| Accept nested user params for association | `cast_assoc(changeset, assoc, opts)` | `put_assoc` with raw params | `cast_assoc` validates nested input through child changeset |

### 2.2 Preload Strategy Selection

| Intent | Strategy | Example | Why |
|--------|----------|---------|-----|
| Always need the association | Inline preload | `Repo.all(from q in Quiz, preload: [:questions])` | Single query plan, no conditional logic |
| Sometimes need the association | Separate preload | `Repo.preload(quiz, :questions)` | Avoids join cost when not needed |
| Filter on association fields | Join preload | `from q in Quiz, join: qu in assoc(q, :questions), where: qu.active, preload: [questions: qu]` | Can't filter with inline preload |
| Order or limit association | Subquery preload | `from q in Quiz, preload: [questions: ^ordered_query]` | Inline preload can't express ORDER BY on association |

### 2.3 Concurrency Strategy Selection

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Get-or-create by unique key | `Repo.insert` with `on_conflict: :nothing` + `conflict_target` | `Repo.get` then `Repo.insert` | Race between get and insert causes duplicates or constraint errors |
| Upsert (create or update) | `on_conflict: {:replace, fields}` + `conflict_target` | Read-then-branch logic | Atomic, no race window |
| Concurrent user edits on same record | `optimistic_lock/3` on a version field | No locking at all | Prevents silent last-write-wins data loss |
| Protect an invariant across rows | Advisory lock or `lock("FOR UPDATE")` | App-side mutex | Database lock is the only process-safe mechanism |
| Sequence-like `max + 1` | Transaction + `lock("FOR UPDATE")` on parent | Unprotected `max(position) + 1` | Concurrent inserts produce duplicate positions |
| Multiple related writes | `Ecto.Multi` | Scattered `Repo.insert/update` calls | Multi gives atomic success/failure and named intermediate results |

### 2.4 Migration Safety

| Operation | Safe for Zero-Downtime? | Notes |
|-----------|------------------------|-------|
| Add column (nullable) | Yes | Old code ignores new column |
| Add column with default | Yes (Postgres 11+) | Default stored in catalog, not backfilled |
| Create table | Yes | No existing code references it |
| Add index concurrently | Yes | Use `@disable_ddl_transaction true` and `create_if_not_exists index(..., concurrently: true)` |
| Add index (not concurrent) | WARN -- locks table | Blocks writes for duration of index build |
| Remove column | No | Running code will crash on missing column. Deploy code first. |
| Rename column/table | No | Breaks running code and queries simultaneously |
| Change column type | No | May require table rewrite and breaks running code |

## 3. Patterns (BAD -> GOOD)

### 3.1 Cast vs Put_change Boundary

**Severity:** BLOCK

```elixir
# BAD -- casting server-generated values exposes them to user override
def changeset(struct, params) do
  struct
  |> cast(params, [:title, :slug])  # slug is server-generated!
end

# GOOD -- cast external, put_change internal
def changeset(struct, params) do
  struct
  |> cast(params, [:title])
  |> put_slug()
end

defp put_slug(changeset) do
  case get_change(changeset, :title) do
    nil -> changeset
    title -> put_change(changeset, :slug, Slug.slugify(title))
  end
end
```

**Why:** `cast/4` is for untrusted external input. If `:slug` is in the cast list, a user can set it directly by including `"slug"` in their params, bypassing your generation logic.

### 3.2 N+1 Query

**Severity:** BLOCK

```elixir
# BAD -- N+1: one query per quiz
quizzes = Repo.all(Quiz)
Enum.map(quizzes, fn quiz ->
  questions = Repo.all(from q in Question, where: q.quiz_id == ^quiz.id)
  %{quiz | questions: questions}
end)

# GOOD -- single preload query
quizzes = Repo.all(from q in Quiz, preload: [:questions])
```

**Why:** N+1 queries scale linearly with data size. 100 quizzes = 101 queries. Preload does it in 2 queries regardless of count.

### 3.3 Missing on_delete

**Severity:** BLOCK

```elixir
# BAD -- default :nothing creates orphan rows when parent is deleted
add :user_id, references(:users, type: :binary_id)

# GOOD -- explicit lifecycle
add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
```

**Why:** The default `:nothing` means deleting a user leaves behind all their associated records with dangling foreign keys. This causes crashes when code tries to preload the deleted parent.

### 3.4 Float for Money

**Severity:** BLOCK

```elixir
# BAD -- floating point rounding errors
add :price, :float

# GOOD -- integer cents
add :price, :integer  # store in cents, display as dollars

# GOOD -- decimal with explicit precision
add :price, :decimal, precision: 12, scale: 2
```

**Why:** `0.1 + 0.2 != 0.3` in IEEE 754. Financial calculations accumulate rounding errors that cause real accounting discrepancies.

### 3.5 SQL Injection via Interpolation

**Severity:** BLOCK

```elixir
# BAD -- SQL injection vector
fragment("name ILIKE '%#{search}%'")
Repo.query("SELECT * FROM users WHERE name = '#{name}'")

# GOOD -- parameterized
fragment("name ILIKE ?", ^"%#{search}%")
Repo.query("SELECT * FROM users WHERE name = $1", [name])
```

**Why:** String interpolation in SQL allows arbitrary query injection. Parameterized queries send the value separately from the SQL, making injection impossible.

### 3.6 Race-Unsafe Get-or-Create

**Severity:** BLOCK

```elixir
# BAD -- race condition between get and insert
case Repo.get_by(Thread, user_id: user_id, workbook_id: workbook_id) do
  nil ->
    Repo.insert!(%Thread{user_id: user_id, workbook_id: workbook_id})
  thread ->
    thread
end

# GOOD -- atomic upsert
{:ok, thread} =
  Repo.insert(
    %Thread{user_id: user_id, workbook_id: workbook_id},
    on_conflict: :nothing,
    conflict_target: [:user_id, :workbook_id]
  )

# If you need the row back after on_conflict: :nothing,
# re-read by the unique key:
thread = Repo.get_by!(Thread, user_id: user_id, workbook_id: workbook_id)
```

**Why:** Two concurrent requests can both pass the `get_by` nil check and both attempt insert, causing a constraint error or duplicate data.

### 3.7 Filter Composition Without dynamic

**Severity:** WARN

```elixir
# BAD -- repeated query branching
query = from(q in Quiz)
query = if status, do: from(q in query, where: q.status == ^status), else: query
query = if owner_id, do: from(q in query, where: q.owner_id == ^owner_id), else: query

# GOOD -- composable with dynamic
filters = dynamic(true)
filters = if status, do: dynamic([q], ^filters and q.status == ^status), else: filters
filters = if owner_id, do: dynamic([q], ^filters and q.owner_id == ^owner_id), else: filters

from q in Quiz, where: ^filters
```

**Why:** `dynamic/2` composes cleanly without rebuilding the full query at each step. It's the idiomatic Ecto pattern for optional filters.

### 3.8 Unprotected Position Increment

**Severity:** BLOCK

```elixir
# BAD -- concurrent inserts get same max
max_pos = Repo.one(from q in Question, where: q.quiz_id == ^quiz_id,
                   select: max(q.position))
Repo.insert(%Question{quiz_id: quiz_id, position: (max_pos || 0) + 1})

# GOOD -- transaction with row lock on parent
Repo.transaction(fn ->
  quiz = Repo.one!(from q in Quiz, where: q.id == ^quiz_id, lock: "FOR UPDATE")

  max_pos = Repo.one(from q in Question, where: q.quiz_id == ^quiz_id,
                     select: max(q.position))

  Repo.insert!(%Question{quiz_id: quiz_id, position: (max_pos || 0) + 1})
end)
```

**Why:** Without a lock, two concurrent inserts both read the same `max(position)` and produce duplicate position values.

### 3.9 Multi Without Named Steps

**Severity:** WARN

```elixir
# BAD -- anonymous multi steps, can't reference intermediate results
Ecto.Multi.new()
|> Ecto.Multi.insert(:step1, quiz_changeset)
|> Ecto.Multi.run(:step2, fn _repo, _changes ->
  # Can't access the inserted quiz
  {:ok, nil}
end)

# GOOD -- named steps with dependency references
Ecto.Multi.new()
|> Ecto.Multi.insert(:quiz, Quiz.changeset(%Quiz{}, attrs))
|> Ecto.Multi.insert(:default_section, fn %{quiz: quiz} ->
  Section.changeset(%Section{quiz_id: quiz.id}, %{title: "Default"})
end)
|> Repo.transaction()
|> case do
  {:ok, %{quiz: quiz, default_section: section}} -> {:ok, quiz}
  {:error, failed_step, changeset, _changes} -> {:error, failed_step, changeset}
end
```

**Why:** Named steps make Multi flows readable and allow accessing intermediate results. The match on transaction result gives precise error reporting.

### 3.10 Side-Effect Loops vs Bulk Operations

**Severity:** WARN

```elixir
# BAD -- N updates in a loop
Enum.each(question_ids, fn id ->
  Repo.update_all(from(q in Question, where: q.id == ^id),
                  set: [archived: true])
end)

# GOOD -- single bulk update
from(q in Question, where: q.id in ^question_ids)
|> Repo.update_all(set: [archived: true])
```

**Why:** Each `Repo.update_all` is a separate database roundtrip. A single query does the same work in one roundtrip, and the database can optimize the execution plan.

## 4. Checklist

### Schema/Changeset Review
- [ ] `cast/4` only lists fields that come from external input
- [ ] Server-computed fields use `put_change/3` or `change/2`
- [ ] All `has_many`/`embeds_many` used in forms have `on_replace: :delete`
- [ ] `cast_assoc` used for nested user params, `put_assoc` for internal association changes

### Migration Review
- [ ] Every `references` call has an explicit `on_delete`
- [ ] No `:float` for monetary values
- [ ] Indexes added with `concurrently: true` if table has data
- [ ] No column removes or renames without a two-step deploy plan

### Query Review
- [ ] All external values are pinned with `^`
- [ ] No string interpolation in `fragment` or `Repo.query`
- [ ] No N+1 patterns (manual association queries inside `Enum.map`)
- [ ] Optional filters use `dynamic/2`

### Concurrency Review
- [ ] Get-or-create flows use `on_conflict` / `conflict_target`
- [ ] Position/sequence inserts are protected by a lock or transaction
- [ ] Related multi-table writes use `Ecto.Multi`
- [ ] `optimistic_lock/3` used where concurrent user edits are possible

## 5. Routing

- **Phoenix forms using changesets** -> load `phoenix-forms`
- **Testing Ecto code** -> load `testing`
- **LiveView streams displaying query results** -> load `liveview-streams`
- **Background jobs that write to DB** -> load `oban`
- **Performance of queries** -> load `observability`
