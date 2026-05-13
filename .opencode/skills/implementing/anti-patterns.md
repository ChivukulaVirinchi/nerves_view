---
name: implementing/anti-patterns
description: >
  Quick-reference checklist of ~20 anti-patterns Claude most commonly produces in Elixir.
  Each entry is a compact BAD/GOOD pair. For full explanations and the complete catalog
  (80+ patterns across code, OTP, Ecto, architecture, testing, security, config, BEAM DBs)
  -> load reviewing/anti-patterns-catalog.md
---

# Anti-Patterns Quick Reference (Implementing)

> **Canonical reference:** [reviewing/anti-patterns-catalog.md](../reviewing/anti-patterns-catalog.md) has full explanations, severity guidance, and cross-references.
> This file is a curated subset for fast lookup while writing code.

---

## 1. Control Flow

### 1.1 if/else chain for structural dispatch

```elixir
# BAD
if is_map(msg) and Map.has_key?(msg, :type) do
  if msg.type == :error, do: handle_error(msg), else: handle_ok(msg)
end

# GOOD — multi-clause with pattern in head
def handle(%{type: :error} = msg), do: handle_error(msg)
def handle(%{type: _} = msg), do: handle_ok(msg)
```

### 1.2 Nested case instead of with

```elixir
# BAD — O(n^2) visual complexity
case validate(p) do
  {:ok, v} -> case create(v) do {:ok, r} -> {:ok, r}; e -> e end
  e -> e
end

# GOOD
with {:ok, v} <- validate(p), {:ok, r} <- create(v), do: {:ok, r}
```

### 1.3 cond without true catch-all

```elixir
# BAD — CondClauseError if no branch matches
cond do
  x > 10 -> :large
  x > 5 -> :medium
end

# GOOD
cond do
  x > 10 -> :large
  x > 5 -> :medium
  true -> :small
end
```

### 1.4 Nil checks instead of pattern match

```elixir
# BAD
if user != nil do
  if user.name != nil, do: "Hello, #{user.name}", else: "Hello, anon"
else
  "Hello, guest"
end

# GOOD
def greet(%{name: name}) when is_binary(name), do: "Hello, #{name}"
def greet(%{}), do: "Hello, anon"
def greet(nil), do: "Hello, guest"
```

## 2. Pipelines

### 2.1 Single-step pipe

```elixir
# BAD
name |> String.upcase()
# GOOD
String.upcase(name)
```

### 2.2 Pipe into anonymous function

```elixir
# BAD
data |> (fn x -> x * 2 end).()
# GOOD
data |> then(&(&1 * 2))
```

## 3. Enum / Iteration

### 3.1 Enum.each for accumulation

```elixir
# BAD — rebinding doesn't escape the closure
result = []
Enum.each(items, fn item -> result = [process(item) | result] end)
result  # still []

# GOOD
result = Enum.map(items, &process/1)
```

### 3.2 length(list) > 0 for emptiness check

```elixir
# BAD — O(n)
if length(list) > 0, do: process(list)

# GOOD — O(1)
case list do
  [_ | _] -> process(list)
  [] -> :empty
end
```

### 3.3 Anonymous fn wrapping a single call

```elixir
# BAD
Enum.map(users, fn u -> User.name(u) end)
# GOOD
Enum.map(users, &User.name/1)
```

### 3.4 Two passes for partition

```elixir
# BAD
good = Enum.filter(xs, &valid?/1)
bad = Enum.reject(xs, &valid?/1)

# GOOD — one pass
{good, bad} = Enum.split_with(xs, &valid?/1)
```

## 4. Error Handling

### 4.1 try/rescue for expected failures

```elixir
# BAD
try do
  String.to_integer(s)
rescue
  ArgumentError -> {:error, :invalid}
end

# GOOD
case Integer.parse(s) do
  {n, ""} -> {:ok, n}
  _ -> {:error, :invalid}
end
```

### 4.2 rescue instead of catch :exit for GenServer.call

