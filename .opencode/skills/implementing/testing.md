---
name: elixir-testing
description: >
  Comprehensive testing skill covering ExUnit structure, fixtures, context
  testing, Mox, LiveView interaction tests, async safety, uploads, and worker
  verification. ALWAYS use when writing or reviewing ExUnit tests. For Ecto
  query testing -> load ecto. For LiveView component design -> load
  liveview-components.
---

# Testing: ExUnit, Fixtures, Mox & LiveView

Elixir testing with ExUnit is powerful but LLMs consistently make mistakes
around fixture design, async safety, Mox boundaries, LiveView test interactions,
and process testing. This skill covers the full testing surface from basic unit
tests through advanced integration patterns.

## 1. Rules

1. **Use fixtures, not mocks, for internal logic.** Mocks lie about real behavior. Only mock external boundaries behind behaviours.
2. **Test through the context API, not Repo directly.** Context functions are your public API; test what users of your code actually call.
3. **Each test creates its own data.** No shared state between tests. Fixtures accept `attrs` overrides for test-specific customization.
4. **Default to `async: true`.** Only set `async: false` when tests mutate global state (ETS, Application env, named processes).
5. **Never use `Process.sleep/1` in tests.** Use `assert_receive`, monitors, `:sys.get_state/1`, or `start_supervised!` for synchronization.
6. **Mock only external boundaries, behind behaviours.** Define the behaviour first, then mock it. Never mock Repo or internal business logic.
7. **Always `verify_on_exit!` with Mox.** Ensures expected calls were actually made.
8. **Test LiveViews through selectors and events, not raw HTML string matching.** Use `element/3`, `render_click/2`, `form/3`, `render_submit/2`.
9. **Assert Oban worker return values map to retry semantics.** `:ok` and `{:ok, _}` mean success; `{:error, _}` triggers retry; `{:cancel, _}` means permanent failure.
10. **Use `start_supervised!/1` for all test processes.** Ensures cleanup on test exit. Never use bare `GenServer.start_link/3` in tests.

## 2. Decision Tables

### 2.1 Test Module Selection

| What You're Testing | Use Module | Key Import | Why |
|---------------------|------------|------------|-----|
| Context functions (business logic) | `MyApp.DataCase` | `import MyApp.Fixtures.*` | Sandbox connection, no HTTP overhead |
| Controller/plug endpoints | `MyApp.ConnCase` | `import Plug.Conn` | Provides `build_conn()` |
| LiveView pages | `MyApp.ConnCase` | `import Phoenix.LiveViewTest` | LiveView tests use conn-based mounting |
| Channel interactions | `MyApp.ChannelCase` | `import Phoenix.ChannelTest` | Provides socket helpers |
| Pure functions (no DB) | `ExUnit.Case` | nothing | No database needed |

### 2.2 Test Data Strategy

| Situation | Use | Avoid | Why |
|-----------|-----|-------|-----|
| Need a persisted record with defaults | Fixture function (`item_fixture/1`) | Raw `Repo.insert!` in test | Fixtures encapsulate defaults and dependency chains |
| Need a struct without DB | `build` function (no insert) | Full fixture when DB not needed | Faster, no transaction overhead |
| Need to verify external call | `Mox.expect/3` | Real HTTP call | Deterministic, fast, no network dependency |
| Need unique values | `System.unique_integer()` | Hardcoded strings | Prevents collision in async tests |
| Need related records | Fixture that creates parent chain | Manual multi-step setup | Keeps test setup DRY and correct |
| Need to stub config/env | `Application.put_env` + `on_exit` cleanup | Module attribute or hardcoded | Allows per-test config without leaking |

### 2.3 Async Safety

| Resource | Async-Safe? | Solution if Not |
|----------|-------------|-----------------|
| Ecto Repo (DataCase sandbox) | Yes | Sandbox handles isolation per test |
| Named GenServer/ETS table | No | Use `async: false` or unique names per test |
| Application env | No | Use `async: false` + `on_exit` cleanup |
| File system | No | Use unique temp paths or `async: false` |
| Mox (global mode) | No | Use `set_mox_from_context` + allowances for async |
| PubSub | Yes | Subscribe in test, messages are per-process |

