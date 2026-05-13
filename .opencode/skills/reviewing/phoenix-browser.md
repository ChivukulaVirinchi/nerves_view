---
name: phoenix-browser
description: >
  Browser-based verification and exploratory testing for Phoenix LiveView apps using agent-browser.
  Use when verifying UI changes end-to-end, testing authentication flows in the real browser,
  dogfooding LiveView features, checking LiveSocket connectivity, or running QA passes.
  For server-side verification (smoke_test, browser_inspect) → load phoenix-verify.
  For quality gates → load quality-gates.
---

# Phoenix Browser Verification

Real browser verification for Phoenix LiveView apps using `agent-browser`. This skill
covers what server-side tools cannot: LiveSocket WebSocket negotiation, phx-hook lifecycle,
JS interop, CSS transitions, flash message rendering, form validation UX, file upload
previews, and stream-driven DOM diffing.

**Prerequisite:** `agent-browser` installed (`npm i -g agent-browser && agent-browser install`).

## 1. Rules

1. **Server-side first, browser second** — run `smoke_test` or `mix test` before opening a browser. If the page 500s server-side, browser testing wastes time.
2. **Wait for LiveSocket** — after `open`, always wait for the LiveView WebSocket before interacting. A page that renders HTML but has no socket is not a working LiveView.
3. **Re-snapshot after every phx- event** — `phx-click`, `phx-submit`, `phx-change`, and stream updates all mutate the DOM. Refs are stale after any of these.
4. **Check flash messages explicitly** — Phoenix flash messages are rendered once and cleared. Snapshot immediately after the action that triggers them.
5. **Test disconnected render** — the initial HTML (before LiveSocket connects) must be usable. Verify by checking the page before `wait --fn` for the socket.
6. **Auth via the real login form** — unlike `browser_inspect` which forges cookies, browser testing should exercise the actual `phx.gen.auth` flow to catch form/redirect bugs.
7. **Name sessions after the feature** — use `--session accounts-login`, not `--session s1`. Survives context switches and makes `session list` readable.
8. **Always close sessions** — leaked browser processes accumulate. Close explicitly or use `close --all` at the end of a verification pass.
9. **Capture evidence before asserting** — screenshot + snapshot before claiming something works or is broken. Evidence outlives the session.

## 2. Decision Table

| Intent | Use | Avoid | Why |
|---|---|---|---|
| Quick "does it mount?" | `smoke_test` (server-side) | agent-browser | No browser overhead for a server check |
| LiveSocket actually connects | agent-browser + `wait --fn` for socket | `smoke_test` alone | smoke_test cannot verify WebSocket |
| Form validation UX (inline errors) | agent-browser: fill → trigger phx-change → snapshot | Reading changeset output in IEx | Real user sees DOM; changeset != rendered HTML |
| phx-hook mounted and working | agent-browser: open → wait → snapshot → check hook element | `validate_js_hooks` alone | validate_js_hooks checks static; hooks need a live page |
| Flash message after action | agent-browser: action → snapshot immediately | Waiting or scrolling first | Flash auto-dismisses; capture within 1-2s |
| Auth flow end-to-end | agent-browser: login form → submit → verify redirect | `browser_inspect` with forged cookie | Forged cookies skip the login code path |
| File upload with preview | agent-browser: `upload` → snapshot for preview → submit | curl or HTTP-level testing | Upload preview is client-side JS + LiveView |
| Stream-rendered list (append/prepend) | agent-browser: trigger → diff snapshot | Reading assigns in IEx | Streams update DOM directly; assigns don't show rendered order |
| Multi-role verification | Parallel sessions: `--session teacher`, `--session student` | Sequential single-session | Catch role-specific rendering bugs simultaneously |
| Mobile/responsive layout | `set viewport 375 812` → screenshot | Desktop-only verification | Tailwind responsive classes need real viewport |
| Dark mode rendering | `--color-scheme dark` → screenshot | Ignoring color scheme | Catches invisible text, missing dark: variants |
| Page load performance | `agent-browser open` + timing, or Chrome profiler | Guessing from server logs | Server time != total time (JS, fonts, images) |

