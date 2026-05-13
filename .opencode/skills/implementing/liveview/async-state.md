# LiveView Async State

> Depth file for [liveview/SKILL.md](SKILL.md). Load the parent skill first.

## 1. Rules

1. ALWAYS use `start_async/3` or `assign_async/3` instead of hand-rolled `Task.start/1` + `handle_info` for async work in LiveViews.
2. ALWAYS initialize loading/error/result assigns before starting async work.
3. ALWAYS track request IDs when later results can stale out earlier ones.
4. ALWAYS keep URL-derived state in `handle_params/3` -- keep expensive fetching behind async boundaries.
5. NEVER start async work in disconnected mount -- guard with `connected?(socket)`.
6. NEVER capture the entire socket or assigns map in async closures -- extract only needed fields.
7. ALWAYS handle both `{:ok, result}` and `{:exit, reason}` in `handle_async/3`.
8. ALWAYS centralize polling state and stop scheduling once terminal.

## 2. Decision Table

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Load data on mount with loading/error UI | `assign_async/3` | Blocking call in mount | Built-in `<.async_result>` template |
| User-triggered async (control over continuation) | `start_async/3` + `handle_async/3` | `Task.async` in handle_event | Supervised, lifecycle-aware |
| Async load into a stream | `start_async/3` + `stream(..., reset: true)` in callback | `assign_async` | assign_async doesn't support streams |
| Multiple independent async loads | Multiple `assign_async` calls | Single blocking function | Independent loading states |
| Fire-and-forget side effect | `Task.Supervisor.start_child/2` | `start_async` | LV doesn't need the result |
| Debounced search with stale protection | `start_async` + request ID tracking | Bare Task.start | Discards stale results |
| Poll external system | `Process.send_after` in `handle_info` with stop condition | Unbounded `send_after` loop | Terminal state stops polling |

## 3. Patterns

### Blocking the Socket Process

**Severity: BLOCK** | **Why: All events from this user queue until the blocking call returns -- multi-second blocks look like LV death**

```elixir
# BAD
def handle_event("fetch_report", %{"id" => id}, socket) do
  {:ok, %{body: data}} = Req.get!("https://api.example.com/reports/#{id}")
  {:noreply, assign(socket, :report, data)}
end

# GOOD
def handle_event("fetch_report", %{"id" => id}, socket) do
  {:noreply, start_async(socket, :fetch_report, fn ->
    Req.get!("https://api.example.com/reports/#{id}")
  end)}
end

def handle_async(:fetch_report, {:ok, %{body: data}}, socket) do
  {:noreply, assign(socket, :report, data)}
end

def handle_async(:fetch_report, {:exit, reason}, socket) do
  {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
end
```

### Capturing Socket in Closure

**Severity: WARN** | **Why: Copies entire assigns map into spawned process memory**

```elixir
# BAD
{:noreply, start_async(socket, :fetch, fn -> process(socket.assigns) end)}

# GOOD
user_id = socket.assigns.current_user.id
{:noreply, start_async(socket, :fetch, fn -> process(user_id) end)}
```

### Hand-Rolled Task Without Ownership

**Severity: WARN** | **Why: Task.start/1 has no supervision, no cancellation, no lifecycle awareness**

```elixir
# BAD
def handle_event("search", %{"q" => q}, socket) do
  Task.start(fn ->
    results = Search.run(q)
    send(socket.transport_pid, {:search_results, results})  # Wrong PID!
  end)
  {:noreply, socket}
end

# GOOD
def handle_event("search", %{"q" => q}, socket) do
  {:noreply, start_async(socket, :search, fn -> Search.run(q) end)}
end

def handle_async(:search, {:ok, results}, socket) do
  {:noreply, assign(socket, results: results)}
end
```

### Stale Response Overwrites Fresh

**Severity: WARN** | **Why: Slow request 1 returns after fast request 2 -- old results overwrite new**

```elixir
# BAD - no stale protection
def handle_event("search", %{"q" => q}, socket) do
  {:noreply, start_async(socket, :search, fn -> Search.run(q) end)}
end

def handle_async(:search, {:ok, results}, socket) do
  {:noreply, assign(socket, results: results)}  # May be stale!
end

# GOOD - keyed async discards stale results
def handle_event("search", %{"q" => q}, socket) do
  {:noreply,
   socket
   |> assign(:loading, true)
   |> start_async({:search, q}, fn -> Search.run(q) end)}
end

def handle_async({:search, _q}, {:ok, results}, socket) do
  {:noreply, assign(socket, results: results, loading: false)}
end
```

