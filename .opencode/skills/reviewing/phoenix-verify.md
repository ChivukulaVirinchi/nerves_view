---
name: phoenix-verify
description: >
  Phoenix LiveView page verification and testing. ALWAYS use when verifying UI changes,
  testing authentication flows, debugging page rendering, or checking LiveView mounts.
  For quality gates → load quality-gates. For BEAM introspection → load beam-introspection.
---

# Phoenix LiveView Verification

Verify Phoenix LiveView pages without a manual browser. This skill covers the verification
workflow using Tidewave MCP tools: `smoke_test` for server-side checks, `browser_inspect`
for full rendering, and `validate_js_hooks` for JS hook integrity. Authentication is
handled by forging session cookies server-side -- no login form interaction needed.

## 1. Rules

1. **Always verify after UI changes** -- every template, component, or LiveView change needs at minimum a `smoke_test`.
2. **Check `final_url` in browser_inspect results** -- a redirect to `/login` means authentication failed silently.
3. **Get `user_id` from the database** -- never hardcode UUIDs. Query for a test user matching the role you need.
4. **Use `smoke_test` for quick checks** -- no browser needed, catches 500 errors, redirect chains, and mount-time crashes.
5. **Use `browser_inspect` for full UI verification** -- confirms LiveView mounts, hooks are present, and DOM renders correctly.
6. **Run `validate_js_hooks` after any hook change** -- catches missing hooks, incorrect callbacks, and template/JS mismatches without a browser.
7. **Follow the verification chain in order** -- smoke_test, then validate_js_hooks, then browser_inspect. Each level catches different issues.
8. **Use `eval_with_logs` to capture log output from operations** -- scoped logs show exactly what happened during the request.

## 2. Decision Table

| Intent / Situation | Use | Avoid | Why |
|---|---|---|---|
| Quick "does the page mount?" check | `smoke_test url="http://localhost:4000/route"` | Opening a browser manually | Instant; catches 500s, redirect chains, crashes |
| Full page render verification | `browser_inspect url="..." user_id="UUID"` | `smoke_test` alone | smoke_test does not render JS or hooks; browser_inspect does |
| Verify authentication works | `browser_inspect` + check `final_url` | Manually logging in through the browser | Forges session cookie server-side; no form interaction |
| JS hooks changed or added | `validate_js_hooks` | Manual browser testing | Parses JS bundle, cross-refs HEEx templates, validates callback names |
| Debugging a page error | `smoke_test` + check logs + `eval_with_logs` | Reading terminal output | Scoped logs show only the relevant request |
| Finding a test user for auth | `project_eval` with Ecto query | Hardcoding UUIDs | UUIDs change between environments; query ensures a valid user |
| Verifying redirect chain | `smoke_test` -- returns redirect chain | Following redirects manually | Shows every hop: 302 -> 302 -> 200 |
| Checking LiveView assigns | `get_process_info` on the LiveView PID | Adding `IO.inspect` to the LiveView | Non-invasive; does not modify code |
| Testing a public page (no auth) | `smoke_test` or `browser_inspect` without `user_id` | -- | No authentication needed for public routes |
| Testing multiple roles | Multiple `browser_inspect` calls with different `user_id`s | One check for one role | Different roles see different content; verify each |
| After deploy/restart | `smoke_test` on critical routes | Assuming it works | Catches config issues, missing env vars, broken migrations |

## 3. Patterns

### 3.1 Hardcoded User UUID

**Severity:** BLOCK

```elixir
# BAD -- UUID from development that won't exist in other environments
browser_inspect(
  url: "http://localhost:4000/dashboard",
  user_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"  # hardcoded
)

# GOOD -- query for a user with the right attributes
# Step 1: Find a suitable user
project_eval("""
  import Ecto.Query
  MyApp.Repo.one(
    from u in MyApp.Accounts.User,
    where: u.role == :student,
    limit: 1,
    select: u.id
  )
""")

# Step 2: Use the returned UUID
browser_inspect(
  url: "http://localhost:4000/dashboard",
  user_id: "returned-uuid-from-step-1"
)
```

**Why:** Hardcoded UUIDs break when the database is reset, seeded differently, or in a different environment. Querying ensures a valid user always exists.

### 3.2 Skipping final_url Check

**Severity:** BLOCK

```elixir
# BAD -- assuming browser_inspect succeeded because it returned data
result = browser_inspect(url: "http://localhost:4000/admin", user_id: uuid)
# "Looks good!" -- but final_url is "/login", not "/admin"

# GOOD -- explicitly check final_url
result = browser_inspect(url: "http://localhost:4000/admin", user_id: uuid)
# Check: result.final_url should be "/admin"
# If final_url is "/login" → auth failed; user doesn't have admin role
```

**Why:** `browser_inspect` follows redirects silently. A redirect to `/login` means the session cookie was rejected or the user lacks the required role. The page renders the login form, not the admin panel -- but it still returns a 200 status.

### 3.3 Using smoke_test for Everything

**Severity:** WARN

