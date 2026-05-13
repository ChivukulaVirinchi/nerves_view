# Refactor Templates

> **Depth file for [SKILL.md](SKILL.md).** Load when writing review comments with suggested fixes. These are the top recurring refactors — copy/adapt them into review comments.

---

## 11.1 Extract pure function from GenServer

```elixir
# BEFORE
def handle_call({:apply_discount, code}, _from, state) do
  discount =
    case code do
      "SAVE10" -> Decimal.new("0.10")
      "SAVE20" -> Decimal.new("0.20")
      _ -> Decimal.new("0")
    end
  new_total = Decimal.mult(state.total, Decimal.sub(1, discount))
  {:reply, {:ok, new_total}, %{state | total: new_total}}
end

# AFTER — extract a pure module
defmodule MyApp.Pricing do
  def apply_discount(total, code), do: Decimal.mult(total, Decimal.sub(1, rate(code)))
  defp rate("SAVE10"), do: Decimal.new("0.10")
  defp rate("SAVE20"), do: Decimal.new("0.20")
  defp rate(_), do: Decimal.new("0")
end

def handle_call({:apply_discount, code}, _from, state) do
  new_total = MyApp.Pricing.apply_discount(state.total, code)
  {:reply, {:ok, new_total}, %{state | total: new_total}}
end
```

---

## 11.2 Replace try/rescue with ok/error

```elixir
# BEFORE
def parse(s) do
  try do
    {:ok, String.to_integer(s)}
  rescue
    ArgumentError -> {:error, :invalid}
  end
end

# AFTER
def parse(s) do
  case Integer.parse(s) do
    {int, ""} -> {:ok, int}
    {_, _rest} -> {:error, :trailing}
    :error -> {:error, :invalid}
  end
end
```

---

## 11.3 Replace nested case with with

```elixir
# BEFORE
case validate_email(params) do
  {:ok, email} ->
    case validate_password(params) do
      {:ok, pw} ->
        case create_user(email, pw) do
          {:ok, user} -> {:ok, user}
          {:error, r} -> {:error, r}
        end
      {:error, r} -> {:error, r}
    end
  {:error, r} -> {:error, r}
end

# AFTER
with {:ok, email} <- validate_email(params),
     {:ok, pw} <- validate_password(params),
     {:ok, user} <- create_user(email, pw) do
  {:ok, user}
end
```

---

## 11.4 Replace if/else dispatch with multi-clause

```elixir
# BEFORE
def handle(msg) do
  if is_map(msg) and Map.has_key?(msg, :type) do
    if msg.type == :error, do: handle_error(msg), else: handle_ok(msg)
  end
end

# AFTER
def handle(%{type: :error} = msg), do: handle_error(msg)
def handle(%{type: _} = msg), do: handle_ok(msg)
```

---

## 11.5 Replace single-step pipe into case

```elixir
# BEFORE
Enum.reduce_while(xs, {:ok, []}, fn ... end)
|> case do
  {:ok, acc} -> {:ok, Enum.reverse(acc)}
  {:error, _} = e -> e
end

# AFTER
result =
  Enum.reduce_while(xs, {:ok, []}, fn ... end)

case result do
  {:ok, acc} -> {:ok, Enum.reverse(acc)}
  {:error, _} = e -> e
end
```

---

## 11.6 Replace context-crossing Repo call

```elixir
# BEFORE — controller calling Repo directly
def index(conn, _) do
  products = Repo.all(Product)
  render(conn, :index, products: products)
end

# AFTER — through context
def index(conn, _) do
  products = MyApp.Catalog.list_products()
  render(conn, :index, products: products)
end
```

---

## 11.7 Replace spawn with supervised Task

```elixir
# BEFORE
spawn(fn -> send_notification(user) end)

# AFTER
Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
  send_notification(user)
end)

# In application.ex:
children = [
  {Task.Supervisor, name: MyApp.TaskSupervisor},
  # ...
]
```

---

## 11.8 Replace Process.sleep with assert_receive

```elixir
# BEFORE
send(pid, :work)
Process.sleep(100)
assert :done == GenServer.call(pid, :state)

# AFTER
send(pid, :work)
assert_receive {:completed, _}, 500
```

---

## 11.9 Tighten @spec

```elixir
# BEFORE — vague
@spec fetch(any()) :: any()
def fetch(id), do: ...

# AFTER — specific
@spec fetch(pos_integer()) :: {:ok, User.t()} | {:error, :not_found}
def fetch(id), do: ...
```

---

## 11.10 Replace short-circuit `with` chain with accumulating validation

**The dominant idiom**: `Ecto.Changeset` validators (`validate_required`, `validate_format`, `validate_length`, `validate_number`, etc.) are already **accumulating by design** — every validator that fires adds to `changeset.errors`. If the data is changeset-shaped (struct-with-fields, schema-backed), reach for the changeset before reaching for a manual reduce.