When using a keyed tuple like `{:search, q}`, `start_async` automatically cancels the previous async with the same key shape. For manual tracking:

```elixir
def handle_event("search", %{"q" => q}, socket) do
  request_id = System.unique_integer([:positive])
  {:noreply,
   socket
   |> assign(:search_request_id, request_id)
   |> assign(:searching?, true)
   |> start_async(:search, fn -> {request_id, Search.run(q)} end)}
end

def handle_async(:search, {:ok, {request_id, results}}, socket) do
  if request_id == socket.assigns.search_request_id do
    {:noreply, assign(socket, results: results, searching?: false)}
  else
    {:noreply, socket}  # Stale, discard
  end
end
```

### Async Work in Disconnected Mount

**Severity: WARN** | **Why: HTTP phase mount triggers async that completes after the static render is gone**

```elixir
# BAD
def mount(_, _, socket) do
  {:ok, assign_async(socket, :data, fn -> {:ok, %{data: load()}} end)}
end

# GOOD
def mount(_, _, socket) do
  socket = assign(socket, data: nil, loading: true)
  if connected?(socket) do
    {:ok, assign_async(socket, :data, fn -> {:ok, %{data: load()}} end)}
  else
    {:ok, socket}
  end
end
```

### Unbounded Polling

**Severity: WARN** | **Why: Polling continues forever even after terminal state -- wastes resources**

```elixir
# BAD - never stops
def handle_info(:poll, socket) do
  status = ExternalAPI.check_status(socket.assigns.job_id)
  Process.send_after(self(), :poll, 5_000)
  {:noreply, assign(socket, status: status)}
end

# GOOD - stops on terminal state
def handle_info(:poll, socket) do
  status = ExternalAPI.check_status(socket.assigns.job_id)
  unless status in [:completed, :failed] do
    Process.send_after(self(), :poll, 5_000)
  end
  {:noreply, assign(socket, status: status)}
end
```

## 4. Async as Continuation-Passing Style (CPS)

LiveView's async API is continuation-passing style adapted to the process lifecycle:

- **`start_async(socket, name, fn -> work end)`** -- kicks off work in a supervised Task
- **`handle_async(name, result, socket)`** -- IS the continuation that receives the result

The same shape underlies `assign_async/3`:

```elixir
# assign_async packages CPS with built-in loading/error UI
assign_async(socket, :stats, fn -> {:ok, %{stats: load_stats()}} end)
```

```heex
<.async_result :let={stats} assign={@stats}>
  <:loading>Loading stats...</:loading>
  <:failed :let={reason}>Error: {inspect(reason)}</:failed>
  <p>Total: {stats.total}</p>
</.async_result>
```

**Why CPS matters:** A LiveView is a long-lived process. Every callback runs serially. If a callback blocks for 2 seconds, every other event queues. The CPS pattern keeps the main event loop free.

## 5. Combining Async with Streams

`assign_async` doesn't support streams directly. Use `start_async` with `stream(..., reset: true)`:

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:loading, true)
   |> stream(:notes, [])
   |> start_async(:load_notes, fn -> Notes.list_all() end)}
end

def handle_async(:load_notes, {:ok, notes}, socket) do
  {:noreply,
   socket
   |> assign(:loading, false)
   |> stream(:notes, notes, reset: true)}
end

def handle_async(:load_notes, {:exit, reason}, socket) do
  {:noreply,
   socket
   |> assign(:loading, false)
   |> put_flash(:error, "Failed to load notes")}
end
```

## 6. When Polling Is Acceptable

Use polling only when:
- External system has no callback/webhook channel
- Short-lived status checks with explicit stop conditions
- Low frequency (5s+ intervals)

Always:
- Centralize polling state in a single assign
- Stop scheduling once terminal state is reached
- Guard initial scheduling with `connected?(socket)`

## 7. Checklist

- [ ] Blocking operations use `start_async/3` or `assign_async/3`
- [ ] Loading/error assigns initialized before async starts
- [ ] Async closures capture only needed fields, not socket/assigns
- [ ] `handle_async/3` handles both `{:ok, _}` and `{:exit, _}`
- [ ] Overlapping requests protected against stale results (keyed async or request IDs)
- [ ] Async work guarded by `connected?(socket)` in mount
- [ ] Polling has explicit stop condition
- [ ] `<.async_result>` template used for assign_async (loading + failed slots)
