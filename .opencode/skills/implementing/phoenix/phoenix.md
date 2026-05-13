---
name: phoenix
description: >
  Phoenix framework patterns. ALWAYS use when working with Phoenix controllers, plugs,
  routing, channels, or deployment. For LiveView → load liveview.
---

# Phoenix

## Subskills

| File | Scope |
|------|-------|
| [reference.md](reference.md) | Plug.Conn functions, router DSL, generator field types, channel patterns, component attribute types |
| [examples.md](examples.md) | Complete plug examples, context module template, channel implementation, controller examples |

## 1. Rules

1. ALWAYS use contexts for business logic -- never access Repo directly from controllers or LiveViews.
2. ALWAYS use `to_form()` and `@form[:field]` for forms -- never access changesets directly in templates.
3. ALWAYS use verified routes `~p"/path"` -- never string-concatenate paths.
4. ALWAYS preload associations before rendering -- never trigger lazy loads in templates.
5. ALWAYS use action-specific changesets -- never cast all fields in one changeset (mass assignment).
6. ALWAYS guard `runtime.exs` config with `if config_env() == :prod` -- it runs in ALL environments.
7. ALWAYS use raw SQL or migration-local schemas in migrations -- never reference application schemas.
8. NEVER use `String.to_atom/1` with user input -- atom table exhaustion attack vector.
9. NEVER use `raw/1` on unsanitized user input -- XSS vulnerability.
10. ALWAYS use `~H` sigil and `{...}` interpolation -- never use deprecated `~E`, `let={f}`, or `Phoenix.View`.
11. ALWAYS set `same_site`, `http_only`, and `secure` on session cookies in production.
12. ALWAYS call `delete_csrf_token/0` after login to prevent session fixation.
13. ALWAYS prefer generators (`mix phx.gen.*`) over hand-writing contexts, schemas, and migrations.
14. ALWAYS use battle-tested libraries for auth/crypto -- never hand-roll. Canonical picks: `phx.gen.auth` (sessions), Guardian (JWT APIs), Ueberauth (OAuth), `bcrypt_elixir`/`argon2_elixir` (password hashing), `Plug.Crypto.secure_compare/2` (constant-time compare).
15. NEVER set `check_origin: false` in production WebSocket config.
16. NEVER use `Mix.env()` in runtime code -- unavailable in releases. Use `Application.compile_env/3` or `Application.get_env/3`.

## 2. Decision Tables

### Which Route Type?

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| REST resource with CRUD | `resources "/users", UserController` | Individual route macros | Generates all standard paths with correct naming |
| LiveView with client state | `live "/dashboard", DashboardLive` | Controller + JS | Server-rendered real-time over WebSocket |
| Static page, no state | `get "/about", PageController, :about` | LiveView | LiveView overhead unnecessary |
| JSON API endpoint | `resources` in `:api` pipeline | `:browser` pipeline | No session/CSRF overhead |
| WebSocket real-time | Channel via `socket "/socket"` | Polling controller | Persistent connection, lower latency |
| Delegate to sub-router | `forward "/admin", AdminRouter` | Duplicating pipelines | Single responsibility |

### Which Data Access Pattern?

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Fetch by ID (may not exist) | `context.get_thing(id)` returning `nil` | `Repo.get!` in controller | Expected absence is not exceptional |
| Fetch by ID (must exist) | `context.get_thing!(id)` in controller | Manual nil check | 404 via Ecto.NoResultsError |
| Query with filters | Context function with `Ecto.Query` | Raw SQL in controller | Composable, parameterized |
| Create/update with validation | Context returning `{:ok, struct} / {:error, changeset}` | `Repo.insert` in controller | Encapsulates business logic |
| Form changeset for display | `context.change_thing(struct)` | Building changeset in template | Separation of concerns |

### Which Component Type?

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Reusable stateless UI | Function component with `attr`/`slot` | LiveComponent | Simpler, no process overhead |
| Shared layout wrapper | Function component | `embed_templates` alone | Composable with slots |
| Tabular data with columns | Slot attributes (`:col` with `:let`) | Manual table HTML | Declarative column definition |
| External template files | `embed_templates "components/*"` | Inline `~H` for large templates | Code organization |

### Which Auth Strategy?

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Browser app, login form | `phx.gen.auth` (sessions + cookies) | Hand-rolled JWT | Battle-tested, generates tests |
| JSON API, bearer token | Guardian | Hand-rolled Joken plug | Plug pipeline, revocation hooks built in |
| Both web + API | `phx.gen.auth` for web + Guardian for API | Single strategy | Different transport needs |
| OAuth providers | Ueberauth | Manual OAuth flow | Handles state, CSRF, provider quirks |
| Custom `Authorization` scheme | Guardian's `VerifyHeader` with `scheme:` option | Hand-rolled header parser | One config line vs. a whole plug |

### Which Generator?

