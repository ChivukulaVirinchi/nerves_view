---
name: liveview
description: >
  Phoenix LiveView patterns. ALWAYS use when working with LiveView modules, components,
  forms, streams, async, hooks, or JS commands. For Phoenix controllers/plugs → load phoenix.
---

# LiveView

## Subskills

| File | Scope |
|------|-------|
| [lifecycle.md](lifecycle.md) | Mount phases, handle_params, connected? guards, assign initialization |
| [streams.md](streams.md) | Stream operations, reset, filtering, empty states, async streams |
| [components.md](components.md) | Function components vs LiveComponents vs hooks, state ownership, APIs |
| [async-state.md](async-state.md) | start_async, assign_async, stale response guards, polling |
| [optimistic-ui.md](optimistic-ui.md) | JS commands, loading states, optimistic inserts, undo, error recovery |
| [reference.md](reference.md) | Callback signatures, JS commands, form bindings, upload options, test helpers |
| [examples.md](examples.md) | Full LiveView examples, modal, search, nested forms, SortableJS, uploads |
| [alpine.md](alpine.md) | Alpine.js directives, stores, LiveView integration rules |
| [state-persistence.md](state-persistence.md) | Browser storage hooks, Phoenix.Token encryption, connect params |
| [wire-protocol.md](wire-protocol.md) | WebSocket framing, diff format, binary upload protocol |
| [wasm.md](wasm.md) | WebAssembly integration with LiveView hooks |

## 1. Rules

1. ALWAYS use `connected?(socket)` guard before subscribing to PubSub or starting expensive work in `mount/3` -- mount runs twice (HTTP + WebSocket).
2. ALWAYS initialize ALL assigns in mount before any conditional logic -- static render crashes with KeyError otherwise.
3. ALWAYS use streams for lists of database records -- never store large collections in assigns.
4. ALWAYS use `assign_async/3` or `start_async/3` for blocking operations -- never block the socket process.
5. ALWAYS use `@impl true` on all LiveView callbacks.
6. ALWAYS use `phx-disable-with` on submit buttons to prevent double-submission.
7. ALWAYS use `push_navigate/2` and `push_patch/2` -- never use deprecated `live_redirect/2` or `live_patch/2`.
8. ALWAYS preload associations in the parent LiveView -- never query the database inside `render/1`.
9. ALWAYS use `<.input field={@form[:field]} />` for form fields -- never access `@changeset` directly in templates.
10. ALWAYS use `phx-update="stream"` with a unique `id` on the container and `id={dom_id}` on each item.
11. ALWAYS pass data to LiveComponents via assigns, communicate back via `send/2` or callback assigns.
12. NEVER copy large data structures (full socket, assigns map) into spawned processes -- extract only needed fields.
13. NEVER use `Process.sleep` in tests -- use `assert_receive`, `render_async/1`, or `eventually` patterns.

## 2. Decision Tables

### Which Component Type?

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Reusable stateless UI | Function component | LiveComponent | No process overhead, simpler |
| Encapsulated state + events | LiveComponent with `id` | Function component with assigns hack | Proper isolation |
| Independent process surviving navigation | `live_render` with `sticky: true` | LiveComponent | Separate process, survives remount |
| Just organize code into modules | Function component (extract module) | LiveComponent | Don't pay for state you don't need |
| Batch-load data for list items | LiveComponent with `update_many/1` | N+1 queries in function components | Single batch query |

### Which Async Pattern?

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Load data on mount with loading/error UI | `assign_async/3` | Blocking call in mount | Built-in `<.async_result>` template |
| User-triggered async operation | `start_async/3` + `handle_async/3` | `Task.async` in handle_event | Supervised, lifecycle-aware |
| Async load into a stream | `start_async/3` + `stream(..., reset: true)` | `assign_async` | assign_async doesn't support streams |
| Multiple independent async loads | Multiple `assign_async` calls | Single blocking function | Independent loading states |
| Fire-and-forget side effect | `Task.Supervisor.start_child/2` | `start_async` | LV doesn't need the result |

### Which Navigation?

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Go to a different LiveView | `push_navigate/2` / `<.link navigate={}>` | `push_patch` (only same LV) | Full remount |
| Stay in same LV, change params | `push_patch/2` / `<.link patch={}>` | `push_navigate` (remounts) | Triggers handle_params only |
| Full page load (non-LiveView) | `<.link href={}>` | `navigate` or `patch` | Traditional HTTP request |
| Redirect after form to controller | `redirect(socket, to: path)` | `push_navigate` | Controller needs conn |

