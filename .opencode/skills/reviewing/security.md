---
name: elixir-security
description: >
  Comprehensive security skill covering atom exhaustion, XSS prevention, SQL
  injection, LiveView re-authorization, router session boundaries, auth flows,
  current_scope patterns, and secrets management. ALWAYS use when writing auth,
  session, password, token, authorization, or security-sensitive code. For
  Ecto query safety -> load ecto. For form validation -> load phoenix-forms.
---

# Security: Auth, Sessions, Authorization & Defense

Security in Phoenix/LiveView requires defense at every layer: router sessions
for coarse access control, context functions for record-level authorization,
LiveView events for re-authorization on every mutation, and fundamental hygiene
around atoms, HTML escaping, and SQL parameterization. LLMs consistently fail
to re-authorize in LiveView events, mix public and authenticated route sessions,
and use `String.to_atom/1` on user input.

## 1. Rules

1. **Authorize in every LiveView event handler.** Mount-time auth is NOT enough. Users can send arbitrary events to any mounted LiveView via the WebSocket.
2. **Never `String.to_atom/1` on user input.** Atoms are never garbage collected. User-controlled atom creation is a denial-of-service vector.
3. **Never `raw/1` without sanitization.** `raw/1` bypasses Phoenix's automatic HTML escaping. Always sanitize first, or avoid `raw` entirely.
4. **Never interpolate into SQL.** Use parameterized queries everywhere -- `fragment("?", ^value)` and `Repo.query("$1", [value])`.
5. **Put secrets in `runtime.exs` only.** `config.exs` and `prod.exs` are compiled into the release binary. Secrets there are baked into artifacts.
6. **Use separate `live_session` blocks for different auth levels.** Never put admin routes in the general authenticated session.
7. **`handle_params/3` must re-authorize URL-derived records.** Don't trust prior assigns when the URL changes within a live session.
8. **Use `current_scope` to shape queries, not naked `user_id`.** The scope struct carries the full authorization context and prevents accidental cross-tenant data access.
9. **Route login/register/reset flows through `phx-trigger-action`.** These flows need cookies and HTTP redirects that LiveView WebSocket cannot provide.
10. **Validate and sanitize all external input at the boundary.** Controllers and LiveView event handlers are the boundary. Never trust data deep in business logic.

## 2. Decision Tables

### 2.1 Authorization Layer Selection

| What to Protect | Where to Authorize | How | Why |
|----------------|-------------------|-----|-----|
| Entire route group (logged-in only) | Router `live_session` + `on_mount` | `on_mount: [{MyAppWeb.UserAuth, :require_authenticated}]` | Prevents mounting for unauthenticated users |
| Specific resource access | Context function | `def get_quiz!(scope, id)` scoped to scope | Database query enforces ownership |
| Destructive/sensitive event | LiveView `handle_event` | Re-check ownership before mutating | Events bypass mount auth check |
| Admin-only features | Separate `live_session` + admin `on_mount` | Dedicated on_mount hook checks admin role | Isolates admin privilege escalation surface |
| URL-driven data loading | `handle_params/3` | Re-authorize when params change | Live navigation can change URL without re-mounting |

### 2.2 Router Session Design

| Route Type | Session Name | on_mount Hook | Why |
|-----------|-------------|---------------|-----|
| Public pages (landing, docs) | `:public` | `[:ensure_current_scope]` (optional user) | No auth required, optionally personalized |
| Auth pages (login, register) | `:redirect_if_authenticated` | `[:redirect_if_authenticated]` | Logged-in users should not see login page |
| Authenticated features | `:require_authenticated` | `[:require_authenticated]` | Must be logged in |
| Admin tools | `:require_admin` | `[:require_authenticated, :require_admin]` | Separate session prevents privilege leak |

### 2.3 Input Sanitization Strategy

| Input Type | Threat | Defense | Why |
|-----------|--------|---------|-----|
| User text displayed in HTML | XSS | Phoenix auto-escapes by default; never use `raw/1` | Templates escape `<script>` tags automatically |
| User text rendered as markdown/rich | XSS | `HtmlSanitizeEx.markdown_html/1` before `raw/1` | Strips dangerous tags while preserving formatting |
| User params used in queries | SQL injection | Ecto `^pin` and `fragment("?", ^val)` | Parameterized queries prevent injection |
| User params used as atom keys | DoS (atom exhaustion) | `String.to_existing_atom/1` or allowlist | Atoms are never garbage collected |
| User params selecting modules | Remote code execution | Explicit allowlist map | Never dynamically construct module names |
| File upload names | Path traversal | `Path.basename/1` + UUID prefix | Strips directory traversal characters |
| URL params for redirects | Open redirect | Allowlist paths or use `~p` sigil | Prevents redirect to malicious external sites |

### 2.4 Auth Flow Selection

