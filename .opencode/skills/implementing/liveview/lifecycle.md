# LiveView Lifecycle

> Depth file for [liveview/SKILL.md](SKILL.md). Load the parent skill first.

## 1. Rules

1. ALWAYS initialize ALL assigns in mount before any conditional logic -- static render crashes with KeyError otherwise.
2. ALWAYS use `connected?(socket)` guard before PubSub subscriptions, `send(self(), ...)`, `Process.send_after`, or `start_async`.
3. ALWAYS handle the "loading" state in templates -- assigns exist but data is not yet loaded.
4. ALWAYS wrap `render/1` content in the appropriate layout shell (`<Layouts.app>` or your app shell component).
5. NEVER start side effects in disconnected mount -- they run twice and the first set is wasted.
6. ALWAYS use `handle_params/3` for URL-dependent state -- it runs after mount AND on every patch navigation.
7. ALWAYS use `assign_new/3` in on_mount hooks to avoid re-fetching on `push_patch` within the same live_session.

## 2. Decision Table

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Initialize all assigns | Top of `mount/3`, before any `if` | Inside conditional branches | Static render needs every assign |
| Subscribe to PubSub | Inside `if connected?(socket)` | Bare in mount body | Mount runs twice; HTTP phase subscription is wasted |
| Load data on mount | `assign_async/3` or `send(self(), :load)` guarded by `connected?` | Blocking call in mount | Keeps HTTP render fast |
| Set page title from URL param | `handle_params/3` | `mount/3` | handle_params runs on patch too |
| Auth guard across LiveViews | `on_mount` hook in `live_session` | Duplicating auth in each mount | Single source of truth |
| Pass data from session to LV | `on_mount` with `assign_new/3` | Re-fetching in every mount | Survives push_patch |
| Mutate session (set tenant, login) | Controller POST then redirect to LiveView | LiveView handle_event | LV can't mutate session |

## 3. Patterns

### Missing Assign in Static Render

**Severity: BLOCK** | **Why: Template accesses `@items` during HTTP render -- KeyError crash**

```elixir
# BAD
def mount(_params, _session, socket) do
  if connected?(socket) do
    {:ok, assign(socket, items: Context.list_items())}
  else
    {:ok, socket}  # No :items assign
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

### Side Effects Running Twice

**Severity: BLOCK** | **Why: `send(self(), :load_data)` fires in HTTP phase too -- wasted work or duplicate messages**

```elixir
# BAD
def mount(_, _, socket) do
  send(self(), :load_data)  # Runs twice!
  {:ok, socket}
end

# GOOD
def mount(_, _, socket) do
  if connected?(socket), do: send(self(), :load_data)
  {:ok, assign(socket, data: nil, loading: true)}
end
```

### Render Without Layout Shell

**Severity: WARN** | **Why: Page renders as raw content with no header, navigation, or app chrome**

```elixir
# BAD
def render(assigns) do
  ~H"""
  <div class="space-y-4">
    <h1>My Page</h1>
  </div>
  """
end

# GOOD
def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash} current_scope={@current_scope}>
    <div class="space-y-4">
      <h1>My Page</h1>
    </div>
  </Layouts.app>
  """
end
```

### Re-Fetching on Every Patch

**Severity: SUGGEST** | **Why: `assign_new` skips fetch if key already exists in socket**

```elixir
# BAD - re-fetches user on every push_patch
def on_mount(:mount_current_scope, _params, session, socket) do
  user = Accounts.get_user_by_session_token(session["user_token"])
  {:cont, assign(socket, :current_scope, Scope.for_user(user))}
end

# GOOD - assign_new skips if already set
def on_mount(:mount_current_scope, _params, session, socket) do
  {:cont, assign_new(socket, :current_scope, fn ->
    if token = session["user_token"] do
      {user, _} = Accounts.get_user_by_session_token(token)
      Scope.for_user(user)
    end || Scope.for_user(nil)
  end)}
end
```

## 4. Lifecycle Flow

```
HTTP GET -> mount/3 (connected? = false) -> render/1 -> HTML response
                         |
WebSocket -> mount/3 (connected? = true) -> handle_params/3 -> render/1
                                                   |
                        User Event -> handle_event/3 -> render/1
                                                   |
                       Process Msg -> handle_info/2 -> render/1
                                                   |
                        Async Done -> handle_async/3 -> render/1
```

### Callback Ordering

1. `on_mount` hooks (in order specified in `live_session`)
2. `mount/3`
3. `handle_params/3` (WebSocket phase only, also on every `push_patch`)
4. `render/1`
5. `handle_event/3` / `handle_info/2` / `handle_async/3` (event loop)

### on_mount Hook Pattern

```elixir
defmodule MyAppWeb.UserAuth do
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)
    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      {:halt, socket |> put_flash(:error, "You must log in") |> redirect(to: ~p"/users/log-in")}
    end
  end
end
```

### Two-Tier live_session (User + Tenant)

For multi-tenant apps, separate live_sessions for user-level and tenant-level auth. Crossing sessions forces a full page reload, clearing stale assigns:

```elixir
# User-level: authenticated but no team selected
live_session :authenticated, on_mount: [{UserAuth, :ensure_authenticated}] do
  live "/teams", TeamsLive
end

# Tenant-level: authenticated AND team member
live_session :tenant, on_mount: [{UserAuth, :ensure_authenticated}, {TeamAuth, :ensure_member}] do
  live "/workspace", WorkspaceLive
end
```

### Controller-to-LiveView Handoff

LiveView can't mutate the session. Use a controller POST to set session, then redirect:

```elixir
# Controller
def select_team(conn, %{"team_id" => team_id}) do
  conn |> put_session(:team_id, team_id) |> redirect(to: ~p"/workspace")
end

# LiveView on_mount reads from session
def on_mount(:load_team, _params, %{"team_id" => team_id}, socket) do
  {:cont, assign(socket, :team, Teams.get_team!(team_id))}
end
```

## 5. handle_params

Called after mount and on every `push_patch` navigation:

```elixir
def handle_params(%{"id" => id}, _uri, socket) do
  item = Context.get_item!(id)
  {:noreply, assign(socket, item: item, page_title: item.title)}
end

def handle_params(params, _uri, socket) do
  page = String.to_integer(params["page"] || "1")
  {:noreply, socket |> assign(:page, page) |> load_data()}
end
```

**Key:** All params have STRING keys. Always parse/validate before use.

## 6. Layout Shell Reference

| Page Type | Shell | Mode |
|-----------|-------|------|
| Login, register, public | `<Layouts.app>` | Default or `wide={true}` |
| Dashboard, listings | App shell component | `:wide` |
| Reading / content | App shell component | `:reading` |
| Fullscreen / exercises | App shell component | `:fullscreen` |

## 7. Checklist

- [ ] All assigns initialized in mount before conditional logic
- [ ] `connected?(socket)` guards all side effects
- [ ] `handle_params` used for URL-dependent state (not mount)
- [ ] `assign_new` used in on_mount hooks to avoid re-fetching
- [ ] Template handles loading state (data not yet loaded)
- [ ] `render/1` wraps content in layout shell
- [ ] `@impl true` on all callbacks
