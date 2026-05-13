---
name: implementing/critical-patterns
description: >
  Critical patterns Claude commonly gets wrong in Elixir — pipelines, pattern matching,
  with chains, comprehensions, recursion, guards, IO lists, struct updates, LiveView streams,
  composition patterns, security (ETF, eval, apply), Logger metadata, secret Inspect, error sanitization,
  event versioning.
  ALWAYS use when writing pipelines, with chains, or composition patterns.
---

# Critical Patterns Claude Commonly Gets Wrong

> **Parent:** [SKILL.md](SKILL.md) — implementing routing core.

These are the patterns that separate idiomatic Elixir from "Elixir-shaped imperative code." Each subsection gives the idiomatic template first, then variations, then a common-mistake BAD/GOOD.

---

### 5.1 Pipelines — the subject-first discipline

**Idiomatic template:**

```elixir
# A pipeline is a sequence of transformations on a primary subject.
# The subject is always the first argument of each step.
raw_input
|> String.trim()
|> String.split("\n")
|> Enum.reject(&(&1 == ""))
|> Enum.map(&parse_line/1)
|> Enum.group_by(& &1.category)
|> Map.new(fn {k, v} -> {k, length(v)} end)
```

**Rules of thumb:**

- 2+ transformations → pipeline
- Exactly 1 → direct call
- The first value in the pipeline is the *subject*; every function after must take it as its first argument
- One pipe per line; never `a |> b() |> c()` inlined

**Variations:**

```elixir
# tap/1 — side effect without breaking the pipeline (returns input unchanged)
order
|> calculate_total()
|> tap(&Logger.debug("Total: #{&1}"))
|> apply_tax()

# then/2 — when the next step is not first-arg-compatible
cfg
|> Map.get(:timeout, 5_000)
|> then(&Process.send_after(self(), :check, &1))

# Conditional step — maybe_X/2 helper, keeps pipeline flat
data
|> transform()
|> maybe_validate(opts[:validate])
|> finalize()

defp maybe_validate(data, true), do: validate(data)
defp maybe_validate(data, _), do: data

# Piping into case — only at the END of a multi-step pipeline
conn
|> fetch_session("user_token")
|> case do
  nil -> assign(conn, :current_user, nil)
  token -> assign(conn, :current_user, Accounts.get_user_by_token(token))
end
```

**BAD/GOOD:**

```elixir
# BAD — single-step pipe
name |> String.upcase()
# GOOD — direct call
String.upcase(name)
```

```elixir
# BAD — piping into a lone reduce_while + case (single step)
Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
  case validate(item) do
    {:ok, v} -> {:cont, {:ok, [v | acc]}}
    {:error, _} = e -> {:halt, e}
  end
end)
|> case do
  {:ok, acc} -> {:ok, Enum.reverse(acc)}
  {:error, _} = error -> error
end

# GOOD — intermediate variable, then case
result =
  Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
    case validate(item) do
      {:ok, v} -> {:cont, {:ok, [v | acc]}}
      {:error, _} = e -> {:halt, e}
    end
  end)

case result do
  {:ok, acc} -> {:ok, Enum.reverse(acc)}
  {:error, _} = error -> error
end
```

```elixir
# BAD — piping into an anonymous function (awkward)
data |> (fn x -> x * 2 end).()
# GOOD — use then/1
data |> then(&(&1 * 2))
```

```elixir
# BAD — multiple pipes on one line
list |> Enum.map(&process/1) |> Enum.sum()
# GOOD — one pipe per line
list
|> Enum.map(&process/1)
|> Enum.sum()
```

### 5.2 Pattern matching in function heads

**Idiomatic template:**

```elixir
# Multi-clause dispatch on data shape — most powerful Elixir feature.
# Each clause handles a specific case. The compiler warns on unmatched cases.
def handle_event(%Click{x: x, y: y}), do: on_click(x, y)
def handle_event(%Submit{form: form}), do: on_submit(form)
def handle_event(%KeyDown{key: "Escape"}), do: cancel()
def handle_event(%KeyDown{key: key}), do: on_key(key)
def handle_event(unknown), do: {:error, {:unknown_event, unknown}}

# Guards refine the match
def process(n) when is_integer(n) and n > 0, do: :positive
def process(n) when is_integer(n) and n < 0, do: :negative
def process(0), do: :zero
def process(n) when is_float(n), do: :float
def process(_), do: :not_a_number
```

**Canonical shapes:**

```elixir
# Tagged tuples — result dispatch
def handle({:ok, value}), do: process(value)
def handle({:error, reason}), do: log_error(reason)

# Nested destructure — pull deep fields in the head
def city(%User{address: %Address{city: city}}), do: {:ok, city}
def city(_), do: {:error, :no_city}

# Pin to match against an existing variable (NOT bind)
expected_id = 42
case event do
  %{user_id: ^expected_id} -> :match
  _ -> :no_match
end

# Keep the whole struct bound while also destructuring fields
def greet(%User{name: name} = user), do: "Hello #{name}, id=#{user.id}"
```

**BAD/GOOD:**

```elixir
# BAD — if/else dispatching on shape
def handle(msg) do
  if is_map(msg) and Map.has_key?(msg, :type) do
    if msg.type == :error, do: handle_error(msg), else: handle_ok(msg)
  end
end

# GOOD — multi-clause with pattern
def handle(%{type: :error} = msg), do: handle_error(msg)
def handle(%{type: _} = msg), do: handle_ok(msg)
```

```elixir
# BAD — forgetting the pin, variable rebinds and matches ANYTHING
target = 42
case x do
  target -> :match     # Always matches; `target` rebinds to x
end

# GOOD — pin operator
target = 42
case x do
  ^target -> :match
  _ -> :no_match
end
```

```elixir
# BAD — %{} matches ANY map, not just empty
def classify(%{}), do: :empty
# GOOD — guard for empty map
def classify(map) when map_size(map) == 0, do: :empty
def classify(_), do: :non_empty
```

### 5.3 with — chaining ok/error operations

**Idiomatic template:**

```elixir
def create_order(user_id, product_id, qty) do
  with {:ok, user} <- Users.get(user_id),
       {:ok, product} <- Products.get(product_id),
       :ok <- validate_stock(product, qty),
       {:ok, order} <- insert_order(user, product, qty) do
    {:ok, order}
  end
end
```

**When to use else:**

Only when you need to *transform* the error on the way out. Otherwise omit the `else` — the first non-matching value is returned as-is.

```elixir
def create_order(user_id, product_id, qty) do
  with {:ok, user} <- Users.get(user_id),
       {:ok, product} <- Products.get(product_id),
       :ok <- validate_stock(product, qty),
       {:ok, order} <- insert_order(user, product, qty) do
    {:ok, order}
  else
    {:error, :not_found} -> {:error, :resource_not_found}
    {:error, :insufficient_stock} -> {:error, :out_of_stock}
    # Any other {:error, _} falls through unchanged
  end
end
```

**Tagged-tuple with — label each clause for precise error handling:**

```elixir
# Use when several steps can return the same error shape and you need
# to distinguish which step failed.
with {:user, {:ok, user}} <- {:user, fetch_user(id)},
     {:auth, :ok} <- {:auth, authorize(user, action)},
     {:save, {:ok, result}} <- {:save, save(user)} do
  {:ok, result}
else
  {:user, {:error, _}} -> {:error, :user_not_found}
  {:auth, {:error, _}} -> {:error, :unauthorized}
  {:save, {:error, changeset}} -> {:error, changeset}
end
```