| Flow | Mechanism | Why Not Pure LiveView? |
|------|-----------|----------------------|
| Login (password) | `phx-trigger-action` -> HTTP POST -> session cookie | Session cookies require HTTP request/response |
| Registration confirmation | `phx-trigger-action` -> HTTP POST | Token verification + session creation needs HTTP |
| OAuth callback | Controller action | OAuth providers redirect to HTTP endpoints |
| Password reset | LiveView form + controller action | Token link arrives via email to HTTP route |
| Logout | HTTP DELETE to session controller | Must clear HTTP-only session cookie |
| API token auth | Plug pipeline (not LiveView) | Stateless auth per HTTP request |

## 3. Patterns (BAD -> GOOD)

### 3.1 Mount-Only Authorization

**Severity:** BLOCK

```elixir
# BAD -- only checks in mount, events are unprotected
def mount(%{"id" => id}, _session, socket) do
  quiz = Quizzes.get_quiz!(id)
  if quiz.owner_id != socket.assigns.current_user.id, do: raise "unauthorized"
  {:ok, assign(socket, quiz: quiz)}
end

def handle_event("delete", _, socket) do
  Quizzes.delete_quiz(socket.assigns.quiz)  # no re-check!
  {:noreply, push_navigate(socket, to: ~p"/quizzes")}
end

# GOOD -- re-authorize in every mutation event
def handle_event("delete", _, socket) do
  quiz = socket.assigns.quiz
  scope = socket.assigns.current_scope

  case Quizzes.delete_quiz(scope, quiz) do
    {:ok, _} ->
      {:noreply, push_navigate(socket, to: ~p"/quizzes")}
    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Not authorized")}
  end
end
```

**Why:** A user can open a page they own, then send arbitrary events from browser DevTools or a crafted WebSocket message. Mount checks run once; events can fire unlimited times with any payload.

### 3.2 Atom Exhaustion via User Input

**Severity:** BLOCK

```elixir
# BAD -- atom table DoS
role = String.to_atom(params["role"])
status = String.to_atom(params["status"])

# GOOD -- explicit allowlist
role = case params["role"] do
  "student" -> :student
  "teacher" -> :teacher
  "admin"   -> :admin
  _         -> :guest
end

# ACCEPTABLE -- if atom is known to exist at compile time
role = String.to_existing_atom(params["role"])
# Raises ArgumentError if atom doesn't exist (safe, but gives ugly error)
```

**Why:** The BEAM VM atom table has a fixed limit (default ~1M). Each unique `String.to_atom/1` call creates a permanent entry. An attacker sending random strings exhausts the table and crashes the VM.

### 3.3 XSS via raw/1

**Severity:** BLOCK

```elixir
# BAD -- direct XSS vector
<%= raw(@user_content) %>

# BAD -- "sanitizing" with String.replace
<%= raw(String.replace(@user_content, "<script>", "")) %>
# Bypassed by: <scr<script>ipt>alert(1)</script>

# GOOD -- proper sanitizer library
<%= raw(HtmlSanitizeEx.markdown_html(@user_content)) %>

# BEST -- avoid raw entirely, let Phoenix auto-escape
{@user_content}
```

**Why:** Phoenix templates auto-escape HTML by default. `raw/1` opts out of this protection. If the content includes `<script>alert('xss')</script>`, it executes in the user's browser.

### 3.4 SQL Injection in Fragments

**Severity:** BLOCK

```elixir
# BAD -- string interpolation in SQL
fragment("name ILIKE '%#{search}%'")
Repo.query("SELECT * FROM users WHERE name = '#{name}'")

# GOOD -- parameterized placeholders
fragment("name ILIKE ?", ^"%#{search}%")
Repo.query("SELECT * FROM users WHERE name = $1", [name])
```

**Why:** String interpolation in SQL is the classic injection vector. Input like `'; DROP TABLE users; --` becomes executable SQL. Parameterized queries separate data from code.

### 3.5 Secrets in Compile-Time Config

**Severity:** BLOCK

```elixir
# BAD -- in config/config.exs or config/prod.exs
config :my_app, MyAppWeb.Endpoint,
  secret_key_base: "actual-secret-here"

config :my_app, :stripe_key, "sk_live_..."

# GOOD -- in config/runtime.exs
config :my_app, MyAppWeb.Endpoint,
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

config :my_app, :stripe_key, System.fetch_env!("STRIPE_SECRET_KEY")
```

**Why:** `config.exs` and `prod.exs` are evaluated at compile time and their values are embedded in the release binary. Anyone with access to the release artifact can extract secrets. `runtime.exs` reads from the environment at boot.

### 3.6 Admin Routes in General Auth Session

**Severity:** BLOCK

```elixir
# BAD -- admin routes share session with regular users
live_session :require_authenticated, on_mount: [{UserAuth, :require_authenticated}] do
  live "/dashboard", DashboardLive
  live "/admin/users", AdminUsersLive  # privilege escalation risk!
end

# GOOD -- separate session with dedicated hook
live_session :require_admin,
  on_mount: [{UserAuth, :require_authenticated}, {UserAuth, :require_admin}] do
  live "/admin/users", AdminUsersLive
  live "/admin/settings", AdminSettingsLive
end
```