```elixir
# BAD — GenServer.call raises :exit, not an exception
try do
  GenServer.call(pid, :status)
rescue
  _ -> {:error, :down}
end

# GOOD
try do
  GenServer.call(pid, :status)
catch
  :exit, _ -> {:error, :down}
end
```

### 4.3 Broad rescue swallowing everything

```elixir
# BAD
def risky do
  do_work()
rescue
  _ -> nil
end

# GOOD — rescue specific exceptions
def risky do
  do_work()
rescue
  File.Error -> {:error, :io}
end
```

## 5. Data Manipulation

### 5.1 Map.put on a struct

```elixir
# BAD — silently accepts typo'd keys
Map.put(user, :nmae, "Jane")

# GOOD — raises on unknown keys
%{user | name: "Jane"}
```

### 5.2 String concatenation in a loop

```elixir
# BAD — O(n^2)
Enum.reduce(rows, "", fn row, acc -> acc <> format(row) <> "\n" end)

# GOOD — IO list
rows |> Enum.map(fn row -> [format(row), "\n"] end) |> IO.iodata_to_binary()
```

## 6. Pattern Matching

### 6.1 Forgot the pin operator

```elixir
# BAD — variable rebinds, matches anything
expected = :ok
case result do
  expected -> :matched    # ALWAYS matches
end

# GOOD
case result do
  ^expected -> :matched
  _ -> :no_match
end
```

### 6.2 Atom keys vs string keys mismatch

```elixir
# BAD
params = %{"name" => "Jane"}
%{name: n} = params   # MatchError!

# GOOD
%{"name" => n} = params          # external data -> string keys
%{name: n} = internal_map        # internal data -> atom keys
```

## 7. Atoms and Safety

### 7.1 String.to_atom on untrusted input

```elixir
# BAD — atom table exhaustion
String.to_atom(user_input)
Jason.decode!(json, keys: :atoms)

# GOOD
String.to_existing_atom(user_input)
Jason.decode!(json)   # default: string keys
```

## 8. Process / OTP

### 8.1 Unsupervised spawn

```elixir
# BAD
spawn(fn -> loop() end)
# GOOD
Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> loop() end)
```

### 8.2 Business logic in GenServer callback

```elixir
# BAD — domain logic coupled to process mechanics
def handle_call({:apply_discount, code}, _from, state) do
  discount = case code do "SAVE10" -> Decimal.new("0.10"); _ -> Decimal.new("0") end
  {:reply, {:ok, Decimal.mult(state.total, Decimal.sub(1, discount))}, state}
end

# GOOD — pure function for domain, GenServer for process mechanics
defmodule Pricing do
  def apply_discount(total, code), do: Decimal.mult(total, Decimal.sub(1, rate(code)))
  defp rate("SAVE10"), do: Decimal.new("0.10")
  defp rate(_), do: Decimal.new("0")
end
```

## 9. Testing

### 9.1 Process.sleep for async behavior

```elixir
# BAD — flaky
send(pid, :go)
Process.sleep(100)
assert :done == GenServer.call(pid, :state)

# GOOD
send(pid, :go)
assert_receive {:done, _}, 500
```

### 9.2 stub when expect is needed

```elixir
# BAD — test passes even if the code never calls send_welcome
stub(MyApp.Mailer.Mock, :send_welcome, fn _ -> :ok end)

# GOOD — verifies the call happened
expect(MyApp.Mailer.Mock, :send_welcome, fn _ -> :ok end)
```

## 10. Security

### 10.1 Unsafe deserialization

```elixir
# BAD — RCE vector
:erlang.binary_to_term(blob)

# GOOD
Plug.Crypto.non_executable_binary_to_term(blob, [:safe])
```

### 10.2 Secret leak via Inspect

```elixir
# BAD — token leaks in crash dumps
defstruct [:id, :user_id, :token, :expires_at]

# GOOD
@derive {Inspect, only: [:id, :user_id, :expires_at]}
defstruct [:id, :user_id, :token, :expires_at]
```