### 2.4 LiveView Test Coverage

| What to Test | How | Why |
|--------------|-----|-----|
| Mount authorization | `assert {:error, {:redirect, _}} = live(conn, path)` | Verifies unauthorized users can't access |
| Form validation (phx-change) | `form(view, "#form-id", %{field: bad_value}) \|> render_change()` | Verifies live validation feedback |
| Form submission | `form(view, "#form-id", %{field: value}) \|> render_submit()` | Verifies create/update flows |
| Submit + redirect | `{:error, {:redirect, %{to: path}}} = render_submit(...)` or `assert_redirect` | Verifies navigation after success |
| Async data loading | `render_async(view)` | Waits for `start_async` to complete |
| Upload flow | `file_input(view, "#form", :field, [file]) \|> render_upload(...)` | Verifies upload acceptance and consumption |
| Stream rendering | `assert has_element?(view, "#items-#{id}")` | Tests stream items by stable DOM id |
| Flash messages | `assert render(view) =~ "Created successfully"` | Verifies user feedback |
| Event authorization | Mount as non-owner, send event, assert error flash | Verifies event-level auth checks |

## 3. Patterns (BAD -> GOOD)

### 3.1 Fixture Returns Tuple Instead of Schema

**Severity:** BLOCK

```elixir
# BAD -- returns {:ok, item}, forcing destructuring in every test
def item_fixture(attrs \\ %{}) do
  attrs
  |> Enum.into(%{title: "Test Item"})
  |> MyApp.Context.create_item()
end

# GOOD -- returns the schema directly
def item_fixture(attrs \\ %{}) do
  {:ok, item} =
    attrs
    |> Enum.into(%{title: "Test Item #{System.unique_integer()}"})
    |> MyApp.Context.create_item()
  item
end
```

**Why:** Every test that calls the fixture would need `{:ok, item} = item_fixture()`. Unwrapping in the fixture keeps tests clean. Using `System.unique_integer()` prevents collisions in async tests.

### 3.2 Hardcoded Unique Values

**Severity:** WARN

```elixir
# BAD -- collides in async tests
def user_fixture(attrs \\ %{}) do
  {:ok, user} =
    attrs
    |> Enum.into(%{email: "test@example.com"})
    |> Accounts.create_user()
  user
end

# GOOD -- unique per invocation
def user_fixture(attrs \\ %{}) do
  unique = System.unique_integer()
  {:ok, user} =
    attrs
    |> Enum.into(%{
      email: "user-#{unique}@example.com",
      username: "user_#{unique}"
    })
    |> Accounts.create_user()
  user
end
```

**Why:** Async tests run concurrently. Hardcoded emails hit unique constraint violations. `System.unique_integer()` guarantees uniqueness across all concurrent tests.

### 3.3 Process.sleep in Tests

**Severity:** BLOCK

```elixir
# BAD -- flaky, wastes time, hides race conditions
test "worker processes message" do
  send(worker, {:process, data})
  Process.sleep(100)
  assert Worker.get_result(worker) == expected
end

# GOOD -- synchronize with the process
test "worker processes message" do
  send(worker, {:process, data})
  _ = :sys.get_state(worker)  # forces sync with GenServer mailbox
  assert Worker.get_result(worker) == expected
end

# GOOD -- use monitor for process completion
test "task completes" do
  {:ok, pid} = start_supervised!(MyWorker)
  ref = Process.monitor(pid)
  MyWorker.do_work(pid)
  assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
end
```

**Why:** `Process.sleep` makes tests slow and flaky. The sleep duration is a guess -- too short causes intermittent failures, too long wastes CI time. Monitors and `:sys.get_state` provide deterministic synchronization.

### 3.4 Mocking Internal Business Logic

**Severity:** BLOCK