### Which Form Pattern?

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Standard CRUD form | `to_form(changeset)` + `phx-change` + `phx-submit` | Direct changeset in template | Standard LiveView form flow |
| Nested associations | `inputs_for` with `cast_assoc` + sort/drop params | Manual field management | Built-in add/remove/reorder |
| Independent editable items | Stream of forms (dynamic forms) | `inputs_for` | Per-item validation and save |
| URL-synced filters | `push_patch` in handler, load in `handle_params` | Assign in handle_event | Shareable URLs, back button works |

## 3. Patterns

### Missing Assign Initialization

**Severity: BLOCK** | **Why: Static render crashes with KeyError when assign not set for both phases**

```elixir
# BAD
def mount(_params, _session, socket) do
  if connected?(socket) do
    {:ok, assign(socket, items: Context.list_items())}
  else
    {:ok, socket}  # No :items assign -- template crashes
  end
end

# GOOD
def mount(_params, _session, socket) do
  socket = assign(socket, items: [], loading: true)
  socket = if connected?(socket),
    do: assign(socket, items: Context.list_items(), loading: false),
    else: socket
  {:ok, socket}
end
```

### PubSub Without connected? Guard

**Severity: BLOCK** | **Why: Subscribes during HTTP render too -- mount runs twice**

```elixir
# BAD
def mount(_, _, socket) do
  Phoenix.PubSub.subscribe(MyApp.PubSub, "topic")
  {:ok, socket}
end

# GOOD
def mount(_, _, socket) do
  if connected?(socket), do: Phoenix.PubSub.subscribe(MyApp.PubSub, "topic")
  {:ok, socket}
end
```

### Blocking the Socket Process

**Severity: BLOCK** | **Why: All events from this user queue until blocking call returns**

```elixir
# BAD
def handle_event("fetch", _, socket) do
  data = HTTPClient.get!(url)
  {:noreply, assign(socket, data: data)}
end

# GOOD
def handle_event("fetch", _, socket) do
  {:noreply, start_async(socket, :fetch, fn -> HTTPClient.get!(url) end)}
end

def handle_async(:fetch, {:ok, data}, socket) do
  {:noreply, assign(socket, data: data)}
end
```

### Large Collections in Assigns

**Severity: BLOCK** | **Why: Entire list held in process memory, grows unbounded**

```elixir
# BAD
{:ok, assign(socket, items: Repo.all(Item))}

# GOOD
{:ok, stream(socket, :items, Repo.all(Item))}
```

### Copying Socket into Async Closure

**Severity: WARN** | **Why: Captures entire assigns map into spawned process memory**

```elixir
# BAD
{:noreply, start_async(socket, :fetch, fn -> process(socket.assigns) end)}

# GOOD
user_id = socket.assigns.current_user.id
{:noreply, start_async(socket, :fetch, fn -> process(user_id) end)}
```

### Trusting Client-Submitted IDs

**Severity: BLOCK** | **Why: Client can forge hidden field values -- use server assigns for identity**

```elixir
# BAD
def handle_event("leave", %{"user_id" => user_id}, socket) do
  Teams.remove_member(user_id)
end

# GOOD
def handle_event("leave", _params, socket) do
  Teams.remove_member(socket.assigns.current_user.id)
end
```

### N+1 in Components

**Severity: WARN** | **Why: Each component render fires a separate query**

```elixir
# BAD
def render(assigns) do
  user = Repo.get!(User, assigns.user_id)  # N+1!
  ...
end

# GOOD - preload in parent
users = User |> preload(:department) |> Repo.all()
```

### Stream Without Proper IDs

**Severity: WARN** | **Why: LiveView can't track items for efficient diffing**

```heex
<%!-- BAD --%>
<div phx-update="stream">
  <div :for={{_id, item} <- @streams.items}>{item.name}</div>
</div>

<%!-- GOOD --%>
<div id="items" phx-update="stream">
  <div :for={{dom_id, item} <- @streams.items} id={dom_id}>{item.name}</div>
</div>
```

### Full Re-Query on Every PubSub Message