```elixir
# BEFORE — manual short-circuit on first error
def validate_signup(params) do
  with {:ok, email} <- validate_email(params),
       {:ok, password} <- validate_password(params),
       {:ok, age} <- validate_age(params) do
    {:ok, %{email: email, password: password, age: age}}
  end
end

# AFTER (idiomatic Elixir for any schema-backed data) — Ecto changeset
def validate_signup(params) do
  %Signup{}
  |> Ecto.Changeset.cast(params, [:email, :password, :age])
  |> Ecto.Changeset.validate_required([:email, :password, :age])
  |> Ecto.Changeset.validate_format(:email, ~r/@/)
  |> Ecto.Changeset.validate_length(:password, min: 8)
  |> Ecto.Changeset.validate_number(:age, greater_than_or_equal_to: 13)
end
# All validators always run; errors accumulate in changeset.errors;
# the LiveView form gets every error at once.
```

**When changeset isn't the right shape** — schemaless data (raw maps from external systems, batch import rows, multi-rule policy checks) — use the manual accumulating reduce:

```elixir
# AFTER (non-changeset) — manual accumulating reduce
def validate_signup_payload(params) do
  [
    {:email, &validate_email/1},
    {:password, &validate_password/1},
    {:age, &validate_age/1}
  ]
  |> Enum.reduce({%{}, []}, fn {key, validator}, {fields, errors} ->
    case validator.(params) do
      {:ok, value} -> {Map.put(fields, key, value), errors}
      {:error, reason} -> {fields, [{key, reason} | errors]}
    end
  end)
  |> case do
    {fields, []} -> {:ok, fields}
    {_, errors} -> {:error, Enum.reverse(errors)}
  end
end
```

**Decision rule**: if the data has (or will have) an Ecto schema, the changeset path is the answer — it IS the accumulating reduce, written once in a domain-friendly DSL. Reach for the manual form only when changesets don't fit (schemaless params, non-cast validators, custom error shapes).

---

## 11.11 Hoist expensive call to module attribute

```elixir
# BEFORE — Regex.compile! runs on every call
def valid_handle?(input) do
  rx = Regex.compile!("^[a-z][a-z0-9_]{2,15}$")
  Regex.match?(rx, input)
end

# AFTER — compile once at module load
@valid_handle_re Regex.compile!("^[a-z][a-z0-9_]{2,15}$")
def valid_handle?(input), do: Regex.match?(@valid_handle_re, input)
```

---

## 11.12 Wrap blocking HTTP in `start_async/3` + `handle_async/3`

```elixir
# BEFORE — LV freezes for the duration of the HTTP call
def handle_event("fetch_users", _params, socket) do
  {:ok, response} = Req.get("https://api.example.com/users")
  {:noreply, assign(socket, :users, response.body)}
end

# AFTER — LV stays responsive; result delivered via handle_async
def handle_event("fetch_users", _params, socket) do
  {:noreply,
   start_async(socket, :fetch_users, fn ->
     Req.get!("https://api.example.com/users").body
   end)}
end

def handle_async(:fetch_users, {:ok, users}, socket) do
  {:noreply, assign(socket, :users, users)}
end

def handle_async(:fetch_users, {:exit, reason}, socket) do
  {:noreply, put_flash(socket, :error, "Failed to load users: #{inspect(reason)}")}
end
```

---

## 11.13 Convert nested `Map.update` / `Map.put` to `update_in` / `put_in`

```elixir
# BEFORE — nested lambdas obscure the path (path already exists)
Map.update(state, :counts, %{}, fn counts ->
  Map.put(counts, :total, 1)
end)

# AFTER — Access path makes the structure explicit
put_in(state, [:counts, :total], 1)

# BEFORE — two-level update with computed value
Map.update(state, :a, %{}, fn a ->
  Map.update(a, :b, 0, fn n -> n + 1 end)
end)

# AFTER
update_in(state, [:a, :b], &(&1 + 1))
```

**When `put_in` / `update_in` does NOT apply** — the source `Map.update/4`'s 3rd argument (initial-value-when-missing) is non-trivial:

```elixir
# This is NOT equivalent to put_in — the %{name => value} default fires
# only when :body is missing from request, which put_in can't express:
Map.update(request, :body, %{name => value}, &Map.put(&1, name, value))

# OPTION A: keep the Map.update/4 form (genuinely cleanest when default matters)
# — flag as "false-positive" on Archdo 6.98 if reviewers ask.

# OPTION B: ensure the path is populated upstream, then use put_in
request = Map.put_new(request, :body, %{})
put_in(request, [:body, name], value)
```