**BAD/GOOD:**

```elixir
# BAD — nested case
def register(params) do
  case validate_email(params) do
    {:ok, email} ->
      case validate_password(params) do
        {:ok, password} ->
          case create_user(email, password) do
            {:ok, user} -> {:ok, user}
            {:error, reason} -> {:error, reason}
          end
        {:error, reason} -> {:error, reason}
      end
    {:error, reason} -> {:error, reason}
  end
end

# GOOD — with chain
def register(params) do
  with {:ok, email} <- validate_email(params),
       {:ok, password} <- validate_password(params),
       {:ok, user} <- create_user(email, password) do
    {:ok, user}
  end
end
```

```elixir
# BAD — with for a single op (overkill, harder to read)
with {:ok, user} <- Accounts.fetch(id) do
  process(user)
end

# GOOD — case for a single op
case Accounts.fetch(id) do
  {:ok, user} -> process(user)
  {:error, _} = e -> e
end
```

### 5.4 Comprehensions — `for` when it wins over pipelines

Use `for` when you're doing one or more of:

- Pattern-matching generators (silent skip on non-match)
- Collecting into a specific type (`into:`)
- Accumulator with tuple/map state (`reduce:`)
- Multiple generators (Cartesian / nested iteration)
- Binary iteration (`<<byte <- data>>`)
- Deduplication (`uniq: true`)

```elixir
# Pattern in generator — skip non-successful results silently
for {:ok, value} <- results, do: value

# into: MapSet — build a set in one pass
for app <- apps, module <- Application.spec(app, :modules), into: MapSet.new(), do: module

# Binary comprehension — iterate bytes
for <<byte <- string>>, byte not in ?\s..?~, into: "", do: <<byte>>

# reduce: — tuple accumulator in one pass
for {name, field} <- fields, reduce: {[], []} do
  {keep, drop} ->
    case field.writable do
      :always -> {[name | keep], drop}
      _ -> {keep, [name | drop]}
    end
end

# Multiple generators — cross product
for x <- 1..3, y <- 1..3, x <= y, do: {x, y}
#=> [{1,1}, {1,2}, {1,3}, {2,2}, {2,3}, {3,3}]

# uniq: true — inline deduplication
for type_expr <- args, var <- collect_vars(type_expr), uniq: true, do: var
```

### 5.5 Recursion — the third iteration tool

> **Depth:** [idioms-reference.md](idioms-reference.md) §Recursion — Last Call Optimization (LCO) explained with tail-position precision table, body-vs-tail trade-offs with modern BEAM/JIT performance nuance, accumulator-reverse pattern, binary-pattern recursion, tree traversal, mutual recursion, recursion-vs-`reduce_while` decision, wrapping recursive walkers as lazy streams.

Recursion is **a first-class iteration tool in Elixir**, not a fallback. A tail-recursive function with pattern matching is the functional equivalent of an imperative `while` loop — constant stack, pattern-dispatch on the state.

**When recursion is the right answer:**

- **Long-running loops** — GenServer message loops, TCP accept loops, retry loops. Elixir's idiomatic `while (true)`.
- **Early termination** with halt conditions spanning multiple accumulators (simple cases fit `Enum.reduce_while`).
- **Tree / graph / AST traversal** where the structure is genuinely recursive.
- **Binary decoders** — `<<byte, rest::binary>> = data; decode(rest)` is the dominant BEAM-optimized pattern for parsers.
- **Parsers and walkers** where each element shapes what you do with the next.
- **Infinite / lazy generation** — wrapped in `Stream.iterate`/`Stream.unfold`/`Stream.resource`.
- **Custom enumeration** — implementing `Enumerable`.

**Tail vs body recursion — both are first-class.** The Erlang Efficiency Guide (*Seven Myths of Erlang Performance*) explicitly says: *"Use the version that makes your code cleaner (hint: it is usually the body-recursive version)."* Since R12B, body-recursive list construction uses the same memory as tail + reverse. The stdlib's `:lists.map/2`, `:lists.filter/2`, and list comprehensions are all body-recursive by choice.

**When each is right:**

| Situation | Prefer |
|---|---|
| Unbounded / adversarial input (user lists, streams) | **Tail** — guaranteed constant stack |
| Long-running process loop | **Tail** — MUST (never terminates) |
| Known-bounded structure (tree, AST, expression grammar, recurrence) | **Body** — clearer, often the better choice |
| List transformation where order matters | Either — body-recursive is often cleaner; tail + reverse is explicit |
| Modern OTP (24+) with JIT, performance matters | Benchmark — JIT has reversed some pre-JIT rules of thumb |

**The while-loop analogy:**

```elixir
# Imperative: while (running) { msg = receive(); handle(msg); }
def loop(state) do
  receive do
    :stop -> :ok
    msg -> msg |> handle(state) |> loop()      # tail call — constant stack
  end
end

# Imperative: while (!done) { if (try_work()) break; sleep(); }
def retry(attempt \\ 1) do
  case work() do
    {:ok, r} -> {:ok, r}
    {:error, _} when attempt >= @max -> {:error, :exhausted}
    {:error, _} -> Process.sleep(backoff(attempt)); retry(attempt + 1)
  end
end
```