**Severity: WARN** | **Why: Expensive query on every broadcast -- use granular updates**

```elixir
# BAD
def handle_info(:update_workspace, socket) do
  workspace = Teams.get_full_workspace!(socket.assigns.team_id)
  {:noreply, assign(socket, workspace: workspace)}
end

# GOOD
def handle_info({:note_created, note}, socket) do
  {:noreply, stream_insert(socket, :notes, note)}
end
```

### Deprecated Navigation Functions

**Severity: WARN** | **Why: `live_redirect`/`live_patch` are deprecated in favor of push_ functions**

```elixir
# BAD
live_redirect(socket, to: path)
live_patch(socket, to: path)

# GOOD
push_navigate(socket, to: path)
push_patch(socket, to: path)
```

### No Loading Feedback

**Severity: SUGGEST** | **Why: User has no indication action was received**

```heex
<%!-- BAD --%>
<button phx-click="save">Save</button>

<%!-- GOOD --%>
<button phx-click="save" phx-disable-with="Saving...">Save</button>
```

### Form Deprecations

**Severity: WARN** | **Why: `let={f}` and direct changeset access are deprecated**

```elixir
# BAD
<.form for={@form} let={f}>
<%= @changeset.errors %>

# GOOD
<.input field={@form[:email]} />
<%= for error <- @form[:email].errors do %>
```

## 4. Checklist

### Before Every LiveView
- [ ] All assigns initialized in mount before conditional logic
- [ ] `connected?(socket)` guards PubSub subscriptions and async work
- [ ] Collections use streams, not plain assigns
- [ ] Blocking work uses `start_async/3` or `assign_async/3`
- [ ] `@impl true` on all callbacks

### Forms
- [ ] Changeset wrapped with `to_form()`
- [ ] Fields accessed as `@form[:field]`
- [ ] `phx-change` handler present (enables auto-recovery on reconnect)
- [ ] Submit button has `phx-disable-with`
- [ ] Form has stable, unique `id`

### Streams
- [ ] Container has `id` and `phx-update="stream"`
- [ ] Each item has `id={dom_id}`
- [ ] Filtering uses `stream(socket, :items, filtered, reset: true)`
- [ ] No `Enum` operations on streams (not enumerable)

### Security
- [ ] No client-submitted IDs used for authorization
- [ ] Server assigns used for current user identity
- [ ] Associations preloaded in parent, never in render

### Testing
- [ ] No `Process.sleep` -- use `render_async/1` or `assert_receive`
- [ ] Form tests cover both `render_change` (validation) and `render_submit`
- [ ] Async paths tested for loading, success, and failure states

## Lifecycle Overview

```
HTTP GET -> mount/3 -> render/1 -> HTML response
               |
WebSocket -> mount/3 -> handle_params/3 -> render/1
                              |
         User Event -> handle_event/3 -> render/1
                              |
        Process Msg -> handle_info/2 -> render/1
                              |
         Async Done -> handle_async/3 -> render/1
```

**Key:** mount runs twice. First call (HTTP) serves initial HTML. Second call (WebSocket) establishes the persistent connection. All assigns must exist for both phases.

### on_mount Hooks

Shared setup across LiveViews for auth, assigns, telemetry. Returns `{:cont, socket}` to continue or `{:halt, socket}` to stop. Runs before `mount/3`.

```elixir
live_session :authenticated, on_mount: [{MyAppWeb.UserAuth, :require_authenticated}] do
  live "/dashboard", DashboardLive
end
```

### Async as Continuation-Passing Style

`start_async/3` kicks off work in a supervised Task. `handle_async/3` IS the continuation -- "the rest of the computation" that receives the result. This keeps the LiveView's main event loop free while slow work runs concurrently.

```elixir
# assign_async -- built-in loading/error UI
assign_async(socket, :stats, fn -> {:ok, %{stats: load_stats()}} end)

# Template
<.async_result :let={stats} assign={@stats}>
  <:loading>Loading...</:loading>
  <:failed :let={reason}>Error: {inspect(reason)}</:failed>
  <p>Total: {stats.total}</p>
</.async_result>
```

## Forms

### Complete Form Flow