| Intent | Use | Creates |
|--------|-----|---------|
| Full CRUD with HTML | `mix phx.gen.html` | Context, schema, migration, controller, templates, tests |
| JSON API endpoints | `mix phx.gen.json` | Context, schema, migration, controller, JSON view, tests |
| LiveView CRUD | `mix phx.gen.live` | Context, schema, migration, LiveView, components, tests |
| Business logic only | `mix phx.gen.context` | Context, schema, migration, context tests |
| Schema + migration | `mix phx.gen.schema` | Schema module, migration |
| Session auth | `mix phx.gen.auth` | Full auth system with tests |

## 3. Patterns

### Context Bypass

**Severity: BLOCK** | **Why: Breaks encapsulation, scatters query logic across web layer**

```elixir
# BAD
def show(conn, %{"id" => id}) do
  user = Repo.get!(User, id)
end

# GOOD
def show(conn, %{"id" => id}) do
  user = Accounts.get_user!(id)
end
```

### Mass Assignment

**Severity: BLOCK** | **Why: Security -- user can set admin flag via form params**

```elixir
# BAD
cast(attrs, [:username, :email, :admin])

# GOOD - separate changesets per trust level
def registration_changeset(user, attrs), do: cast(attrs, [:username, :email])
def admin_changeset(user, attrs), do: cast(attrs, [:admin, :role])
```

### Programmatic Fields in Cast

**Severity: BLOCK** | **Why: user_id from untrusted input allows impersonation**

```elixir
# BAD
cast(attrs, [:body, :user_id])

# GOOD
cast(attrs, [:body]) |> put_assoc(:user, user)
```

### SQL Injection

**Severity: BLOCK** | **Why: Arbitrary SQL execution from user input**

```elixir
# BAD
query = "SELECT * FROM users WHERE name = '#{params["name"]}'"

# GOOD
from(u in User, where: u.name == ^params["name"]) |> Repo.all()
```

### XSS via raw/1

**Severity: BLOCK** | **Why: Injects arbitrary HTML/JS from user input**

```elixir
# BAD
<%= raw(@user_input) %>

# GOOD - auto-escaped by default
<%= @user_input %>

# GOOD - if HTML needed, sanitize first
<%= raw(HtmlSanitizeEx.strip_tags(@user_input)) %>
```

### Atom Table Exhaustion

**Severity: BLOCK** | **Why: User input creates unlimited atoms, crashes VM**

```elixir
# BAD
role = String.to_atom(params["role"])

# GOOD
role = case params["role"] do
  "admin" -> :admin
  "user" -> :user
  _ -> :guest
end
```

### Schema in Migration

**Severity: BLOCK** | **Why: Migration breaks when schema changes later**

```elixir
# BAD
alias MyApp.Accounts.User
from(u in User, where: u.old_field == "value") |> Repo.update_all(...)

# GOOD
execute("UPDATE users SET permission = 'default' WHERE old_field = 'value'")
```

### Router Namespace Duplication

**Severity: WARN** | **Why: Scope already provides alias -- double namespace confuses routing**

```elixir
# BAD
scope "/admin", MyAppWeb.Admin do
  live "/users", MyAppWeb.Admin.UserLive
end

# GOOD
scope "/admin", MyAppWeb.Admin do
  live "/users", UserLive
end
```

### N+1 Queries

**Severity: WARN** | **Why: Linear query growth -- one query per template iteration**

```elixir
# BAD
users = Accounts.list_users()
Enum.map(users, fn u -> u.department.name end)

# GOOD
users = Accounts.list_users() |> Repo.preload(:department)
```

### runtime.exs Without Guard

**Severity: WARN** | **Why: Overrides dev/test config, causes :eaddrinuse and wrong settings**

```elixir
# BAD
config :my_app, MyAppWeb.Endpoint, http: [port: 4000]

# GOOD
if config_env() == :prod do
  config :my_app, MyAppWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]
end
```

### Hardcoded Fallback Secrets

**Severity: WARN** | **Why: Fallback ships in source control, deployed silently**

```elixir
# BAD
secret_key_base: System.get_env("SECRET_KEY_BASE") || "hardcoded_fallback"

# GOOD
secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
```

### Bang Functions in Context Logic

**Severity: WARN** | **Why: Crashes process on validation failure instead of returning errors**

```elixir
# BAD
def process_video(%Video{} = video) do
  Repo.update!(Video.changeset(video, %{status: :processing}))
  Repo.insert!(Thumbnail.changeset(%{video_id: video.id}))
end

# GOOD - use Multi for atomic operations with error tuples
def process_video(%Video{} = video) do
  Ecto.Multi.new()
  |> Ecto.Multi.update(:video, Video.changeset(video, %{status: :processing}))
  |> Ecto.Multi.insert(:thumbnail, fn %{video: v} ->
    Thumbnail.changeset(%Thumbnail{}, %{video_id: v.id})
  end)
  |> Repo.transaction()
end
```

### Mix.env() in Runtime Code

**Severity: WARN** | **Why: Not available in releases -- crashes in production**

```elixir
# BAD
if Mix.env() == :prod, do: Mailer.deliver(user)

# GOOD
if Application.get_env(:my_app, :send_emails), do: Mailer.deliver(user)
```

### God Context