**Tail-position gotchas** (where LCO silently DOESN'T apply — see idioms-reference for full list):

- `with ... else ...` — the `else` clause keeps the result for re-matching; final call is NOT tail.
- `try do ... end` — the protected `do` body is NOT tail position (stacktrace is kept).
- Arithmetic / construction around the call: `[x | recur(t)]` is body-recursive (fine for bounded input; not "broken").

**BAD/GOOD:**

```elixir
# Body-recursive — fine for reasonable inputs; stdlib :lists.map works exactly this way
def double_all([]), do: []
def double_all([h | t]), do: [h * 2 | double_all(t)]

# Tail-recursive + reverse — use when input may be unbounded
def double_all(list), do: do_double_all(list, [])
defp do_double_all([], acc), do: Enum.reverse(acc)
defp do_double_all([h | t], acc), do: do_double_all(t, [h * 2 | acc])

# Usually clearest — let Enum handle bounded-list work
def double_all(list), do: Enum.map(list, &(&1 * 2))
```

**Real anti-patterns (these ARE broken):**

```elixir
# BAD — O(n²) from append in accumulator
defp build([], acc), do: acc
defp build([h | t], acc), do: build(t, acc ++ [process(h)])   # ++ on left operand!

# BAD — reimplementing Enum.map
def each_squared(list), do: do_each_squared(list, [])
defp do_each_squared([], acc), do: Enum.reverse(acc)
defp do_each_squared([h | t], acc), do: do_each_squared(t, [h * h | acc])
# → just write: Enum.map(list, &(&1 * &1))
```

### 5.6 Guards — constraints at the function boundary

```elixir
# Combine guard clauses with `when` — comma = AND, `when ... when ...` = OR
def valid?(x) when is_integer(x) and x >= 0 and x <= 100, do: true
def valid?(_), do: false

# Multiple when = OR — cleaner than long `or` chains
def is_escape_char(c)
    when c in 0x2061..0x2064
    when c in [0x061C, 0x200E, 0x200F]
    when c in 0x202A..0x202E,
    do: true

# Custom guards (defguard) — reusable, composable
defguard is_positive_int(n) when is_integer(n) and n > 0
defguard is_non_empty_str(s) when is_binary(s) and byte_size(s) > 0

def create(%{age: age, name: name}) when is_positive_int(age) and is_non_empty_str(name) do
  {:ok, %User{age: age, name: name}}
end

# Allowed in guards (partial list): is_*, ==, !=, <, >, in, and/or/not,
# +, -, *, /, abs, div, rem, round, trunc, byte_size, elem, hd, tl, length,
# map_size, tuple_size, is_map_key, Bitwise operators (after `import Bitwise`)

# NOT allowed in guards: String.length, Enum.*, any user-defined function
# (except via defguard)
```

**Idiomatic use — guard on struct field without binding the whole struct:**

```elixir
# When you care about one field of a large struct, guard on dot-access
def active?(strategy) when strategy.enabled? and strategy.version >= 2, do: true
def active?(_), do: false
```

### 5.7 IO lists — building binaries without O(n²)

```elixir
# Nested lists of binaries, integers (bytes), or other IO lists.
# Accepted by File.write/2, IO.puts/1, :gen_tcp.send/2, etc.

# Build by prepending (O(1))
iolist = ["last", ", ", "middle", ", ", "first"]
# Flatten only when you need a real binary
binary = IO.iodata_to_binary(iolist)

# Build a CSV row without concatenation
row = [name, ",", amount_str, ",", date, "\n"]

# Join with separator via map_join
csv = Enum.map_join(rows, "\n", fn row -> Enum.join(row, ",") end)

# Build via comprehension
headers = for {k, v} <- headers, into: "", do: "#{k}: #{v}\r\n"
```

**BAD/GOOD:**

```elixir
# BAD — O(n²) — each <> copies the entire growing string
Enum.reduce(rows, "", fn row, acc -> acc <> format(row) <> "\n" end)

# GOOD — IO list, single binary at the end
rows
|> Enum.map(fn row -> [format(row), "\n"] end)
|> IO.iodata_to_binary()

# ALSO GOOD — map_join for a simple case
Enum.map_join(rows, "\n", &format/1)
```

### 5.8 Struct updates — the `%{struct | field: v}` syntax

```elixir
# Update existing key — compile-time check that the field exists
%User{name: "Jane", age: 30}
|> then(fn u -> %{u | age: u.age + 1} end)

# Struct update with multiple fields
%{user | name: new_name, updated_at: DateTime.utc_now()}

# Nested update via put_in/update_in
put_in(order.shipping.address.city, "New City")
update_in(order.items, &Enum.map(&1, fn item -> %{item | price: item.price * 0.9} end))
```

**BAD/GOOD:**

```elixir
# BAD — Map.put silently accepts typos
%{user | nmae: "Jane"}     # Compile error: key :nmae not in struct User
Map.put(user, :nmae, "Jane")  # No error! Silently adds :nmae to the struct

# GOOD — update syntax for existing fields
%{user | name: "Jane"}
```

### 5.9 LiveView streams do NOT react to external assign changes

A stream row's DOM is only re-rendered when you call `stream_insert/3,4` with that row. Updating a *separate* assign — even one the row template reads — will NOT redraw existing stream rows. This is a core performance optimization of streams: they don't re-render everything on every assign change. It is also the most common LiveView trap.

```elixir
# BAD — device_states is a separate assign; changing it does NOT re-render stream rows
def mount(_, _, socket) do
  socket =
    socket
    |> stream(:devices, Fleet.list_devices())
    |> assign(:device_states, %{})
  {:ok, socket}
end

def handle_info({:device_state_changed, id, new_state}, socket) do
  # Stream rows still show the OLD state — the row DOM isn't re-emitted
  {:noreply, update(socket, :device_states, &Map.put(&1, id, new_state))}
end
```

```elixir
# GOOD — the state lives ON the stream member, and we re-insert on change
def mount(_, _, socket) do
  {:ok, stream(socket, :devices, Fleet.list_with_state())}
  # list_with_state/0 returns %Device{current_state: ...} with virtual field populated
end

def handle_info({:device_state_changed, id, new_state}, socket) do
  device = Fleet.get_device_with_state!(id)
  # stream_insert updates the row in-place — this triggers re-render
  {:noreply, stream_insert(socket, :devices, device)}
end
```

**When state is computed outside the stream** (e.g., cluster-wide presence, a cross-context derivation), either:
1. Attach it to the stream member via a virtual schema field populated by the context query (`Ecto.Schema` `field :current_state, :map, virtual: true`), or
2. Wrap the row payload in a plain map (`%{device: device, state: state}`) and use that as the stream member.

Then make every `handle_info` that can change the row's appearance call `stream_insert/3,4` with the updated member. `assign`-only updates to unrelated keys will not redraw the row.

This is one of the highest-impact LV gotchas — it often drives architectural rework (virtual field on the schema, `list_with_state/1` context function with `DISTINCT ON`, etc.). Design for it at planning time; don't discover it in a test failure.

### 5.10 Composition Patterns — `with` as Elixir's railway

**Composition is how Elixir code becomes maintainable: small functions that snap together because their outputs and inputs match.** Five composition primitives map across most production code. Each has a canonical Elixir form — none of these requires a library; they're idiomatic uses of stdlib.

**Building-blocks first, composition second.** Every pattern in this section delivers its full payoff only when the underlying functions are building-blocks (see `elixir-planning/building-blocks.md`): pure (axes 1–6) and input-guarded (axis 7). Composition over impure code wires functions together but doesn't deliver the property-test, memoize, or local-reasoning payoffs. The slogan: **build building-blocks, then COMPOSE them.** Concrete dependencies:

- Railway / `with`-chain (§5.10.1) requires steps to return ok/error, never raise → axis 6 (errors-as-values).
- `Result.map` / functor (§5.10.5) maps a pure transform → axes 1, 5, 6.
- Applicative validation (§5.10.6) accumulates errors from independent pure validators → axes 1, 5, 6.
- Effects-as-data (§5.10.7) is the *only* honest way for a building-block to communicate "this should happen" without doing it → axis 5.
- Capability passing (§5.10.8) IS axis 1 (input closure) restated as a composition pattern.
- Lens / `update_in` (§5.10.9) requires the update to be pure → axis 5.
- Subject-position discipline (§5.10.10) is what makes building-block functions pipeable.

If you find yourself reaching for one of these patterns and the surrounding module isn't a building-block, the answer is rarely "compose anyway" — it's usually "extract a building-block first" (§building-blocks.md §5 / §6.4).

#### 5.10.1 Railway-Oriented `with` chain — the dominant pattern

In F# / Haskell terminology, **railway-oriented programming** (Wlaschin) routes a value down a "success track" through a series of operations; the moment any step fails, the value drops to the "failure track" and skips the rest. Elixir's `with` IS the railway. Each `<-` arrow is a track switch:

```elixir
def register_user(attrs) do
  with {:ok, valid_attrs}    <- validate(attrs),
       {:ok, hashed_attrs}   <- hash_password(valid_attrs),
       {:ok, user}           <- insert(hashed_attrs),
       :ok                   <- send_welcome_email(user) do
    {:ok, user}
  end
end
```

**Anatomy of the railway:**
- Each `<-` is a step on the success track. If the LHS pattern matches the RHS, the chain continues with the bound value.
- If ANY step's RHS doesn't match — typically because it returned `{:error, _}` — the `with` short-circuits. The non-matching value is the return value of the whole expression.
- **Bare `with` (no `else`) propagates errors transparently.** This is the cleanest railway shape. Don't add an `else` unless you need to *transform* the error on the way out.
- Mix step shapes: `{:ok, _}` for value-returning steps, `:ok` for confirmation-only steps. Both are valid railway stops.

**Building-block prerequisite:** the railway only works because each step returns ok/error tuples and never raises. That's axis 6 of the building-block checklist (`elixir-planning/building-blocks.md` §3.1). If a step in your chain raises on failure (e.g., a non-bang function that internally calls `Repo.one!`), the railway derails: the raise blows past `with` and propagates as an exception. Either change the step to return `{:error, _}` or wrap it at a boundary with `try`/`rescue` that converts. Pure building-block steps make railways trustworthy; ad-hoc impure steps make them brittle.

**Why bare `with` is preferred:**
- No mental overhead reading the success path: it's straight-line.
- LCO-safe — `with...else` rebinds the result for re-matching, breaking last-call optimization (idioms-reference.md §With Chains).
- Errors from any step keep their original shape, which downstream callers pattern-match.

#### 5.10.2 When to add `else` — transforming errors at the boundary

Use `else` ONLY when downstream callers expect a specific error shape that internal steps don't produce. The `else` is an error translator:

```elixir
def public_api(input) do
  with {:ok, parsed} <- Parser.parse(input),
       {:ok, valid}  <- Validator.check(parsed),
       {:ok, stored} <- Repo.insert(valid) do
    {:ok, stored}
  else
    {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
    {:error, %Ecto.Changeset{} = cs} -> {:error, errors_on(cs)}
    # Other {:error, _} fall through unchanged
  end
end
```

The `else` only catches FAILURE-track values; success goes to the `do` block. Don't use `else` to handle success cases — that's a sign the chain has too many concerns; split it.

#### 5.10.3 Tagged-tuple `with` — labeling which step failed

When multiple steps return the same shape (`{:error, :not_found}` from any of three lookups), wrap each step in a tag tuple to distinguish:

```elixir
def transfer(from_id, to_id, amount) do
  with {:from,  {:ok, from_acct}} <- {:from, Accounts.fetch(from_id)},
       {:to,    {:ok, to_acct}}   <- {:to,   Accounts.fetch(to_id)},
       {:funds, :ok}               <- {:funds, check_funds(from_acct, amount)},
       {:tx,    {:ok, tx}}         <- {:tx, Ledger.post(from_acct, to_acct, amount)} do
    {:ok, tx}
  else
    {:from, {:error, :not_found}}  -> {:error, :source_not_found}
    {:to, {:error, :not_found}}    -> {:error, :dest_not_found}
    {:funds, {:error, reason}}     -> {:error, {:funds, reason}}
    {:tx, {:error, _} = err}       -> err
  end
end
```

The tag is the step name; the `else` translates by step. This is the Elixir adaptation of Wlaschin's "two-track functions with named lanes" — it lets the failure track carry which switch threw it.

#### 5.10.4 Chain length signals architectural drift

| Chain length | Diagnosis | Action |
|---|---|---|
| 2–4 steps | Healthy railway — keep as-is | None |
| 5–6 steps | Approaching the limit | Look for sub-chain opportunities to extract as their own `with`-returning helper |
| 7+ steps | The function is doing too much | Split into named phases (`prepare/1`, `commit/1`); orchestrator calls each |
| Deep chains spanning Repo + HTTP + PubSub | Process orchestration smell | Consider Oban (durability), Saga (compensating actions), or event sourcing |

**Rule of thumb:** if the chain contains a Repo write AND an HTTP call AND a PubSub broadcast, it's no longer a railway — it's an integration. Move it to an Oban worker (or a saga) so the failure track can compensate, not just abort.

#### 5.10.5 Result.map / functor — single-step transforms inside the railway

When a step's success value needs ONE transform applied with no further failure cases, `with` is the right tool — but the transform itself is a `Result.map`-shaped operation. Don't reach for an external library; use bare `with`:

```elixir
# BAD — verbose case mimicking case-of-Result
def parse_count(input) do
  case Integer.parse(input) do
    {n, ""} -> {:ok, n * 2}
    _ -> {:error, :invalid}
  end
end

# GOOD — `with` clause expresses the same transform on the success track
def parse_count(input) do
  with {n, ""} <- Integer.parse(input) do
    {:ok, n * 2}
  end
end

# Or when chaining multiple maps:
def normalize_and_double(input) do
  with {:ok, n}   <- parse_int(input),
       doubled    = n * 2,
       {:ok, str} <- format(doubled) do
    {:ok, str}
  end
end
```

The `=` clause inside `with` is a pure binding (no track switch — it always succeeds). Use it for "compute this from the success value" steps that don't fail.

If a project has 5+ identical `case` patterns mimicking Result.map, define a project-local helper:

```elixir
defmodule MyApp.Result do
  def map({:ok, v}, fun), do: {:ok, fun.(v)}
  def map({:error, _} = e, _), do: e

  def map_error({:error, e}, fun), do: {:error, fun.(e)}
  def map_error({:ok, _} = ok, _), do: ok
end
```

But prefer `with` chains when possible — they read closer to the railway and don't force a new vocabulary.

#### 5.10.6 Applicative validation — accumulating errors instead of short-circuiting

`with` is a **monadic** chain — it short-circuits on the first failure. For independent validations whose errors should ALL be reported (form validation, batch import, multi-field check), short-circuiting is the wrong semantics. Use a reduce-based accumulator:

```elixir
# BAD — short-circuits; user fixes one error, gets another, fixes that, gets another...
def validate(attrs) do
  with :ok <- check_email(attrs),
       :ok <- check_password(attrs),
       :ok <- check_age(attrs) do
    {:ok, attrs}
  end
end

# GOOD — accumulates; user sees all errors at once
def validate(attrs) do
  errors =
    [
      check_email(attrs),
      check_password(attrs),
      check_age(attrs)
    ]
    |> Enum.flat_map(fn
      :ok -> []
      {:error, e} -> [e]
    end)

  case errors do
    [] -> {:ok, attrs}
    errs -> {:error, errs}
  end
end
```

`Ecto.Changeset` does this implicitly — its `traverse_errors/2` accumulates field-level errors. When you control the validators, the explicit reduce pattern works.

**Decision: short-circuit (`with`) vs accumulate (reduce):**

| Use short-circuit `with` when... | Use accumulate-reduce when... |
|---|---|
| Each step depends on the previous step's value | Steps are independent (validate field A independently of B) |
| Failure is rare (happy-path optimization) | Failure is common AND the user fixes errors interactively (forms) |
| Cost of running a failed step is high (DB write, network call) | All steps are cheap (in-memory predicates) |
| Aborting early is correct semantics (transactional) | "All errors at once" is the better UX |

#### 5.10.7 Effects-as-data — return events, let the orchestrator emit

A building-block (see elixir-planning building-blocks.md) doesn't emit side effects. But the building-block KNOWS what should happen — "this user should get a welcome email", "this metric should be incremented". The pattern: return the events as data; the orchestrator interprets:

```elixir
# Building-block: pure decision + event description
defmodule MyApp.Accounts.Rules do
  @moduledoc "Building block — decides what registration should do."

  @spec register(map(), salt :: String.t()) ::
          {:ok, Ecto.Changeset.t(), [event]} | {:error, :invalid}
        when event: {:emit, atom(), map()} | {:send, atom(), map()}
  def register(attrs, salt) do
    cs = User.changeset(%User{}, Map.put(attrs, :salt, salt))

    case cs.valid? do
      true ->
        events = [
          {:emit, :user_registered, %{email: cs.changes.email}},
          {:send, :welcome_email, %{email: cs.changes.email}}
        ]
        {:ok, cs, events}
      false ->
        {:error, :invalid}
    end
  end
end

# Orchestrator: drives the building-block, executes events
defmodule MyApp.Accounts.Registration do
  alias MyApp.Accounts.Rules
  alias MyApp.{Repo, Mailer}

  def register(attrs) do
    with salt <- Bcrypt.gen_salt(),
         {:ok, cs, events} <- Rules.register(attrs, salt),
         {:ok, user} <- Repo.insert(cs) do
      Enum.each(events, &dispatch/1)
      {:ok, user}
    end
  end

  defp dispatch({:emit, name, payload}), do: :telemetry.execute([:accounts, name], %{}, payload)
  defp dispatch({:send, :welcome_email, %{email: email}}), do: Mailer.deliver_welcome(email)
end
```

**Why this matters:**
- The building-block (`Rules`) is property-test-friendly: assert that valid input produces the expected events list.
- The orchestrator's responsibility shrinks to "run the rules, persist, dispatch events" — itself testable with a captured-events mock.
- Events are first-class values: log them, audit them, replay them. This is the writer-monad pattern from FP, adapted naturally to Elixir.

When NOT to use this: when there's exactly one effect and it's transactional (e.g., insert+nothing-else). The events list is overhead for trivial cases.

#### 5.10.8 Capability passing — effects as arguments, not globals

A building-block that needs `now()`, `Application.get_env`, or a random salt fails axis 1 (input closure) of the building-block checklist. The fix: take the capability as an argument. The orchestrator resolves the capability at call time:

```elixir
# BAD — hidden capability (axis 1 fail)
def calculate_due_date(invoice), do: Date.add(invoice.issued_on, Application.get_env(:my_app, :net_days))

# GOOD — capability is an argument
@spec calculate_due_date(Invoice.t(), pos_integer()) :: Date.t()
def calculate_due_date(invoice, net_days), do: Date.add(invoice.issued_on, net_days)

# Orchestrator resolves it:
def issue(invoice) do
  net_days = Application.fetch_env!(:my_app, :net_days)
  Calculations.calculate_due_date(invoice, net_days)
end
```

For functions that need MULTIPLE capabilities (clock, random, config), bundle them into a `ctx` struct or keyword:

```elixir
defmodule MyApp.Clock.Ctx do
  defstruct [:now, :rand, :id_gen]

  def real do
    %__MODULE__{
      now:    &DateTime.utc_now/0,
      rand:   &:rand.uniform/0,
      id_gen: &Ecto.UUID.generate/0
    }
  end

  def deterministic(now, seed) do
    :rand.seed(:exsss, {seed, seed, seed})
    %__MODULE__{now: fn -> now end, rand: &:rand.uniform/0, id_gen: fn -> "test-#{seed}" end}
  end
end

# Building-block takes ctx:
def schedule(task, %Clock.Ctx{} = ctx), do: %{task | scheduled_at: ctx.now.()}

# Test passes deterministic ctx:
test "schedules at the supplied time" do
  ctx = Clock.Ctx.deterministic(~U[2026-05-06 12:00:00Z], 42)
  task = Schedule.schedule(%Task{}, ctx)
  assert task.scheduled_at == ~U[2026-05-06 12:00:00Z]
end
```

Capability passing makes the function a Reader monad in disguise: `ctx -> result` where `ctx` carries everything formerly hidden. Behaviour-based DI (config-pick the implementation per environment) is a degenerate form — useful when there are 2–3 implementations chosen at boot, not many.

#### 5.10.9 Lens / `update_in` — composing nested updates

For deep struct/map updates, manual `Map.update` chains stop reading well past two levels. Use `update_in` / `put_in` with an Access path:

```elixir
# BAD — manual nested update; the path is buried in the lambda
order =
  Map.update(order, :customer, %{}, fn customer ->
    Map.update(customer, :address, %{}, fn address ->
      Map.put(address, :city, "Oslo")
    end)
  end)

# GOOD — Access path expresses the depth declaratively
order = put_in(order.customer.address.city, "Oslo")

# With list traversal — Access.all/0
orders = update_in(orders, [Access.all(), :total], &Decimal.mult(&1, 1.25))

# With find-by-id
orders = update_in(orders, [Access.filter(&(&1.id == id)), :status], fn _ -> :paid end)
```

**When `update_in` doesn't fit:**
- The path depends on a value at one of the levels (e.g., "find this customer's most recent order"): use `Enum.find_index` + `update_in` with `Access.at/1`, or step out into a helper.
- The struct doesn't implement `Access` (most domain structs don't): either `defimpl Access` or fall back to manual updates. Phoenix params and Ecto changesets implement Access; your `defstruct` modules don't by default.