```elixir
# BAD -- mocking Repo or context functions
expect(MyApp.MockRepo, :get, fn _, _ -> %User{id: 1} end)
expect(MyApp.MockContext, :create_item, fn _ -> {:ok, %Item{}} end)

# GOOD -- mock only the external boundary
# 1. Define a behaviour for the external service
defmodule MyApp.Mailer do
  @callback deliver(Swoosh.Email.t()) :: {:ok, term()} | {:error, term()}
end

# 2. Mock the behaviour
setup :verify_on_exit!

expect(MyApp.MockMailer, :deliver, fn email ->
  assert email.to == [{"", "user@example.com"}]
  {:ok, :sent}
end)
```

**Why:** Mocking internal modules creates tests that pass while production code breaks. The mock returns whatever you told it to, hiding real bugs. External boundaries (email, HTTP, SMS) are the correct mock boundary.

### 3.5 Testing Repo Directly Instead of Context

**Severity:** WARN

```elixir
# BAD -- bypasses business rules
test "creates a quiz" do
  quiz = Repo.insert!(%Quiz{title: "Test", owner_id: user.id})
  assert quiz.title == "Test"
end

# GOOD -- tests through the public API
test "creates a quiz" do
  assert {:ok, quiz} = Quizzes.create_quiz(user, %{title: "Test"})
  assert quiz.title == "Test"
  assert quiz.owner_id == user.id
end
```

**Why:** The context function may enforce validations, set defaults, create related records, or publish events. Testing Repo directly skips all of that, giving false confidence.

### 3.6 LiveView Testing with Raw HTML Matching

**Severity:** WARN

```elixir
# BAD -- brittle, breaks when markup changes
test "shows quiz title" do
  {:ok, view, html} = live(conn, ~p"/quizzes/#{quiz}")
  assert html =~ "<h1>My Quiz</h1>"
end

# GOOD -- use selectors
test "shows quiz title" do
  {:ok, view, _html} = live(conn, ~p"/quizzes/#{quiz}")
  assert has_element?(view, "h1", "My Quiz")
end

# BAD -- submitting forms without the form helper
test "creates item" do
  {:ok, view, _html} = live(conn, ~p"/items/new")
  render_click(view, "save", %{item: %{title: "New"}})
end

# GOOD -- use form helpers
test "creates item" do
  {:ok, view, _html} = live(conn, ~p"/items/new")
  view
  |> form("#item-form", item: %{title: "New"})
  |> render_submit()

  assert_redirect(view, ~p"/items/")
end
```

**Why:** Raw HTML matching breaks when CSS classes, attributes, or tag structure changes. Selectors (`has_element?/3`) and form helpers (`form/3`, `render_submit/1`) are resilient to markup changes.

### 3.7 Missing start_supervised! for Test Processes

**Severity:** BLOCK

```elixir
# BAD -- process outlives test, causes interference
test "worker does work" do
  {:ok, pid} = MyWorker.start_link([])
  # if test fails, pid is still running
end

# GOOD -- supervised, cleaned up automatically
test "worker does work" do
  pid = start_supervised!(MyWorker)
  # ExUnit stops the process when test ends, even on failure
end
```

**Why:** Unsupervised test processes leak. If a test fails, the process keeps running and can interfere with subsequent tests, causing cascading failures that are extremely hard to debug.

### 3.8 Oban Worker Args with Atom Keys

**Severity:** BLOCK

```elixir
# BAD -- Oban serializes args to JSON; atom keys become strings
test "enqueues notification job" do
  Notifications.notify(user_id: 1)

  assert_enqueued(worker: NotifyWorker, args: %{user_id: 1})
  # This may pass, but the worker receives %{"user_id" => 1}
end

# GOOD -- test with string keys to match runtime behavior
test "enqueues notification job" do
  Notifications.notify(user_id: 1)

  assert_enqueued(worker: NotifyWorker, args: %{"user_id" => 1})
end

# And in the worker:
def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
  # always match on string keys
end
```

**Why:** Oban serializes job args through JSON. All atom keys become strings. If your worker pattern-matches on atom keys, it will crash in production even though tests pass (if tests use atom keys).

