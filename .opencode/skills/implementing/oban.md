---
name: oban
description: >
  Oban background job workers. ALWAYS use when writing or modifying Oban workers,
  queue configuration, or job scheduling. For OTP process design → load otp.
  For Ecto persistence patterns → load ecto.
---

# Oban Worker Patterns

Oban runs background jobs in PostgreSQL-backed queues. Jobs are serialized to JSON,
retried on failure, and must survive crashes, restarts, and duplicate execution.
Every worker must be idempotent and use string-keyed args.

## 1. Rules

1. **Workers must be idempotent** -- Oban retries failed jobs. Side effects (inserts, emails, API calls) must be safe to repeat.
2. **Use string keys in args, never atoms** -- JSON serialization converts atoms to strings; atom keys cause match failures after round-trip.
3. **Store IDs, never structs** -- Structs cannot survive JSON serialization. Store identifiers and re-fetch in `perform/1`.
4. **Keep args small** -- Args are stored as JSONB in PostgreSQL. Large payloads bloat the `oban_jobs` table and slow queries.
5. **Handle all return values explicitly** -- `:ok`, `{:ok, _}`, `{:error, _}`, `{:cancel, _}`, `{:snooze, n}` each have different retry semantics.
6. **Use unique constraints for deduplication** -- Prevent duplicate jobs at insert time rather than handling duplicates in the worker.
7. **Always annotate `perform/1` with `@impl Oban.Worker`** (or `@impl true`).
8. **Size queues to real throughput limits** -- CPU-heavy and rate-limited work needs lower concurrency than default.
9. **Use `{:cancel, reason}` for permanent failures** -- Distinguishes "never retry" from "retry later" errors.
10. **Test workers with `Oban.Testing`** -- Use `perform_job/3` in tests, not direct `perform/1` calls.

## 2. Decision Table

| Intent / Situation | Use | Avoid | Why |
|---|---|---|---|
| Prevent duplicate side effects on retry | Check-before-act guard (`unless already_done?`) | Bare insert/send without guard | Retries re-execute the entire `perform/1` body |
| Pass data to a worker | `%{"user_id" => user.id}` (string keys, IDs) | `%{user: user}` (atom keys, structs) | JSON round-trip loses atom keys and struct metadata |
| Large file/payload processing | Store in S3/disk, pass `%{"file_path" => path}` | `%{"content" => Base.encode64(bytes)}` | JSONB payloads bloat `oban_jobs` and slow queue queries |
| Prevent same job from being enqueued twice | `unique: [period: 60, fields: [:args, :worker]]` | Manual DB check before insert | Built-in uniqueness is atomic and race-free |
| Permanent failure (bad data) | `{:cancel, "invalid recipient"}` | `{:error, "invalid recipient"}` | `{:error, _}` triggers retry; `{:cancel, _}` stops permanently |
| Transient failure (API timeout) | `{:error, reason}` (let Oban retry) | `{:cancel, _}` or swallowing the error | Transient errors should retry with backoff |
| Retry after a specific delay | `{:snooze, 300}` (seconds) | `Process.sleep` inside worker | Snooze frees the queue slot; sleep blocks it |
| Rate-limited external API | Dedicated queue with low concurrency (2-5) | Default queue with concurrency 10+ | Overwhelming the API causes cascading failures |
| CPU-intensive processing | Dedicated queue: `queue: :media, max_attempts: 1` | Sharing the default queue | CPU work blocks other jobs; usually not retryable |
| Email delivery | Dedicated `:mailer` queue, concurrency 5 | Default queue | Isolates email throughput from other work |
| LLM/AI API calls | Dedicated `:ai` queue, concurrency 2-3 | High concurrency queues | API rate limits and cost control |
| Testing a worker | `Oban.Testing.perform_job(Worker, args)` | Calling `Worker.perform(%Oban.Job{args: args})` | `perform_job/3` validates args and simulates Oban runtime |
| Scheduling a future job | `MyWorker.new(args, scheduled_at: ~U[...])` | Manual `Process.send_after` | Oban persists the schedule; survives restarts |

## 3. Patterns

### 3.1 Non-Idempotent Worker

**Severity:** BLOCK

```elixir
# BAD -- creates duplicate notification on every retry
def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
  Accounts.create_welcome_notification(user_id)
  :ok
end

# GOOD -- check-before-act makes it idempotent
def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
  unless Notifications.welcome_sent?(user_id) do
    Accounts.create_welcome_notification(user_id)
  end
  :ok
end
```

**Why:** Oban retries jobs on failure (default 20 attempts). Without an idempotency guard, side effects multiply with each retry -- duplicate emails, duplicate records, duplicate charges.

### 3.2 Atom Keys in Args

**Severity:** BLOCK

```elixir
# BAD -- atom keys become strings after JSON round-trip
%{user_id: user_id, action: :welcome}
|> MyWorker.new()
|> Oban.insert()

# Pattern match will fail:
def perform(%Oban.Job{args: %{user_id: uid}}) do  # never matches

# GOOD -- string keys throughout
%{"user_id" => user_id, "action" => "welcome"}
|> MyWorker.new()
|> Oban.insert()

def perform(%Oban.Job{args: %{"user_id" => uid, "action" => action}}) do
  # ...
end
```