For very deep / dynamic paths (10+ levels, computed paths), reach for `Pathex` or `Focus` — but the threshold is high; `update_in` covers >95% of cases.

#### 5.10.10 Subject-position discipline — the rule that makes pipelines compose

Every public function in a building-block module follows: **the data (the thing being transformed) is the FIRST argument; configuration is LAST.**

```elixir
# BAD — pipeline-hostile
def discount(rate, price), do: # ...
# Caller: cart.items |> Enum.map(fn item -> discount(0.10, item.price) end)
# The pipeline can't put item.price in first-arg position.

# GOOD — pipeline-friendly
def discount(price, rate), do: # ...
# Caller: cart.items |> Enum.map(&discount(&1.price, 0.10))
# Or with a partial: cart.items |> Enum.map(&discount(&1.price, rate))
```

This is the foundation of pipeline composition. Stdlib observes it religiously: `Enum.map(coll, fn)`, `String.replace(s, pat, rep)`, `Map.put(map, k, v)`. Domain code should match.

**Special cases:**
- Functions that take an opts keyword take it last (`Module.fun(data, opts \\ [])`).
- Functions on a *pair* of things (merge, intersect, append) take both first then opts (`Map.merge(a, b, conflict_fn)`).
- Predicate functions on an enumerable take the enumerable first, the predicate second: `Enum.filter(coll, pred)`.

