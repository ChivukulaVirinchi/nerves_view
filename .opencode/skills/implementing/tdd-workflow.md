---
name: implementing/tdd-workflow
description: >
  TDD workflow for Elixir — Red/Green/Refactor cycle, test-first vs test-after
  decision, outside-in TDD, bug-fix TDD, property-based TDD. For test templates,
  assertions, Mox, factories -> load testing.
---

# TDD Workflow — Red / Green / Refactor

Testing is not a phase after writing code. It is the loop you code inside. Every change to behavior is driven by a failing test.

## 1. The Core Cycle

1. **RED** — Write a failing test that describes the behavior you want. Run it. Confirm the failure matches your expectation.
2. **GREEN** — Write the *minimum* code that makes the test pass. Do not gold-plate.
3. **REFACTOR** — With tests green, improve the code: extract helpers, rename, remove duplication. Re-run tests after each change.
4. **Go back to RED** for the next behavior.

## 2. Canonical TDD Example

```elixir
# STEP 1 — RED: Write the test first (MyApp.Pricing does not yet exist)
defmodule MyApp.PricingTest do
  use ExUnit.Case, async: true

  describe "discount/2" do
    test "applies a percentage discount" do
      assert MyApp.Pricing.discount(100_00, 0.10) == 90_00
    end

    test "clamps the discount to the item price" do
      assert MyApp.Pricing.discount(50_00, 1.50) == 0
    end

    test "returns price unchanged for zero discount" do
      assert MyApp.Pricing.discount(75_00, 0.0) == 75_00
    end
  end
end
# Run: mix test — ALL THREE FAIL (module undefined)

# STEP 2 — GREEN: Minimum implementation
defmodule MyApp.Pricing do
  @spec discount(non_neg_integer(), float()) :: non_neg_integer()
  def discount(price_cents, rate) when rate >= 0 do
    max(0, price_cents - round(price_cents * rate))
  end
end
# Run again — three tests pass.

# STEP 3 — REFACTOR: Nothing to clean up. Next test case.
```

## 3. Decision: Tests First or After?

| Write Tests FIRST | Write Tests AFTER | Skip Tests |
|---|---|---|
| New public API function | UI / LiveView layout changes | One-off scripts with no reuse |
| Bug fix (reproduce as failing test) | HEEx template tweaks | Exploratory prototyping |
| Business logic with edge cases | Performance optimization (benchmark) | Temporary debug output |
| Refactor (characterization tests first) | Pure visual CSS changes | |
| Changeset validation | | |
| Multi-step `with` chain | | |
| Cross-context boundary call | | |

**Default:** tests first.

## 4. Outside-In TDD

Start from the public context API; let test failures guide you inward.

```elixir
# 1. Write a context-level test FIRST
test "register/1 creates user, sends welcome email" do
  Mox.expect(MyApp.Mailer.Mock, :send_welcome, fn %User{email: "a@b.com"} -> :ok end)

  assert {:ok, %User{email: "a@b.com"}} =
           Accounts.register(%{email: "a@b.com", password: "secret-pw-123"})
end

# 2. This tells you the shape of Accounts.register/1
# 3. Implement register/1, write unit tests for extracted helpers as you go
```

## 5. Bug-Fix TDD

Reproduce every bug as a failing test *before* fixing it.

```
1. User reports: "deleting a user with posts crashes"
2. Write test: create user, create posts, delete user, assert expected behavior
3. Confirm test fails with the actual bug
4. Fix the code. Test goes green.
5. Commit both the test AND the fix
```

## 6. Property-Based TDD

For invariant-driven code, define the invariant *before* the implementation.

```elixir
property "encode then decode is the identity" do
  check all value <- term() do
    assert value == value |> MyCodec.encode() |> MyCodec.decode() |> elem(1)
  end
end
```

## 7. Fast Feedback

```bash
mix test test/my_app/pricing_test.exs:18  # Single test
mix test --failed                          # Re-run failures
mix test --stale                           # Changed modules only
mix test --max-failures 1                  # Stop at first failure
mix test.watch                             # Continuous (needs mix_test_watch)
```

## 8. TDD Anti-Patterns

```elixir
# BAD — testing implementation details
test "Accounts.register calls Repo.insert" do ... end

# GOOD — test observable behavior
test "Accounts.register persists the user" do
  assert {:ok, %User{id: id}} = Accounts.register(@valid_attrs)
  assert Repo.get(User, id)
end
```

```elixir
# BAD — one test asserting five unrelated things
test "user flow" do
  # create, email, update, delete, audit
end

# GOOD — small focused tests
describe "register/1" do
  test "creates user with hashed password" do ... end
  test "sends welcome email" do ... end
end
```

## 9. TDD Rules

1. **ALWAYS pass the TDD gate (§0) before writing a new public function.**
2. **ALWAYS write the minimum** to go green. Write the next test before generalizing.
3. **NEVER test private functions directly** — test via the public API.
4. **NEVER assert implementation details.** Assert observable behavior.
5. **ALWAYS reproduce every bug as a failing test** before fixing.
6. **PREFER `async: true`** unless test uses shared global state.
7. **ALWAYS enforce test-first at milestone boundaries** in long sessions.

## 10. Routing

- **Test templates, assertions, Mox, factories** -> load `testing`
- **Ecto-specific testing** -> load `ecto`
- **LiveView testing** -> load `liveview`