## 3. Phoenix LiveView Patterns

### 3.1 Waiting for LiveSocket

**Every LiveView verification must confirm the WebSocket is connected.**

```bash
agent-browser open http://localhost:4000/dashboard
agent-browser wait --load networkidle

# Verify LiveSocket connected (not just HTML rendered)
agent-browser eval 'document.querySelector("[data-phx-main]") !== null'
# Or more precisely:
agent-browser eval --stdin <<'EVALEOF'
!!document.querySelector("[data-phx-session]")
EVALEOF
```

If the eval returns `false`, LiveView failed to mount. Check:
- JavaScript bundle loaded (`assets/js/app.js` compiled)
- No JS console errors: `agent-browser console`
- Socket endpoint configured in `endpoint.ex`

### 3.2 Authentication via phx.gen.auth

```bash
agent-browser --session auth-test open http://localhost:4000/users/log_in
agent-browser --session auth-test wait --load networkidle
agent-browser --session auth-test snapshot -i

# Fill the login form (refs from snapshot)
agent-browser --session auth-test fill @eN "test@example.com"
agent-browser --session auth-test fill @eM "password123456"
agent-browser --session auth-test click @eK

# Wait for redirect to authenticated page
agent-browser --session auth-test wait --url "**/dashboard"
agent-browser --session auth-test snapshot -i

# Verify: check URL is NOT /users/log_in
agent-browser --session auth-test get url
```

**After login, save state for reuse across verifications:**

```bash
agent-browser --session auth-test state save ./tmp/auth-state.json
```

**Reuse in subsequent checks:**

```bash
agent-browser --session verify --state ./tmp/auth-state.json open http://localhost:4000/protected
```

### 3.3 LiveView Form Validation

Phoenix forms trigger `phx-change` on every input change and `phx-submit` on submit.
Both produce server-rendered DOM updates over the socket.

```bash
agent-browser --session form-test open http://localhost:4000/posts/new
agent-browser --session form-test wait --load networkidle
agent-browser --session form-test snapshot -i

# Trigger phx-change validation by filling and tabbing away
agent-browser --session form-test fill @eN ""
agent-browser --session form-test press Tab

# Re-snapshot to see inline validation errors
agent-browser --session form-test snapshot -i
# Look for: error elements, phx-feedback-for, "can't be blank" text

# Fill valid data and submit
agent-browser --session form-test fill @eN "My Post Title"
agent-browser --session form-test fill @eM "Post body content..."
agent-browser --session form-test click @eK

# Capture flash message immediately after submit
agent-browser --session form-test wait --load networkidle
agent-browser --session form-test snapshot -i
# Look for: flash container with success message
```

**What to verify:**
- Inline errors appear on `phx-change` (not only on submit)
- Error styling matches (red borders, error text visible)
- `phx-feedback-for` hides errors until form has been interacted with
- Flash message appears after successful submit
- Form resets or redirects as expected

### 3.4 LiveView Streams

Streams update the DOM directly — assigns won't show the rendered order.
Browser verification is the only way to confirm stream behavior.

```bash
# Open a page that uses streams (e.g., a message list)
agent-browser --session stream-test open http://localhost:4000/messages
agent-browser --session stream-test wait --load networkidle
agent-browser --session stream-test snapshot -i

# Take a baseline snapshot for diffing
agent-browser --session stream-test snapshot -i > /tmp/stream-before.txt

# Trigger a stream insert (e.g., submit a new message)
agent-browser --session stream-test fill @eN "New message"
agent-browser --session stream-test click @eK
agent-browser --session stream-test wait 500

# Diff to see what changed
agent-browser --session stream-test diff snapshot --baseline /tmp/stream-before.txt
```

**What to verify:**
- New items appear at the correct position (prepend vs append)
- Deleted items actually disappear from DOM
- Updated items re-render without duplicating
- `phx-update="stream"` container has `id` attribute
- Stream items have stable `id` attributes (no flicker on re-render)