The FP class for Archdo 6.98: two `Map.put`s where the second is in the *value* arg of the first but operates on a DIFFERENT map (e.g. `Map.put(outer, :key, Enum.reduce(xs, %{}, fn _, acc -> Map.put(acc, ...) end))` — `outer` and `acc` are independent). Read the diagnostic; only refactor when both `Map.put`s mutate the same structure.

---

## 11.14 Reorder args to subject-first

```elixir
# BEFORE — opts first; pipe composition broken
def discount(opts, price) do
  rate = Keyword.fetch!(opts, :rate)
  price * (1 - rate)
end

# Caller has to use `then/2` or split:
total = then(price, &discount(opts, &1))

# AFTER — subject first
def discount(price, opts) do
  rate = Keyword.fetch!(opts, :rate)
  price * (1 - rate)
end

# Caller pipes naturally:
total = price |> discount(opts)
```

---

## 11.15 Thread builder via pipes instead of rebinding

```elixir
# BEFORE — imperative-flavored rebinding
def transfer_with_audit(from, to, amount, user_id) do
  multi = Ecto.Multi.new()
  multi = Ecto.Multi.update(multi, :debit, debit_changeset(from, amount))
  multi = Ecto.Multi.update(multi, :credit, credit_changeset(to, amount))
  multi = Ecto.Multi.insert(multi, :audit, audit_changeset(user_id, from, to, amount))
  Repo.transaction(multi)
end

# AFTER — threading-builder shape
def transfer_with_audit(from, to, amount, user_id) do
  Ecto.Multi.new()
  |> Ecto.Multi.update(:debit, debit_changeset(from, amount))
  |> Ecto.Multi.update(:credit, credit_changeset(to, amount))
  |> Ecto.Multi.insert(:audit, audit_changeset(user_id, from, to, amount))
  |> Repo.transaction()
end
```

---

## 11.16 Extract effect to orchestrator (preserve building-block purity)

```elixir
# BEFORE — building-block module emits side effect inline
defmodule MyApp.Pricing do
  @moduledoc "Building block: pure pricing functions."
  require Logger

  def discount(price, rate) do
    Logger.info("calculating discount: rate=#{rate}")
    price * (1 - rate)
  end
end

# AFTER — building-block stays pure; orchestrator emits the effect
defmodule MyApp.Pricing do
  @moduledoc "Building block: pure pricing functions."
  def discount(price, rate), do: price * (1 - rate)
end

defmodule MyApp.Pricing.Workflow do
  @moduledoc "Orchestrates pricing — emits telemetry, persists, broadcasts."
  require Logger
  alias MyApp.Pricing

  def apply_discount(price, rate) do
    Logger.info("calculating discount: rate=#{rate}")
    Pricing.discount(price, rate)
  end
end
```

**Compound impurities — extract capabilities first.** Real modules rarely have just one impurity; the textbook BB+orchestrator split assumes a single Logger call but production code typically mixes hidden inputs (`Application.get_env`, `Endpoint.url()`) with non-determinism (`DateTime.utc_now`, `:rand.uniform`) AND with effects (`Logger`, `Repo`, `PubSub`). The naive split won't work — the "pure" half is still impure.

**Two-step refactor for compound impurities:**

```elixir
# BEFORE — three impurity classes mixed in (verified production case:
#          algora/lib/algora/bot_templates/bot_templates.ex)
defmodule MyApp.BotTemplates do
  @moduledoc false

  def placeholders(:bounty_created, user) do
    %{
      # HIDDEN INPUT (axis 1) — reads endpoint config from Application env
      "FUND_URL" => MyAppWeb.Endpoint.url(),
      "REPO_FULL_NAME" => "#{user.handle}/repo",
      "ATTEMPTS" => """
      | Attempt | Started (UTC) | Solution |
      | --- | --- | --- |
      | @jsmith | #{Calendar.strftime(DateTime.utc_now(), "%b %d, %Y")} | ... |
      #                            NON-DETERMINISM (axis 2)
      """,
      # ... more placeholders
    }
  end

  def get_template(org_id, type) do
    # EFFECT (axis 5) — reads from DB
    Repo.get_by(BotTemplate, user_id: org_id, type: type, active: true)
  end
end
```

**Step 1 — extract capabilities to arguments** (fixes axes 1, 2; the function is now PURE but still in the same module):

```elixir
defmodule MyApp.BotTemplates do
  @moduledoc false

  # Pure: takes the previously-hidden inputs as arguments
  def placeholders(:bounty_created, user, ctx) do
    %{
      "FUND_URL" => ctx.endpoint_url,                                # was Endpoint.url()
      "REPO_FULL_NAME" => "#{user.handle}/repo",
      "ATTEMPTS" => """
      | Attempt | Started (UTC) | Solution |
      | --- | --- | --- |
      | @jsmith | #{Calendar.strftime(ctx.now, "%b %d, %Y")} | ... |
      #                          now from ctx
      """
    }
  end

  # ctx struct bundles the capabilities (Reader-monad shape per
  # elixir-planning §4.7.4 / rule 22c)
  defmodule Ctx do
    @enforce_keys [:endpoint_url, :now]
    defstruct [:endpoint_url, :now]
  end

  # Effects still here — split next
  def get_template(org_id, type) do
    Repo.get_by(BotTemplate, user_id: org_id, type: type, active: true)
  end
end
```