If you find a function in your code where data isn't first, it WILL break someone's pipeline later. Renaming the function arguments is a 5-minute refactor that pays off forever.

#### 5.10.11 Stream as lazy pipeline

A `Stream` chain has the same shape as an `Enum` chain — `coll |> Stream.map(...) |> Stream.filter(...)` — but every step is *lazy*: nothing runs until a terminal `Enum.*` materializes the result. This makes Stream a distinct composition primitive (the 5th mechanism in `elixir-planning/SKILL.md` §4.7.1). Use it when the source is bounded-but-large, unbounded, or I/O-sourced.

**When to choose Stream over Enum:**

| Signal | Choice |
|---|---|
| Source is `File.stream!/1`, `Repo.stream/1,2`, `IO.stream/2`, `Stream.resource/3` | **Stream** — eager `Enum` materializes the whole list into memory |
| Collection size is unknown (user data, log file, paginated API) | **Stream** — keeps memory bounded |
| Pipeline ends with `Enum.take/2` or `Enum.find/2` (early termination) | **Stream** — avoids transforming elements you'll never read |
| Collection size is known and small (≤ 1000 elements, fits in memory) | **Enum** — laziness adds overhead with no payoff |
| Pipeline materializes all elements at the end (`Enum.to_list`, `Enum.sum`) | **Either** — Stream wins on memory, Enum wins on raw speed for small collections |