```elixir
def mount(_params, _session, socket) do
  changeset = Accounts.change_user(%User{})
  {:ok, assign(socket, form: to_form(changeset))}
end

def handle_event("validate", %{"user" => params}, socket) do
  changeset = %User{} |> User.changeset(params) |> Map.put(:action, :validate)
  {:noreply, assign(socket, form: to_form(changeset))}
end

def handle_event("save", %{"user" => params}, socket) do
  case Accounts.create_user(params) do
    {:ok, user} ->
      {:noreply, socket |> put_flash(:info, "Created!") |> push_navigate(to: ~p"/users/#{user}")}
    {:error, changeset} ->
      {:noreply, assign(socket, form: to_form(changeset))}
  end
end
```

### Form Template

```heex
<.form for={@form} phx-change="validate" phx-submit="save">
  <.input field={@form[:name]} type="text" label="Name" />
  <.input field={@form[:email]} type="email" label="Email" />
  <.button phx-disable-with="Saving...">Save</.button>
</.form>
```

## Navigation

### push_navigate vs push_patch

- `push_navigate` -- different LiveView, full remount
- `push_patch` -- same LiveView, triggers `handle_params` only

### URL-Synced Forms (Persistent Filters)

```elixir
def handle_params(params, _uri, socket) do
  filters = Map.take(params, ["title", "status"])
  {:noreply,
   socket
   |> assign(:form, to_form(filters, as: "filters"))
   |> assign(:posts, Posts.search(filters))}
end

def handle_event("filter", %{"filters" => filters}, socket) do
  params = Map.reject(filters, fn {_k, v} -> v == "" end)
  {:noreply, push_patch(socket, to: ~p"/posts?#{params}")}
end
```

## JS Commands

Client-side operations without server roundtrip:

```elixir
JS.show(to: selector) | JS.hide(to: selector) | JS.toggle(to: selector)
JS.add_class("x", to: sel) | JS.remove_class("x", to: sel) | JS.toggle_class("x", to: sel)
JS.set_attribute({"aria-expanded", "true"}, to: sel)
JS.toggle_attribute({"aria-expanded", "true", "false"}, to: sel)
JS.push("event", value: %{}) | JS.navigate(~p"/path") | JS.patch(~p"/path")
JS.focus(to: sel) | JS.focus_first(to: sel) | JS.push_focus() | JS.pop_focus()
```

Commands compose with `|>`:
```elixir
JS.push("close") |> JS.hide(to: "#modal") |> JS.pop_focus()
```

## Hooks (JS Interop)

```javascript
Hooks.InfiniteScroll = {
  mounted() {
    this.observer = new IntersectionObserver(entries => {
      if (entries[0].isIntersecting) this.pushEvent("load_more", {})
    })
    this.observer.observe(this.el)
  },
  destroyed() { this.observer.disconnect() }
}
```

Hook lifecycle: `mounted()`, `updated()`, `destroyed()`, `disconnected()`, `reconnected()`.

When a hook manages its own DOM, use `phx-update="ignore"` to prevent LiveView from overwriting it.

## PubSub Integration

```elixir
def mount(_, _, socket) do
  if connected?(socket), do: Phoenix.PubSub.subscribe(MyApp.PubSub, "posts")
  {:ok, stream(socket, :posts, Posts.list())}
end

def handle_info({:post_created, post}, socket) do
  {:noreply, stream_insert(socket, :posts, post, at: 0)}
end
```

## File Uploads

```elixir
allow_upload(:avatar, accept: ~w(.jpg .jpeg .png), max_entries: 1, max_file_size: 5_000_000)
```

```heex
<.live_file_input upload={@uploads.avatar} />
<.live_img_preview entry={entry} />
```

For external uploads (S3), streaming uploads, and programmatic uploads, see [examples.md](examples.md).

## Testing

```elixir
{:ok, view, html} = live(conn, ~p"/users")
assert html =~ user.name
assert has_element?(view, "#user-#{user.id}")

# Form testing
view |> form("#user-form", user: %{name: ""}) |> render_change() =~ "can't be blank"
view |> form("#user-form", user: valid_attrs) |> render_submit() |> follow_redirect(conn)

# Async testing
assert render_async(view) =~ "Data loaded"
```

## Related Skills

- **phoenix** -- Controllers, plugs, contexts, channels, PubSub, routing, security
- **elixir-planning / elixir-implementing / elixir-reviewing** -- Phase skills