**Why:** Shared sessions mean an authenticated user who discovers the admin URL can access admin LiveViews. A separate `on_mount` hook checks admin role at mount time.

### 3.7 Trusting Assigns After URL Change

**Severity:** WARN

```elixir
# BAD -- handle_params trusts stale assigns
def handle_params(%{"id" => id}, _uri, socket) do
  quiz = Quizzes.get_quiz!(id)  # no ownership check!
  {:noreply, assign(socket, quiz: quiz)}
end

# GOOD -- re-authorize with current scope
def handle_params(%{"id" => id}, _uri, socket) do
  scope = socket.assigns.current_scope
  quiz = Quizzes.get_quiz!(scope, id)  # scoped query ensures ownership
  {:noreply, assign(socket, quiz: quiz)}
end
```

**Why:** Within a live session, `patch` navigation triggers `handle_params` without re-mounting. A user can manually change the URL to access another user's resource ID.

### 3.8 Naked user_id Instead of current_scope

**Severity:** WARN

```elixir
# BAD -- passing raw user_id loses authorization context
def list_quizzes(user_id) do
  from(q in Quiz, where: q.owner_id == ^user_id) |> Repo.all()
end

# Later, someone calls: list_quizzes(params["user_id"])  # IDOR vulnerability

# GOOD -- scope struct carries verified authorization context
def list_quizzes(%Scope{user: user}) do
  from(q in Quiz, where: q.owner_id == ^user.id) |> Repo.all()
end
```

**Why:** A raw `user_id` parameter can come from anywhere -- URL params, form input, API calls. The `Scope` struct is set by the auth system and represents the verified, authenticated user. It cannot be forged by client input.

### 3.9 Missing on_mount for Public Routes

**Severity:** SUGGEST

```elixir
# BAD -- public routes with no session at all
live "/about", AboutLive  # no live_session wrapper

# GOOD -- public session with optional user loading
live_session :public, on_mount: [{UserAuth, :mount_current_scope}] do
  live "/about", AboutLive
  live "/pricing", PricingLive
end
```

**Why:** Even public pages often need to know if a user is logged in (to show nav bar, personalization). A public session with optional scope loading provides this without requiring authentication.

### 3.10 Mixing Cookie and WebSocket Auth

**Severity:** WARN

```elixir
# BAD -- trying to set cookies from LiveView
def handle_event("login", params, socket) do
  # This doesn't work! LiveView runs over WebSocket
  # Cookies can only be set in HTTP response headers
end

# GOOD -- use phx-trigger-action for cookie-based flows
def handle_event("submit_login", params, socket) do
  if valid_credentials?(params) do
    {:noreply, assign(socket, trigger_submit: true)}
  else
    {:noreply, put_flash(socket, :error, "Invalid credentials")}
  end
end
```

```heex
<.form for={@form} action={~p"/session"} phx-submit="submit_login"
       phx-trigger-action={@trigger_submit}>
  <%-- fields --%>
</.form>
```

**Why:** LiveView runs over WebSocket. Cookies are HTTP headers that can only be set during an HTTP request/response cycle. `phx-trigger-action` bridges this by submitting the form as a regular HTTP POST after LiveView validation.

## 4. Checklist

### Router Security
- [ ] Routes are in correct `live_session` blocks by auth level
- [ ] Admin routes have their own `live_session` with admin `on_mount`
- [ ] Public routes still have a session with optional scope loading
- [ ] Auth flows (login, register, reset) use `phx-trigger-action`

### LiveView Security
- [ ] Every `handle_event` that mutates data re-checks authorization
- [ ] `handle_params` re-authorizes when URL params change
- [ ] Context functions accept `scope` and scope queries accordingly
- [ ] No naked `user_id` passed from client to context functions

### Input Safety
- [ ] No `String.to_atom/1` on user input (use allowlist or `to_existing_atom`)
- [ ] No `raw/1` without `HtmlSanitizeEx` or equivalent sanitizer
- [ ] No string interpolation in `fragment/1` or `Repo.query/2`
- [ ] File upload names sanitized with `Path.basename/1`
- [ ] Redirect targets validated (no open redirects)

### Secrets Management
- [ ] All secrets in `config/runtime.exs` via `System.fetch_env!/1`
- [ ] No secrets in `config.exs`, `dev.exs`, or `prod.exs`
- [ ] `.env` files in `.gitignore`
- [ ] No secrets in LiveView assigns (visible in DOM/DevTools)

## 5. Routing

- **Ecto query safety (SQL injection, parameterization)** -> load `ecto`
- **Form validation and changeset handling** -> load `phoenix-forms`
- **LiveView mount/handle_params lifecycle** -> load `liveview-lifecycle`
- **File upload security** -> load `phoenix-uploads`
- **Testing auth flows** -> load `testing`
- **Oban worker security (args, idempotency)** -> load `oban`