**Canonical templates:**

```elixir
# Read-process-write pipeline — bounded memory regardless of file size:
"input.csv"
|> File.stream!()
|> Stream.drop(1)                              # skip header
|> Stream.map(&parse_csv_row/1)
|> Stream.filter(&valid?/1)
|> Stream.map(&transform/1)
|> Stream.into(File.stream!("output.csv"))     # back to file (collectable)
|> Stream.run()                                # materialize

# Database iteration without loading the whole table:
Repo.transaction(fn ->
  Repo.stream(query, max_rows: 500)
  |> Stream.chunk_every(100)
  |> Stream.each(&process_batch/1)
  |> Stream.run()
end, timeout: :infinity)

# Custom Stream from external source (Stream.resource/3):
Stream.resource(
  fn -> {:ok, conn} = Postgrex.start_link(opts); conn end,
  fn conn ->
    case Postgrex.query!(conn, "FETCH 100 FROM cur", []) do
      %{rows: []} -> {:halt, conn}
      %{rows: rows} -> {rows, conn}
    end
  end,
  fn conn -> Postgrex.close(conn) end
)

# Corecursion via Stream.unfold/2 — generate values from a seed:
Stream.unfold({0, 1}, fn {a, b} -> {a, {b, a + b}} end)
|> Enum.take(10)
# => [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]   (Fibonacci)
```

**Rules of thumb:**
- A Stream chain MUST end with exactly one terminal `Enum.*` (or `Stream.run/1`, `Stream.into/2`). The terminal call is what *materializes* the lazy chain.
- Side effects in `Stream.map/2`/`Stream.each/2` run AT MATERIALIZATION TIME — be explicit about when materialization happens.
- `Stream.resource/3` is the parser's best friend for streaming external sources (file handles, DB cursors, network sockets).
- `Stream.unfold/2` is corecursion: generate-from-seed. Pair with `Enum.take/2` to keep it bounded.

**BAD/GOOD:**

```elixir
# BAD — eager Enum on streamed source materializes everything
"huge.log"
|> File.stream!()
|> Enum.map(&parse/1)            # OOM on a 10GB log file
|> Enum.filter(&error?/1)

# GOOD — lazy chain keeps memory bounded
"huge.log"
|> File.stream!()
|> Stream.map(&parse/1)
|> Stream.filter(&error?/1)
|> Enum.take(100)                # only the first 100 errors are parsed
```

Cross-reference: `idioms-reference.md` §Stream has the full operation table (`Stream.map`, `filter`, `flat_map`, `chunk_every`, `transform`, `iterate`, `cycle`, `with_index`, `dedup`, `take_while`, `drop_while`, `interval`, etc.).

#### 5.10.12 Reduce as the universal fold

Most `Enum.*` operations are special cases of `Enum.reduce/3`. When you find yourself writing manual recursion to walk a list, the answer is almost always one of the reduce variants. The variants distinguish themselves by what kind of state the fold accumulates.

**Decision table for reduce variants:**

| Need | Variant | Returns |
|---|---|---|
| Accumulate to one value | `Enum.reduce/3` | The final accumulator |
| Halt early on a condition | `Enum.reduce_while/3` | The halt-or-final accumulator |
| Transform each element + accumulate state in parallel | `Enum.map_reduce/3` | `{transformed_list, final_acc}` |
| Each element produces 0..N outputs + thread state | `Enum.flat_map_reduce/3` | `{flat_list, final_acc}` |
| Emit the running accumulator after each step (running totals) | `Enum.scan/2,3` | List of partial accumulators |
| Pre-compute pairs while looping | `for x <- xs, reduce: acc do ... end` | The final acc |

**Templates:**

```elixir
# reduce — fold to one value
Enum.reduce(orders, Decimal.new(0), &Decimal.add(&2, &1.total))

# reduce_while — early termination with halt
Enum.reduce_while(items, [], fn item, acc ->
  case validate(item) do
    {:ok, v} -> {:cont, [v | acc]}
    {:error, _} = e -> {:halt, e}
  end
end)

# map_reduce — transform each element while threading state (e.g., assign IDs)
Enum.map_reduce(rows, 1, fn row, id -> {%{row | id: id}, id + 1} end)

# flat_map_reduce — each element produces multiple outputs (e.g., expand abbreviations)
Enum.flat_map_reduce(words, 0, fn word, count ->
  expansions = expand(word)
  {expansions, count + length(expansions)}
end)

# scan — running totals; emits each intermediate accumulator
Enum.scan([10, 5, 8, 3], &(&2 + &1))   # => [10, 15, 23, 26]

# for ... reduce: — multi-accumulator with pattern matching in clause
for x <- numbers, reduce: {[], []} do
  {odds, evens} ->
    case rem(x, 2) do
      0 -> {odds, [x | evens]}
      _ -> {[x | odds], evens}
    end
end
```

**BAD/GOOD — manual recursion that's really a reduce:**

```elixir
# BAD — reimplementing Enum.map via manual recursion
defp double_all([]), do: []
defp double_all([h | t]), do: [h * 2 | double_all(t)]

# GOOD — Enum.map with a capture
double_all(list), do: Enum.map(list, &(&1 * 2))

# BAD — reimplementing Enum.reduce with accumulator
defp sum_squares([], acc), do: acc
defp sum_squares([h | t], acc), do: sum_squares(t, acc + h * h)

# GOOD — Enum.reduce
sum_squares(list), do: Enum.reduce(list, 0, &(&2 + &1 * &1))

# BAD — manual recursion to filter+transform in one pass
defp parse_lines([], acc), do: Enum.reverse(acc)
defp parse_lines([line | rest], acc) do
  case parse(line) do
    {:ok, v} -> parse_lines(rest, [v | acc])
    :error -> parse_lines(rest, acc)
  end
end

# GOOD — for-comprehension with pattern in generator
def parse_lines(lines), do: for {:ok, v} <- Enum.map(lines, &parse/1), do: v
```

Manual recursion is right when:
- Multiple accumulators with complex state-machine logic — but consider `for ... reduce: tuple` first.
- Mutual recursion across two functions (rare).
- Tree / graph traversal where the structure isn't a list.
- Long-running process loops (`def loop(state), do: receive do ... end`).

For other cases, reach for the reduce family before writing recursion.

#### 5.10.13 Threading-builder pattern — when the subject accumulates state

Some Elixir APIs don't fit the pipeline shape (where each step *transforms* the subject's type). They follow the *threading-builder* shape: the subject keeps the same type, and each step ENRICHES it with more state. The canonical examples are `Ecto.Multi`, `Ecto.Query`, `Plug.Conn`, and Phoenix LiveView's `Socket`. This is the 6th composition mechanism in `elixir-planning/SKILL.md` §4.7.1.

**Recognition pattern — the API gives it away:**
- Constructor function (`Multi.new/0`, `Conn` from a plug, `socket` from `mount/3`).
- Many "builder" functions all returning the same type (`Multi.insert/3 :: Multi.t()`, `assign/3 :: Socket.t()`, `put_resp_header/3 :: Conn.t()`).
- One "terminal" function that consumes the built-up subject (`Repo.transaction/1`, `send_resp/3`, `render/2`).