### 3.9 Shared Test State

**Severity:** WARN

```elixir
# BAD -- setup_all shares state across tests
setup_all do
  user = user_fixture()
  quiz = quiz_fixture(owner: user)
  %{user: user, quiz: quiz}
end

test "test 1 modifies quiz", %{quiz: quiz} do
  Quizzes.update_quiz(quiz, %{title: "Changed"})
  # Now test 2 sees modified data!
end

# GOOD -- each test gets fresh data
setup do
  user = user_fixture()
  quiz = quiz_fixture(owner: user)
  %{user: user, quiz: quiz}
end
```

**Why:** `setup_all` runs once for all tests in the module. If any test modifies the shared data, subsequent tests see the modification. This creates order-dependent test failures.

### 3.10 LiveView Upload Testing

**Severity:** WARN

```elixir
# BAD -- skipping upload testing entirely

# GOOD -- test the full upload flow
test "uploads avatar", %{conn: conn, user: user} do
  {:ok, view, _html} = live(conn, ~p"/settings")

  avatar =
    file_input(view, "#profile-form", :avatar, [
      %{
        name: "avatar.jpg",
        content: File.read!("test/fixtures/avatar.jpg"),
        type: "image/jpeg"
      }
    ])

  assert render_upload(avatar, "avatar.jpg") =~ "avatar.jpg"

  assert {:error, {:redirect, %{to: "/settings"}}} =
           view
           |> form("#profile-form", %{})
           |> render_submit()
end
```

**Why:** Upload flows involve multiple steps (file selection, progress, consumption) that can each fail independently. Testing only the happy path without uploads misses a significant surface area.

## 4. Checklist

### Test Structure
- [ ] `describe` blocks group tests by function under test (`"function_name/arity"`)
- [ ] Each test follows Setup -> Action -> Assert pattern
- [ ] Test names describe the scenario, not the implementation
- [ ] `async: true` unless test uses global state

### Fixture Quality
- [ ] Fixtures return schemas, not `{:ok, schema}` tuples
- [ ] Fixtures accept `attrs` override with sensible defaults
- [ ] Unique values use `System.unique_integer()`
- [ ] Dependency chains are handled (parent fixtures create their own parents)
- [ ] One fixture module per context

### Coverage Categories
- [ ] Happy path tested
- [ ] Error cases (invalid input, not found, constraint violations)
- [ ] Edge cases (nil, empty string, Unicode, boundary values)
- [ ] Authorization (owner vs non-owner, different roles)
- [ ] Side effects (events, notifications, background jobs)

### LiveView Test Coverage
- [ ] Mount authorization (both allowed and denied)
- [ ] `phx-change` validation (shows errors for invalid input)
- [ ] `phx-submit` success (redirects or updates)
- [ ] `phx-submit` failure (shows changeset errors)
- [ ] Async states tested with `render_async/1`
- [ ] Uploads tested with `file_input/4` and `render_upload/2`

### Process Test Safety
- [ ] All test processes use `start_supervised!/1`
- [ ] No `Process.sleep` -- uses monitors, `assert_receive`, or `:sys.get_state`
- [ ] Mox uses `verify_on_exit!`
- [ ] Mox only mocks external boundaries behind behaviours

## 5. Templates

### 5.1 Test Module Template

```elixir
defmodule MyApp.AccountsTest do
  use MyApp.DataCase, async: true

  alias MyApp.Accounts
  alias MyApp.AccountsFixtures

  describe "register_user/1" do
    test "creates user with valid attributes" do
      attrs = AccountsFixtures.valid_user_attributes()

      assert {:ok, user} = Accounts.register_user(attrs)
      assert user.email == attrs.email
    end

    test "returns error for duplicate email" do
      %{email: email} = AccountsFixtures.user_fixture()
      attrs = AccountsFixtures.valid_user_attributes(email: email)

      assert {:error, %Ecto.Changeset{} = cs} = Accounts.register_user(attrs)
      assert %{email: ["has already been taken"]} = errors_on(cs)
    end
  end
end
```