### 3.5 File Uploads

```bash
agent-browser --session upload-test open http://localhost:4000/photos/new
agent-browser --session upload-test wait --load networkidle
agent-browser --session upload-test snapshot -i

# Upload a file
agent-browser --session upload-test upload @eN ./test/fixtures/sample.jpg

# Snapshot to verify preview renders
agent-browser --session upload-test snapshot -i
agent-browser --session upload-test screenshot ./tmp/upload-preview.png

# Submit the form
agent-browser --session upload-test click @eK
agent-browser --session upload-test wait --load networkidle
agent-browser --session upload-test snapshot -i
```

**What to verify:**
- Preview image/filename appears after upload
- Progress indicator shows (if implemented)
- Error message for wrong file type or oversized file
- Upload completes on form submit (not lost)

### 3.6 JS Hooks in the Browser

`validate_js_hooks` checks static code. Browser verification confirms hooks actually mount:

```bash
agent-browser --session hook-test open http://localhost:4000/page-with-hooks
agent-browser --session hook-test wait --load networkidle

# Check that hook elements exist and have data attributes
agent-browser --session hook-test eval --stdin <<'EVALEOF'
JSON.stringify(
  Array.from(document.querySelectorAll("[phx-hook]"))
    .map(el => ({ hook: el.getAttribute("phx-hook"), id: el.id }))
)
EVALEOF

# Check the JS console for hook errors
agent-browser --session hook-test console
```

**What to verify:**
- No `"unknown hook"` warnings in console
- Hook elements have `id` attributes (required for LiveView tracking)
- Hook `mounted()` callback fired (check for DOM side effects the hook produces)

### 3.7 Flash Messages

Phoenix flash messages render once and clear on the next navigation or after a timeout.
They must be captured immediately.

```bash
# Perform the action that triggers a flash
agent-browser --session flash-test click @eN
agent-browser --session flash-test wait --load networkidle

# Capture immediately — do NOT navigate or wait further
agent-browser --session flash-test snapshot -i
agent-browser --session flash-test screenshot ./tmp/flash-message.png

# Verify flash content
agent-browser --session flash-test eval 'document.querySelector("[role=alert]")?.textContent'
```

### 3.8 Responsive and Dark Mode

```bash
# Mobile viewport
agent-browser --session mobile set viewport 375 812
agent-browser --session mobile open http://localhost:4000/dashboard
agent-browser --session mobile wait --load networkidle
agent-browser --session mobile screenshot ./tmp/mobile-dashboard.png

# Dark mode
agent-browser --session dark --color-scheme dark open http://localhost:4000/dashboard
agent-browser --session dark wait --load networkidle
agent-browser --session dark screenshot ./tmp/dark-dashboard.png
```

### 3.9 Multi-Role Verification

```bash
# Teacher session
agent-browser --session teacher open http://localhost:4000/users/log_in
# ... login as teacher ...
agent-browser --session teacher state save ./tmp/teacher-state.json

# Student session
agent-browser --session student open http://localhost:4000/users/log_in
# ... login as student ...
agent-browser --session student state save ./tmp/student-state.json

# Verify the same page renders differently per role
agent-browser --session teacher --state ./tmp/teacher-state.json open http://localhost:4000/course/1
agent-browser --session student --state ./tmp/student-state.json open http://localhost:4000/course/1

agent-browser --session teacher screenshot ./tmp/course-teacher.png
agent-browser --session student screenshot ./tmp/course-student.png
```

## 4. Verification Workflow

### Quick Verify (after any UI change)

```
1. smoke_test (server-side)           — catches 500s, bad redirects
2. agent-browser open + wait          — page loads in real browser
3. eval for LiveSocket                — WebSocket connected
4. snapshot -i                        — interactive elements present
5. screenshot                         — visual evidence captured
```

### Full Verify (before marking feature complete)