**Canonical templates:**

```elixir
# Ecto.Multi — atomic multi-step transaction
Multi.new()
|> Multi.insert(:order, Order.changeset(%Order{}, attrs))
|> Multi.update(:user, User.changeset(user, %{order_count: user.order_count + 1}))
|> Multi.run(:notify, fn _, %{order: order} ->
  Notifications.send_order_confirmation(order)
end)
|> Repo.transaction()

# Plug.Conn — building up a response
conn
|> put_resp_header("x-request-id", request_id)
|> put_resp_cookie("session", session_id, http_only: true)
|> put_resp_content_type("application/json")
|> send_resp(200, body)

# LiveView Socket — building up assigns + commands
socket
|> assign(:user, user)
|> stream(:posts, posts)
|> push_event("scroll-to-bottom", %{})
```

**The anti-pattern is re-binding instead of piping:**

```elixir
# BAD — each `=` breaks the threading; reads imperatively
multi = Multi.new()
multi = Multi.insert(multi, :order, order_changeset)
multi = Multi.update(multi, :user, user_changeset)
multi = Multi.run(multi, :notify, fn _, %{order: o} -> notify(o) end)
Repo.transaction(multi)

# GOOD — threading-builder pipeline
Multi.new()
|> Multi.insert(:order, order_changeset)
|> Multi.update(:user, user_changeset)
|> Multi.run(:notify, fn _, %{order: o} -> notify(o) end)
|> Repo.transaction()
```

**Why threading-builder is distinct from a regular pipeline:**

| Aspect | Pipeline | Threading-builder |
|---|---|---|
| Subject type at each step | CHANGES (`String` → `[String]` → `Map`) | FIXED (`Multi.t()` everywhere) |
| Step semantics | TRANSFORMS the value | ENRICHES the value with more state |
| Terminal step | Yields the final value | Consumes the built-up subject (`Repo.transaction`, `send_resp`) |
| Failure handling | None inherent | Often via the consumer (`{:error, name, value, _}` from `Multi`) |

**Subject-type fixedness is the discriminator.** If you can re-arrange the steps without changing the type signature at each position, it's a threading-builder. If reordering breaks the type chain, it's a regular pipeline.

### 5.11 Bounded command/plugin registry — the safe replacement for runtime eval and dispatch