**Severity: SUGGEST** | **Why: 30+ functions, 4+ responsibilities -- split for readability**

```elixir
# BAD - 850 lines, videos + channels + thumbnails + transcoding
defmodule MyApp.Library do ... end

# GOOD - split by responsibility
defmodule MyApp.Videos do ... end
defmodule MyApp.Channels do ... end
defmodule MyApp.Transcoding do ... end
```

### Context Coupling

**Severity: SUGGEST** | **Why: Hidden dependencies between contexts -- use PubSub instead**

```elixir
# BAD
defmodule MyApp.Settings do
  def update_car_settings(car, attrs) do
    MyApp.Vehicles.restart(car.id)  # Direct coupling
  end
end

# GOOD
Phoenix.PubSub.broadcast(MyApp.PubSub, "settings:#{car.id}", {:settings_changed, car.id})
```

### Process.sleep for Rate Limiting

**Severity: SUGGEST** | **Why: Blocks GenServer -- no other messages processed during sleep**

```elixir
# BAD
def handle_info(:geocode_batch, state) do
  Enum.each(state.pending, fn addr ->
    geocode(addr)
    Process.sleep(1500)
  end)
  {:noreply, state}
end

# GOOD - self-scheduling, process stays responsive
def handle_info(:geocode_next, %{pending: [addr | rest]} = state) do
  geocode(addr)
  Process.send_after(self(), :geocode_next, 1500)
  {:noreply, %{state | pending: rest}}
end
```

## 4. Checklist

### Before Every Controller/LiveView
- [ ] Business logic goes through a context, not direct Repo calls
- [ ] Associations preloaded before rendering
- [ ] Form uses `to_form()` and `@form[:field]`
- [ ] Verified routes (`~p"..."`) used everywhere

### Before Every Migration
- [ ] No application schema references -- raw SQL or migration-local schema only
- [ ] Foreign keys have `on_delete` strategy
- [ ] Indices on frequently queried columns and foreign keys

### Security Review
- [ ] No `raw/1` on user input
- [ ] No `String.to_atom/1` on user input
- [ ] Action-specific changesets (no mass assignment)
- [ ] Session cookies have `same_site`, `http_only`, `secure` in production
- [ ] `delete_csrf_token/0` called after login
- [ ] `check_origin` configured for WebSocket endpoints
- [ ] No hardcoded fallback secrets

### Deployment
- [ ] `runtime.exs` guarded with `if config_env() == :prod`
- [ ] Secrets use `System.fetch_env!/1` (fail loudly)
- [ ] No `Mix.env()` in runtime code

## 5. Routing

### Request Flow

```
Request -> Endpoint -> Router -> Pipeline -> Controller/LiveView -> Component -> Response
```

### Pipeline Setup

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
end

pipeline :api do
  plug :accepts, ["json"]
end
```

### Scopes and Live Sessions

```elixir
scope "/", MyAppWeb do
  pipe_through :browser
  get "/", PageController, :home
  resources "/users", UserController

  live_session :authenticated, on_mount: [{MyAppWeb.UserAuth, :ensure_authenticated}] do
    live "/dashboard", DashboardLive
    live "/settings", SettingsLive
  end
end

scope "/admin", MyAppWeb.Admin do
  pipe_through [:browser, :require_admin]
  live "/users", UserLive  # Points to MyAppWeb.Admin.UserLive
end
```

### Verified Routes

```elixir
~p"/users"
~p"/users/#{user.id}"
~p"/users/#{user}/edit"
```

### Content-Type Pipelines

```elixir
pipeline :feed do
  plug :accepts, ["xml"]
  plug :put_resp_content_type, "application/xml"
end
```

## Key Architecture Patterns

### Plug Fundamentals

Two types: function plugs (`def my_plug(conn, opts)`) and module plugs (`init/1` at compile time, `call/2` at runtime). Every plug must return the connection.

### Contexts

Group related functionality as bounded contexts. Return `{:ok, struct}` or `{:error, changeset}`. Bang functions (`get_user!`) for controllers only. Split at ~500 lines or 4+ responsibilities.

### Channels and PubSub

One channel process per client per topic. Broadcasts work across clustered nodes. For complex apps, use dedicated event structs instead of bare tuples.

### Configuration Precedence

```
1. config/config.exs           -- compile-time, all envs
2. config/{dev,test,prod}.exs  -- compile-time, per-env
3. config/runtime.exs          -- runtime, ALL envs (guard with config_env())
```

### Background Jobs (Oban)

Return `:ok` on success, `{:error, reason}` to retry, `{:snooze, seconds}` to delay. Use `unique: [period: 300]` to prevent duplicates.

### HEEx Template Rules

- Always `~H` sigil or `.html.heex` files
- `{...}` for interpolation, `<%= %>` for control flow
- Class conditionals use `[...]` syntax
- No `else if` -- use `cond`
- Comments: `<%!-- comment --%>`

## Related Skills

- **liveview** -- LiveView lifecycle, components, forms, streams, async, hooks, JS commands
- **elixir-planning / elixir-implementing / elixir-reviewing** -- Phase skills for Elixir development