**Why:** Oban serializes args to JSON (PostgreSQL JSONB). JSON has no atom type. After deserialization, `%{user_id: 1}` becomes `%{"user_id" => 1}`, and pattern matches on atom keys silently fail.

### 3.3 Struct in Args

**Severity:** BLOCK

```elixir
# BAD -- struct metadata is lost in JSON
%{"user" => user, "quiz" => quiz}
|> MyWorker.new()

# GOOD -- store IDs, re-fetch in perform
%{"user_id" => user.id, "quiz_id" => quiz.id}
|> MyWorker.new()

@impl Oban.Worker
def perform(%Oban.Job{args: %{"user_id" => user_id, "quiz_id" => quiz_id}}) do
  user = Repo.get!(User, user_id)
  quiz = Repo.get!(Quiz, quiz_id)
  # ...
end
```

**Why:** Elixir structs serialize to plain maps in JSON, losing the `__struct__` key and any custom protocol implementations. Re-fetching ensures you work with the current state of the record.

### 3.4 Swallowing Errors

**Severity:** BLOCK

```elixir
# BAD -- always returns :ok, errors silently disappear
def perform(%Oban.Job{args: args}) do
  send_email(args)
  :ok  # what if send_email raised or returned {:error, _}?
end

# GOOD -- surface errors for retry, cancel permanent failures
@impl Oban.Worker
def perform(%Oban.Job{args: %{"email" => email}}) do
  case Mailer.deliver(email) do
    {:ok, _} -> :ok
    {:error, :invalid_recipient} -> {:cancel, "invalid recipient"}
    {:error, reason} -> {:error, reason}  # will retry
  end
end
```

**Why:** If `send_email/1` fails but the worker returns `:ok`, Oban marks the job as complete. The email is never sent and there is no retry. Explicit error handling ensures transient failures retry and permanent failures are recorded.

### 3.5 Large Payload in Args

**Severity:** WARN

```elixir
# BAD -- megabytes of data in JSONB
%{"file_content" => Base.encode64(file_bytes)}
|> MyWorker.new()

# GOOD -- reference to external storage
%{"file_path" => "uploads/abc123.pdf"}
|> MyWorker.new()
```

**Why:** Every `oban_jobs` row contains the full args. Large payloads cause table bloat, slow `INSERT`/`SELECT` queries, and increase memory usage during job processing.

### 3.6 Missing @impl Annotation

**Severity:** WARN

```elixir
# BAD -- no @impl; easy to miss callback typos
def perform(%Oban.Job{args: %{"id" => id}}) do
  # ...
end

# GOOD -- compiler warns if perform/1 is not a valid callback
@impl Oban.Worker
def perform(%Oban.Job{args: %{"id" => id}}) do
  # ...
end
```

**Why:** Without `@impl`, misspelling `perform` or using the wrong arity silently creates a dead function instead of raising a compile-time warning.

## 4. Checklist

- [ ] `@impl Oban.Worker` on `perform/1`
- [ ] All args use string keys (`"key"`, not `:key`)
- [ ] Args contain IDs/references, not structs or large blobs
- [ ] Side effects are idempotent (check-before-act or upsert)
- [ ] Return values are explicit: `:ok`, `{:error, _}`, `{:cancel, _}`
- [ ] Unique constraint configured if duplicate jobs are possible
- [ ] Queue concurrency matches the throughput profile (API rate limits, CPU bounds)
- [ ] Tests use `Oban.Testing.perform_job/3`

## 5. Routing

| If you need... | Load instead |
|---|---|
| OTP process design (GenServer, Supervisor) | `otp` |
| Ecto persistence patterns | `ecto` |
| Async LiveView data fetching | `liveview-async-state` |
| Performance / queue throughput tuning | `observability` |
| Quality checks before completing work | `quality-gates` |

## Queue Design Reference

| Queue | Use For | Concurrency | Notes |
|-------|---------|-------------|-------|
| `:default` | General tasks | 10 | Catch-all; keep fast |
| `:mailer` | Email delivery | 5 | Isolate from main queue |
| `:ai` | LLM API calls | 2-3 | Rate-limited, expensive |
| `:media` | Image/video processing | 2 | CPU-heavy, long-running |
| `:webhooks` | Outbound webhook delivery | 5 | External API tolerance |
| `:imports` | Data import/ETL | 1-2 | Memory-heavy, sequential |

## Return Value Reference

| Return | Oban Behavior |
|--------|---------------|
| `:ok` | Job marked complete |
| `{:ok, value}` | Job marked complete (value ignored) |
| `{:error, reason}` | Job marked failed, will retry (up to `max_attempts`) |
| `{:cancel, reason}` | Job cancelled permanently, no retry |
| `{:snooze, seconds}` | Job rescheduled, attempt count unchanged |
| Unhandled exception | Job marked failed with stacktrace, will retry |