When external input picks the operation to run, the registry IS the security boundary. Unknown names return `{:error, :unknown_command}` instead of executing arbitrary code. This pattern replaces every `Code.eval_*` and every `apply` with a tainted module/function name (rule §1 #25/#26).

```elixir
defmodule MyApp.Commands do
  @moduledoc "Bounded dispatcher. The @commands map IS the security boundary."

  @commands %{
    "list_users"   => &MyApp.Accounts.list_users/0,
    "lock_user"    => &MyApp.Accounts.lock_user/1,
    "unlock_user"  => &MyApp.Accounts.unlock_user/1,
    "audit_export" => &MyApp.Audit.export/1
  }

  @spec dispatch(String.t(), [term()]) :: {:ok, term()} | {:error, :unknown_command}
  def dispatch(name, args) when is_binary(name) and is_list(args) do
    case Map.fetch(@commands, name) do
      {:ok, fun} -> {:ok, apply(fun, args)}
      :error     -> {:error, :unknown_command}
    end
  end
end
```

**Why this shape:** the `@commands` map is compile-time. A new command requires a code change + review + deploy — there is no runtime path that adds entries. `apply/2` on a function capture is fine here because the capture itself is a compile-time literal in the map. Compare:

| | Compile-time registry (this) | `Code.eval_string` | `apply(String.to_atom(name), ...)` |
|---|---|---|---|
| Auditable list of operations | yes — read `@commands` | no — anything | no — any module/function |
| Adds new behaviour at runtime | no (code-change only) | yes | yes |
| Survives a malicious input | yes — `:error` | RCE | RCE |

**Reference**: this is the shape Phoenix routers compile to (the `match` macros build a compile-time dispatch table) and how Oban resolves a `worker` argument to a module (workers are configured at compile time per queue, never named by the job payload).

### 5.12 Safe ETF deserialization — when ETF is unavoidable

**For external payloads, prefer JSON.** ETF should appear only on intra-cluster channels (signed cookies, `:gen_tcp` between known nodes, etc.) — and even there, route through `Plug.Crypto.non_executable_binary_to_term/2`, which forbids funs / pids / refs at decode time:

```elixir
# Cookie / signed-token style — Plug.Crypto.MessageVerifier already does this.
# Use the helper directly when wrapping your own intra-cluster bytes.
def decode_session(blob) when is_binary(blob) do
  Plug.Crypto.non_executable_binary_to_term(blob, [:safe])
rescue
  ArgumentError -> {:error, :decode_failed}
end
```

The `[:safe]` option additionally blocks the creation of new atoms — required when the payload may contain attacker-influenced atom-like strings.

**For external payloads, the canonical shape is JSON + a typed DTO:**

```elixir
defmodule MyApp.OrderRequest do
  @moduledoc "Public DTO for external order requests. Owned at the boundary."

  @enforce_keys [:user_id, :items]
  defstruct [:user_id, :items, opts: %{}]

  @type t :: %__MODULE__{user_id: pos_integer(), items: [map()], opts: map()}

  @spec new(binary()) :: {:ok, t()} | {:error, term()}
  def new(json) when is_binary(json) do
    with {:ok, %{"user_id" => uid, "items" => items} = raw} <- Jason.decode(json),
         {:ok, items}                                      <- normalize_items(items) do
      {:ok, %__MODULE__{user_id: uid, items: items, opts: Map.get(raw, "opts", %{})}}
    end
  end

  def new(_), do: {:error, :invalid_request}
end
```

The `Plug.Session.Cookie` store and `Phoenix.Token` are the production references for the ETF path; `Plug.Parsers.JSON` is the reference for the JSON-DTO path.

### 5.13 Logger.metadata propagation across async boundaries

`Logger.metadata` is per-process. A task spawned from a request handler does **NOT** inherit the request's `trace_id` / `request_id` / `tenant_id`. Any log line or telemetry event the task emits will be orphan — invisible when an operator searches by correlation ID.

The fix is one line on each side: capture, then restore.

```elixir
# Task.Supervisor — supervised, fire-and-forget
parent_metadata = Logger.metadata()

Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
  Logger.metadata(parent_metadata)
  Logger.info("processing order")          # carries parent's request_id
  do_work(order)
end)

# Task.async_stream — same shape
parent_metadata = Logger.metadata()

orders
|> Task.async_stream(
  fn order ->
    Logger.metadata(parent_metadata)
    process_order(order)
  end,
  ordered: false,
  max_concurrency: 8
)
|> Stream.run()
```

For Oban workers, set metadata at the start of `perform/1` from the job's args / metadata:

```elixir
defmodule MyApp.Workers.SyncOrders do
  use Oban.Worker
  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"order_id" => order_id} = args}) do
    # Restore the request's trace_id from the args the producer wrote in.
    Logger.metadata(
      order_id: order_id,
      trace_id: Map.get(args, "trace_id"),
      job_id: args["job_id"]
    )
    do_work(order_id)
  end
end
```

When the metadata you want to propagate is more than a couple of keys, use an explicit `TraceContext` struct passed as part of the message payload — the planning skill's §11.7 covers the design choice.

**Why metadata, not a struct, in most cases:** `Logger.metadata` is what every existing Logger backend, telemetry handler, and log aggregator already consumes. A struct is "more correct" but doesn't reach the formatter. Use the struct when the trace fields outlive the log scope (cross-PubSub, cross-Oban, cross-node).

**Verification grep:** `grep -rn "Logger.metadata\|Task\." lib/` should show that every `Task.async` / `Task.Supervisor.start_child` call is preceded (in the same function or an enclosing wrapper) by a `Logger.metadata()` capture, OR receives a context struct as an argument.

### 5.14 Secret-bearing struct — opaque inspect by default

Every struct that carries a secret-bearing field declares a safe `Inspect` rendering at definition time. **No struct ships without it.** Crash dumps include process state in SASL reports, observer, and remote shells; without an Inspect override every field is printed verbatim, including secrets that may end up in monitoring systems and incident channels.

Two patterns, pick one per struct:

```elixir
# Pattern A — @derive {Inspect, only: [...]}: list the SAFE fields
defmodule MyApp.Session do
  @derive {Inspect, only: [:id, :user_id, :inserted_at]}
  @derive {Jason.Encoder, only: [:id, :user_id, :inserted_at]}
  @enforce_keys [:id, :user_id, :token]
  defstruct [:id, :user_id, :token, :inserted_at]
end
# Inspect output: #MyApp.Session<id: ..., user_id: ..., inserted_at: ...>
# (the :token never appears)

# Pattern B — defimpl Inspect, for: __MODULE__: full custom rendering
# (the Plug.Conn pattern)
defmodule MyApp.CredentialHandle do
  @enforce_keys [:id, :provider]
  defstruct [:id, :provider, :expires_at, :materialized_secret]

  defimpl Inspect do
    def inspect(%{id: id, provider: p, expires_at: ea}, _opts) do
      "#Credential<provider=#{p} id=#{id} expires_at=#{inspect(ea)}>"
    end
  end
end
```

`@derive` MUST come BEFORE `defstruct`, or it does not apply.

**Reference**: `Plug.Conn` uses `defimpl Inspect, for: Plug.Conn` to replace `:secret_key_base` with `:...` before delegating to `Inspect.Any.inspect/2` (see `lib/plug/conn.ex` `defimpl Inspect` block). `Ecto.Changeset`, `Ecto.Query`, `Ecto.Schema.Metadata`, and `Ecto.Association` all use the same `defimpl Inspect` shape — sometimes for secrets, more often for clean rendering of a complex internal struct.

**Sensitive-field allowlist** (close enough for "must have Inspect override" detection):

`:token`, `:auth_token`, `:access_token`, `:refresh_token`, `:session_token`, `:reset_token`, `:bearer_token`, `:csrf_token`, `:id_token`, `:secret`, `:client_secret`, `:secret_key`, `:secret_key_base`, `:api_key`, `:api_secret`, `:private_key`, `:signing_key`, `:encryption_key`, `:password`, `:password_hash`, `:password_digest`, `:hashed_password`, `:encrypted_password`, `:otp_secret`, `:totp_secret`.

### 5.15 Sanitized errors at the response boundary

Drain stacktraces into `Logger` / `:telemetry.execute`; return a bounded error code; never put `__STACKTRACE__` in a response body.

```elixir
defmodule MyAppWeb.OrderController do
  use Phoenix.Controller
  require Logger

  def show(conn, params) do
    do_show(conn, params)
  rescue
    e ->
      # Drain to Logger — operators see it, callers don't
      Logger.error(Exception.format(:error, e, __STACKTRACE__),
        order_id: params["id"],
        path: conn.request_path
      )

      # Return a bounded code; never the stacktrace
      conn
      |> put_status(500)
      |> json(%{error: %{code: "internal_error", message: "An error occurred"}})
  end
end
```

**Reference**: `Phoenix.Endpoint.RenderErrors.__catch__/5` (`lib/phoenix/endpoint/render_errors.ex`) captures the stack into a local var and routes it to `instrument_render_and_send` for Logger / telemetry — Phoenix's render path **never** puts `__STACKTRACE__` in the rendered body. That's the production discipline this section codifies.

For domain errors, route through one mapping module:

```elixir
defmodule MyApp.Errors do
  @moduledoc "One mapping table from internal reason → external response."

  @mappings %{
    payment_failed:     {402, %{code: "payment_failed",     message: "Payment was declined"}},
    insufficient_stock: {409, %{code: "out_of_stock",       message: "Item is out of stock"}},
    not_found:          {404, %{code: "not_found",          message: "Not found"}}
  }

  @spec to_response(atom()) :: {pos_integer(), map()}
  def to_response(reason) do
    Map.get(
      @mappings,
      reason,
      {500, %{code: "internal_error", message: "An error occurred"}}
    )
  end
end
```

The boundary calls only `MyApp.Errors.to_response/1`, never reaches for `__STACKTRACE__` directly.

### 5.16 Versioned event/command struct

Two conventions for evolving persisted/exchanged event payloads. Pick ONE per project and document it in the planning gate (§0.1).

**Convention A — inline `:version` field on the struct.** Simple projects, no event-store library, easy to reason about:

```elixir
defmodule MyApp.Events.OrderPlaced do
  @version 1
  @derive {Jason.Encoder, only: [:version, :order_id, :placed_at]}
  @enforce_keys [:order_id, :placed_at]
  defstruct version: @version, order_id: nil, placed_at: nil

  @type t :: %__MODULE__{version: pos_integer(), order_id: binary(), placed_at: DateTime.t()}
end
```

When the schema evolves, bump `@version` and add the new field with a default; an explicit upcaster module reads the old version and translates:

```elixir
defmodule MyApp.Events.OrderPlacedUpcaster do
  def upcast(%{"version" => 1, "order_id" => oid, "placed_at" => pa}) do
    %{"version" => 2, "order_id" => oid, "placed_at" => pa, "placed_by" => nil}
  end
  def upcast(%{"version" => 2} = event), do: event
end
```

**Convention B — `defimpl Commanded.Event.Upcaster, for: MyEvent`** (the Commanded idiom). **One event module per type**; the upcaster transforms older persisted shapes into the current shape *in place*. Note: Commanded does NOT recommend `V1.OrderPlaced` / `V2.OrderPlaced` separate modules. The struct evolves; the upcaster fills in defaults for fields the older version didn't have.

Documented Commanded example (rename `:name` → `:first_name`):

```elixir
defmodule AnEvent do
  defstruct [:first_name]
end

defimpl Commanded.Event.Upcaster, for: AnEvent do
  def upcast(%AnEvent{} = event, _metadata) do
    %AnEvent{name: name} = event       # old persisted shape had :name
    %AnEvent{event | first_name: name} # current shape has :first_name
  end
end
```

> "Upcaster changes any historical event to the latest version, consumers (aggregates, event handlers, and process managers) only need to support the latest version."
> — `Commanded.Event.Upcaster` moduledoc

**Decision: A vs B**

| Choice | Use when |
|---|---|
| Inline `:version` field (Convention A) | No event-store library; events flow through Oban/PubSub; project owns the storage shape |
| `defimpl Commanded.Event.Upcaster` (Convention B) | Project uses Commanded / EventStore; one event module per type; upcaster handles back-compat |

Mixing the two is acceptable but the project must declare which is the default for new events.