### 5.2 DataCase Template

```elixir
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias MyApp.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import MyApp.DataCase
    end
  end

  setup tags do
    MyApp.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MyApp.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
```

Sharing sandbox connection with a spawned process:

```elixir
test "worker reads from sandbox" do
  pid = start_supervised!({MyApp.Worker, opts})
  Ecto.Adapters.SQL.Sandbox.allow(MyApp.Repo, self(), pid)
end
```

### 5.3 Factory Template (hand-rolled)

```elixir
defmodule MyApp.AccountsFixtures do
  alias MyApp.Accounts

  def unique_email, do: "user-#{System.unique_integer([:positive])}@example.com"

  def valid_user_attributes(overrides \\ %{}) do
    Enum.into(overrides, %{
      email: unique_email(),
      name: "Test User",
      password: "super-secret-password-123"
    })
  end

  def user_fixture(overrides \\ %{}) do
    {:ok, user} = overrides |> valid_user_attributes() |> Accounts.register_user()
    user
  end
end
```

If using ExMachina:

```elixir
defmodule MyApp.Factory do
  use ExMachina.Ecto, repo: MyApp.Repo

  def user_factory do
    %MyApp.Accounts.User{
      email: sequence(:email, &"user#{&1}@example.com"),
      name: "Test User",
      hashed_password: Bcrypt.hash_pwd_salt("password")
    }
  end
end
```

### 5.4 Mox — Full Pattern

```elixir
# 1. Behaviour
defmodule MyApp.EmailSender do
  @callback send(String.t(), String.t(), String.t()) :: {:ok, any()} | {:error, term()}
end

# 2. Real impl
defmodule MyApp.EmailSender.Swoosh do
  @behaviour MyApp.EmailSender
  @impl true
  def send(to, subject, body), do: # ... real Swoosh impl ...
end

# 3. test_helper.exs
Mox.defmock(MyApp.EmailSender.Mock, for: MyApp.EmailSender)

# 4. config/test.exs
config :my_app, :email_sender, MyApp.EmailSender.Mock

# 5. In the test
setup :verify_on_exit!

expect(MyApp.EmailSender.Mock, :send, fn to, subject, _body ->
  assert to == "user@example.com"
  {:ok, :sent}
end)
```

| Mox Call | Purpose |
|---|---|
| `expect(mock, :fun, n \\ 1, impl)` | Assert called exactly N times |
| `stub(mock, :fun, impl)` | Allow any number of calls (no verification) |
| `stub_with(mock, real_module)` | Delegate all callbacks to real impl |
| `verify_on_exit!()` | Fail test if expectations unmet |
| `allow(mock, parent_pid, child_pid)` | Let spawned process use the mock |

### 5.5 Controller Tests

```elixir
defmodule MyAppWeb.UserControllerTest do
  use MyAppWeb.ConnCase, async: true

  describe "GET /users/:id" do
    test "shows user", %{conn: conn} do
      user = user_fixture()
      conn = get(conn, ~p"/users/#{user.id}")
      assert html_response(conn, 200) =~ user.name
    end

    test "404 for missing user", %{conn: conn} do
      assert_error_sent :not_found, fn ->
        get(conn, ~p"/users/0")
      end
    end
  end
end
```

### 5.6 Channel Tests

```elixir
defmodule MyAppWeb.RoomChannelTest do
  use MyAppWeb.ChannelCase, async: true

  setup do
    {:ok, _, socket} =
      MyAppWeb.UserSocket
      |> socket("user_id", %{user_id: 42})
      |> subscribe_and_join(MyAppWeb.RoomChannel, "room:lobby")

    %{socket: socket}
  end

  test "broadcasts a message", %{socket: socket} do
    push(socket, "new:msg", %{body: "hello"})
    assert_broadcast "new:msg", %{body: "hello"}
  end
end
```

| Call | Purpose |
|---|---|
| `push(socket, event, payload)` | Simulate client push |
| `assert_push event, payload` | Server pushed to this socket |
| `assert_broadcast event, payload` | Broadcast to channel |
| `assert_reply ref, status, payload` | Reply to a push |