```elixir
# BAD -- smoke_test cannot verify JS hooks or full rendering
smoke_test(url: "http://localhost:4000/interactive-page")
# "Page works!" -- but the phx-hook never mounted, form is broken

# GOOD -- use the full verification chain
# 1. Quick server check
smoke_test(url: "http://localhost:4000/interactive-page")

# 2. Validate JS hooks
validate_js_hooks()  # catches missing/broken hooks

# 3. Full browser render (with auth if needed)
browser_inspect(url: "http://localhost:4000/interactive-page", user_id: uuid)
# Check: js_hooks field shows expected hooks
# Check: element_count is reasonable
```

**Why:** `smoke_test` only checks server-side rendering (HTTP request/response). It does not execute JavaScript, mount phx-hooks, or render the full DOM. Interactive pages need `browser_inspect` for complete verification.

### 3.4 Missing Hook Validation After Changes

**Severity:** WARN

```elixir
# BAD -- changed a JS hook but did not verify
# (edited assets/js/hooks/chart_hook.js)
# (edited lib/my_app_web/live/dashboard_live.html.heex -- added phx-hook="ChartHook")
# "I'll test it manually later"

# GOOD -- validate immediately after hook changes
# After editing hook JS or templates with phx-hook:
validate_js_hooks()
# Checks:
# - JS file parses without errors
# - Hook name in template matches a defined hook
# - Required callbacks (mounted, updated, destroyed) exist
```

**Why:** JS hook mismatches are silent failures. A misspelled hook name in the template means the hook never mounts -- no error, just a non-functional element. `validate_js_hooks` catches this at dev time.

### 3.5 No Log Isolation During Debugging

**Severity:** SUGGEST

```elixir
# BAD -- reading mixed logs from terminal to find the error
# (scrolling through pages of output from all requests)

# GOOD -- scoped log capture
# Step 1: Clear logs
project_eval("Tidewave.clear_logs()")

# Step 2: Trigger the specific operation
smoke_test(url: "http://localhost:4000/failing-route")

# Step 3: Read only the relevant logs
get_logs(level: "error", tail: 20)
```

**Why:** Development logs contain output from all requests, background jobs, and system processes. Clearing before reproducing isolates the exact logs from your specific operation.

## 4. Checklist

### After Any UI Change

- [ ] `smoke_test` passes (HTTP 200, no redirect to error page)
- [ ] If authenticated route: `final_url` matches expected path (not `/login`)
- [ ] If JS hooks changed: `validate_js_hooks` passes

### Before Marking LiveView Work Complete

- [ ] `smoke_test` on the changed route(s)
- [ ] `validate_js_hooks` if any `phx-hook` attributes exist
- [ ] `browser_inspect` with appropriate `user_id` for each role
- [ ] Checked `final_url`, `js_hooks`, and `element_count` in results
- [ ] Verified with multiple roles if role-based content exists

### When Debugging

- [ ] Cleared logs before reproducing (`Tidewave.clear_logs()`)
- [ ] Used `get_logs` with level filter after reproducing
- [ ] Checked `smoke_test` response for redirect chain
- [ ] Used `eval_with_logs` for targeted function debugging

## 5. Routing

| If you need... | Load instead |
|---|---|
| Real browser testing (LiveSocket, forms, hooks, uploads, responsive) | `phoenix-browser` |
| Quality gates (format, compile, credo) | `quality-gates` |
| BEAM runtime introspection | `beam-introspection` |
| HEEx template syntax | `heex` |
| LiveView lifecycle and mount issues | `liveview` |
| JS hook design patterns | `hooks` |
| Authentication and session patterns | `security` |

## Tool Reference

### smoke_test

Sends an HTTP request to the given URL and returns server-side diagnostics.

**Returns:**
- HTTP status code (200, 302, 500, etc.)
- Redirect chain (every hop)
- Response body snippet
- Application logs scoped to that request

**Usage:**
```
smoke_test(url: "http://localhost:4000/your-route")
```

### browser_inspect

Renders the page in a headless browser (Lightpanda) and returns DOM information.

**Returns:**
- `final_url` -- actual URL after all redirects (catch auth failures here)
- `title` -- page title
- `js_hooks` -- LiveView `phx-hook` elements found on the page
- `source_files` -- Phoenix debug source annotations (file:line)
- `element_count` -- total DOM elements

**Usage:**
```
browser_inspect(url: "http://localhost:4000/route", user_id: "UUID")
```

### validate_js_hooks

Parses the JavaScript bundle, cross-references with HEEx templates, and validates hook definitions.

**Checks:**
- JS files parse without syntax errors
- Hook names in templates match defined hooks
- Required callbacks exist (`mounted`, `updated`, `destroyed`)

**Usage:**
```
validate_js_hooks()
```

### eval_with_logs

Evaluates Elixir code inside the running application and captures log output.

**Usage:**
```
eval_with_logs(code: "MyApp.SomeModule.some_function()")
```

## Authentication Workflow

```
# 1. Find a user with the right role
project_eval("""
  import Ecto.Query
  MyApp.Repo.one(from u in MyApp.Accounts.User,
    where: u.user_type == :student, limit: 1, select: u.id)
""")

# 2. Verify the page with that user
browser_inspect(url: "http://localhost:4000/home", user_id: "uuid-from-step-1")

# 3. Validate: final_url should be "/home", NOT "/login"
```

No browser-based login is needed. `browser_inspect` forges a session cookie server-side using the provided `user_id`.