**Step 2 — split BB / orchestrator** (fixes axis 5; orchestrator builds the ctx and calls the BB):

```elixir
defmodule MyApp.BotTemplates do
  @moduledoc "Building block: pure template rendering."
  defmodule Ctx do
    @enforce_keys [:endpoint_url, :now]
    defstruct [:endpoint_url, :now]
  end

  def placeholders(:bounty_created, user, %Ctx{} = ctx), do: ...
  def get_default_template(:bounty_created), do: ...
end

defmodule MyApp.BotTemplates.Workflow do
  @moduledoc "Orchestrates bot templates — builds ctx, hits Repo."
  alias MyApp.{BotTemplates, BotTemplates.Ctx, Repo}

  def render_for_user(type, user) do
    ctx = %Ctx{endpoint_url: MyAppWeb.Endpoint.url(), now: DateTime.utc_now()}
    BotTemplates.placeholders(type, user, ctx)
  end

  def get_template(org_id, type) do
    Repo.get_by(BotTemplate, user_id: org_id, type: type, active: true)
  end
end
```

**Why two steps, not one:** trying to do BB-split AND capability-extraction in one refactor produces a `MyApp.BotTemplates` module that's pure-shaped but still calls `Endpoint.url()` from inside — failing axis 1 silently. Step 1 makes the impurity explicit (it's now in arguments); Step 2 then has a real BB to extract. Reviewers should ask "what are ALL the impurity axes failed?" before suggesting the split — incomplete extraction wastes time.

**Cross-ref:** `elixir-planning/building-blocks.md` §3.1 (seven-axis checklist), `elixir-planning` §4.7.4 (capability passing / Reader-monad shape).

---

## 11.17 Replace `Enum.*` chain with `Stream.*` over a streamy source

```elixir
# BEFORE — fully materializes the file even though we only count
def count_errors(path) do
  path
  |> File.stream!()
  |> Enum.map(&String.trim/1)
  |> Enum.filter(&String.contains?(&1, "ERROR"))
  |> Enum.count()
end

# AFTER — constant memory regardless of file size
def count_errors(path) do
  path
  |> File.stream!()
  |> Stream.map(&String.trim/1)
  |> Stream.filter(&String.contains?(&1, "ERROR"))
  |> Enum.count()
end
```

---

## 11.18 Replace manual list-fold recursion with `Enum.reduce`

```elixir
# BEFORE — two-clause private function that's a fold in disguise
def total(transactions), do: do_sum(transactions, Decimal.new(0))

defp do_sum([], acc), do: acc
defp do_sum([%{amount: amt} | rest], acc), do: do_sum(rest, Decimal.add(acc, amt))

# AFTER — one line, named primitive
def total(transactions) do
  Enum.reduce(transactions, Decimal.new(0), fn %{amount: amt}, acc ->
    Decimal.add(acc, amt)
  end)
end
```

**When `Enum.reduce` does NOT apply** — verified against production code:

1. **3+ clauses with special-case handling** — e.g., `[], acc / [last], acc / [h | t], acc` where the last-element clause does something different (no separator, terminal marker). The `reduce` rewrite needs `Enum.with_index` or zip-with-tail tricks and is harder to read.
   ```elixir
   # Pleroma's build_csp_from_whitelist — last element has no leading space
   defp build([], acc), do: acc
   defp build([last], acc), do: [param(last) | acc]
   defp build([head | tail], acc), do: build(tail, [[?\s, param(head)] | acc])
   ```
   Keep manual recursion when special-casing is real.

2. **Macro-driven `defp` heads** — `for X <- @list do defp f([{unquote(X), _, _} | rest], acc) ...` dispatches on AST shape generated at compile time. `Enum.reduce` cannot pattern-match different shapes per element.

3. **Mutual recursion** — `defp parse_doc / defp parse_para / defp parse_inline` calling each other based on token. Not a fold.

Archdo 6.100 only flags the strict 2-clause `[], acc` + `[h | t], acc` pattern, which IS a clean fold. Verify the function actually has just two clauses before reaching for the refactor.

---

## Cross-References

- **Core reviewing skill:** [SKILL.md](SKILL.md) — rules, severity, workflows
- **Review checklists:** [review-checklists.md](review-checklists.md) — what to flag
- **Comment style + harvest loop:** [harvest-loop.md](harvest-loop.md)
- **Anti-patterns catalog:** [anti-patterns-catalog.md](anti-patterns-catalog.md)