### 5.7 OTP Process Testing

```elixir
test "counter increments" do
  pid = start_supervised!({MyApp.Counter, limit: 10})
  assert :ok = MyApp.Counter.increment(pid)
  assert MyApp.Counter.value(pid) == 1
end

# Testing state via :sys.get_state (use sparingly)
test "worker holds registered names" do
  pid = start_supervised!({MyApp.Worker, []})
  MyApp.Worker.register(pid, "alice")
  state = :sys.get_state(pid)
  assert "alice" in state.names
end

# Trap exits to observe process deaths
test "worker exits cleanly on stop" do
  Process.flag(:trap_exit, true)
  pid = start_supervised!({MyApp.Worker, []})
  MyApp.Worker.stop(pid)
  assert_receive {:EXIT, ^pid, :normal}, 1_000
end
```

### 5.8 Assertion Patterns

```elixir
# Pattern match — extracts and asserts shape
assert {:ok, %User{id: id}} = Accounts.register_user(attrs)

# Pin operator
expected = "alice"
assert %{name: ^expected} = result

# Struct-specific
assert %Ecto.Changeset{valid?: false} = cs

# assert_raise
assert_raise ArgumentError, ~r/invalid email/, fn ->
  Accounts.register_user!(%{email: nil})
end

# Changeset errors
assert {:error, cs} = Accounts.register_user(attrs)
assert %{email: ["has already been taken"]} = errors_on(cs)

# Numeric
assert_in_delta actual, expected, 0.01

# Async messages
assert_receive {:done, result}, 1_000
refute_receive {:error, _}, 200
```

### 5.9 Property-Based Tests (StreamData)

```elixir
use ExUnitProperties

property "reverse is its own inverse" do
  check all string <- string(:printable) do
    assert string == string |> String.reverse() |> String.reverse()
  end
end
```

Generators: `string/1`, `integer/0-1`, `member_of/1`, `list_of/1`, `map_of/2`, `tuple/1`, `one_of/1`, `filter/2`, `bind/2`.

Use for: invariants (roundtrip, idempotence), parsers, serializers, validators.

### 5.10 Parametrized Tests (Elixir 1.18+)

```elixir
describe "parse/1" do
  parameterize([
    %{input: "42", expected: {:ok, 42}},
    %{input: "abc", expected: {:error, :invalid}},
  ])

  test "parses input", %{input: input, expected: expected} do
    assert MyApp.Parser.parse(input) == expected
  end
end
```

Pre-1.18 alternative: `for {input, expected} <- cases do test "..." do ... end end`

### 5.11 ExVCR — HTTP Recording

```elixir
use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

test "fetches repo stars" do
  use_cassette "github_stars" do
    assert {:ok, %{stars: n}} = MyApp.GitHub.get_stars("elixir-lang/elixir")
    assert n > 0
  end
end
```

First run records to `test/fixtures/cassettes/`. Subsequent runs replay. Use for integration tests against external APIs only — for your own boundaries, use Mox.

### 5.12 Wallaby — Browser Tests

```elixir
feature "user logs in and sees dashboard", %{session: session} do
  user = user_fixture()

  session
  |> visit("/login")
  |> fill_in(text_field("Email"), with: user.email)
  |> fill_in(text_field("Password"), with: "super-secret")
  |> click(button("Log in"))
  |> assert_has(css(".flash-info", text: "Welcome back"))
end
```

Keep feature tests to 5-20 per app. Each is expensive — for exhaustive validation, use LiveView/controller tests.

## 6. Routing

- **TDD workflow (Red/Green/Refactor)** -> load `tdd-workflow`
- **Ecto schema/query testing** -> load `ecto`
- **LiveView component testing** -> load `liveview-components`
- **Security/auth testing** -> load `security`
- **Worker testing** -> load `oban`
- **Test process patterns** -> load `otp`
- **Quality gates (formatter, dialyzer)** -> load `quality-gates`