```
1. Quick Verify (above)
2. Auth flow                          — login → redirect → protected page
3. Form lifecycle                     — phx-change validation → phx-submit → flash
4. JS hooks                           — mounted, no console errors
5. Edge cases                         — empty states, error states, long content
6. Responsive                         — mobile viewport screenshot
7. Multi-role                         — each role sees correct content
8. close --all                        — clean up sessions
```

### Dogfood Pass (QA sweep of a feature area)

For systematic exploratory testing, follow the agent-browser dogfood workflow:

```bash
mkdir -p ./dogfood-output/screenshots ./dogfood-output/videos

agent-browser --session dogfood open http://localhost:4000
agent-browser --session dogfood wait --load networkidle
agent-browser --session dogfood screenshot --annotate ./dogfood-output/screenshots/initial.png
agent-browser --session dogfood snapshot -i
```

Then systematically:
- Visit each route in the feature area
- Test golden path and edge cases
- Record video for interactive bugs: `agent-browser --session dogfood record start ./dogfood-output/videos/issue-NNN.webm`
- Screenshot static issues
- Document findings in `./dogfood-output/report.md`

## 5. Checklist

### After Any UI Change

- [ ] `smoke_test` passes (200, no error redirect)
- [ ] Page opens in agent-browser without JS errors (`console`)
- [ ] LiveSocket connects (`data-phx-session` present)
- [ ] Interactive elements appear in `snapshot -i`
- [ ] Screenshot captured for evidence

### Before Marking LiveView Work Complete

- [ ] All Quick Verify steps pass
- [ ] Auth flow works end-to-end (login → protected page → correct content)
- [ ] Form validation: inline errors on `phx-change`, success on valid submit
- [ ] Flash messages render and are visible
- [ ] If `phx-hook`: hooks mount, no console errors, hook side effects work
- [ ] If streams: items appear/disappear/update correctly
- [ ] If uploads: preview renders, submit succeeds, errors handled
- [ ] Mobile viewport checked (375x812)
- [ ] Multiple roles verified (if role-dependent content)
- [ ] All sessions closed (`close --all`)

### Dogfood/QA Pass

- [ ] Output directory created with screenshots/ and videos/
- [ ] Each finding has reproduction evidence (screenshot or video)
- [ ] Findings classified by severity (block / request-change / suggest / nitpick)
- [ ] Console errors checked on every page
- [ ] Edge cases tested (empty states, invalid input, boundary values)
- [ ] Report written with issue count and severity breakdown

## 6. Routing

| If you need... | Load instead |
|---|---|
| Server-side verification (smoke_test, browser_inspect) | `phoenix-verify` |
| Quality gates (format, compile, credo) | `quality-gates` |
| BEAM runtime introspection | `beam-introspection` |
| HEEx template syntax | `heex` (implementing) |
| LiveView lifecycle issues | `liveview` (implementing) |
| Authentication code patterns | `security` |
| Form implementation patterns | `phoenix-forms` (implementing) |
| Upload implementation patterns | `phoenix-uploads` (implementing) |

## 7. Troubleshooting

**Page loads but LiveView doesn't connect**
```bash
agent-browser console  # check for JS errors
agent-browser eval 'typeof window.liveSocket'  # should be "object"
```
Common causes: JS bundle not compiled (`mix assets.deploy`), socket path mismatch, CSP blocking WebSocket.

**Login succeeds but redirect fails**
```bash
agent-browser get url  # check actual URL after login
```
Common causes: `return_to` parameter lost, scope mismatch in router, `on_mount` hook rejecting.

**Form submit does nothing**
```bash
agent-browser snapshot -i  # check form has phx-submit
agent-browser console      # check for JS errors
```
Common causes: missing `phx-submit` on form, button outside form, `phx-disable-with` stuck.

**Snapshot shows no interactive elements**
```bash
agent-browser snapshot     # full tree (not just -i)
agent-browser screenshot --annotate ./tmp/debug.png
```
Common causes: page still loading, LiveSocket not connected, content inside iframe.

**Flash message not visible**
Flash clears on navigation. If you navigated after the action, the flash is gone.
Snapshot immediately after the triggering action, before any other command.
