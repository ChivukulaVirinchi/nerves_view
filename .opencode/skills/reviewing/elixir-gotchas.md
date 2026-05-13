---
name: elixir-gotchas
description: >
  LLM-specific Elixir mistakes -- patterns that humans rarely produce but LLMs
  consistently get wrong. Covers list bracket access, variable rebinding, struct
  access, naming conventions, guard syntax, pipe argument position, and Enum.each
  accumulation. For the full anti-patterns catalog -> load reviewing/anti-patterns-catalog.md.
  For HEEx -> load heex. For Ecto -> load ecto. For LiveView -> load liveview.
---

# Elixir Gotchas -- LLM-Specific Mistakes

Patterns that LLMs consistently generate but experienced Elixir developers almost never write. Each is a compilation error or silent bug that wastes a review cycle.

> **Full anti-patterns catalog:** [reviewing/anti-patterns-catalog.md](anti-patterns-catalog.md) covers 80+ patterns across all categories.
> This file covers only the mistakes unique to LLM code generation.

---

## 1. Decision Table

| Intent | Use | Avoid | Severity |
|---|---|---|---|
| Access list element by index | `Enum.at(list, n)` | `list[n]` | BLOCK |
| Get first element | `hd(list)` or `List.first(list)` | `list[0]` | BLOCK |
| Access struct field | `my_struct.field` | `my_struct[:field]` | BLOCK |
| Access changeset field | `Ecto.Changeset.get_field(cs, :f)` | `cs[:f]` or `cs.f` | BLOCK |
| Conditionally assign | `socket = if ... do assign(...) else socket end` | `if ... do socket = assign(...) end` | BLOCK |
| Name a boolean function | `def active?(user)` | `def is_active(user)` | WARN |
| Write a guard | `when not is_nil(x) and x > 0` | `when x != nil && x > 0` | BLOCK |
| Accumulate from a list | `Enum.map/reduce` | `Enum.each` + rebinding | BLOCK |
| Pipe a value | `data \|> step1() \|> step2()` | `data \|> Map.put(target, :key)` | WARN |

## 2. Patterns

### 2.1 List Bracket Access

**Severity:** BLOCK

```elixir
# BAD -- lists do not support bracket access
first = mylist[0]

# GOOD
first = Enum.at(mylist, 0)
first = hd(mylist)           # raises on empty
[first | _] = mylist         # pattern match
```

### 2.2 Variable Rebinding in Blocks

**Severity:** BLOCK

```elixir
# BAD -- rebinding inside block does not affect outer scope
if connected?(socket) do
  socket = assign(socket, :val, val)
end
# socket is UNCHANGED here

# GOOD -- bind the block result
socket =
  if connected?(socket) do
    assign(socket, :val, val)
  else
    socket
  end
```

### 2.3 Struct Bracket Access

**Severity:** BLOCK

```elixir
# BAD -- structs do not implement Access
my_struct[:field]

# GOOD
my_struct.field
Ecto.Changeset.get_field(changeset, :field)
```

### 2.4 Predicate Naming

**Severity:** WARN

```elixir
# BAD -- is_ prefix without being a guard
def is_valid(x), do: ...

# GOOD -- ? suffix for boolean functions
def valid?(x), do: ...

# is_ is ONLY for guard-safe macros
defguard is_admin(user) when user.role == :admin
```

### 2.5 Guards with Kernel Operators

**Severity:** BLOCK

```elixir
# BAD -- &&/||/! are Kernel macros, not allowed in guards
defguard is_valid(x) when x != nil && x > 0

# GOOD -- guard-safe operators
defguard is_valid(x) when not is_nil(x) and x > 0
```

### 2.6 Pipe Into Wrong Argument Position

**Severity:** WARN

```elixir
# BAD -- pipe feeds first argument, not second
data |> Map.put(my_map, :key)
# calls Map.put(data, my_map, :key) -- wrong!

# GOOD
my_map |> Map.put(:key, data)
```

### 2.7 Enum.each for Accumulation

**Severity:** BLOCK

```elixir
# BAD -- rebinding inside Enum.each doesn't escape the closure
result = []
Enum.each(items, fn item ->
  result = [transform(item) | result]
end)
IO.inspect(result)   # still []

# GOOD -- Enum.map or Enum.reduce
result = Enum.map(items, &transform/1)

# For conditional accumulation:
result = Enum.reduce(items, [], fn item, acc ->
  if valid?(item), do: [transform(item) | acc], else: acc
end)
```

LLMs produce this because imperative languages (Python, JS) allow mutation inside loops. Elixir closures capture bindings by value; rebinding inside a closure creates a new local binding that is discarded when the closure returns.

### 2.8 Missing @impl on Callbacks

**Severity:** WARN

```elixir
# BAD -- typo creates a dead function, no warning
def handle_events("save", params, socket), do: {:noreply, socket}

# GOOD -- compiler warns if not a valid callback
@impl true
def handle_event("save", params, socket), do: {:noreply, socket}
```

### 2.9 OTP Primitives Without Names

**Severity:** BLOCK

```elixir
# BAD -- crashes with "already started" on restart
children = [{DynamicSupervisor, []}]

# GOOD
children = [{DynamicSupervisor, name: MyApp.TaskSupervisor}]
```

### 2.10 Single-clause with Instead of case

**Severity:** WARN

```elixir
# BAD -- with for one clause is over-engineering
with {:ok, user} <- fetch_user(id) do
  {:ok, user.name}
end

# GOOD -- case is simpler for a single match
case fetch_user(id) do
  {:ok, user} -> {:ok, user.name}
  {:error, _} = err -> err
end
```

## 3. Checklist

- [ ] No `list[index]` bracket access on lists
- [ ] No `struct[:field]` bracket access on structs
- [ ] All `if`/`case` results captured (no rebinding inside blocks)
- [ ] No `Enum.each` used for accumulation -- use `Enum.map`/`Enum.reduce`
- [ ] Boolean functions use `?` suffix (not `is_` prefix)
- [ ] All OTP children have `:name` option
- [ ] All callbacks have `@impl true`
- [ ] Guards use `and`/`or`/`not` (not `&&`/`||`/`!`)
- [ ] Pipes feed the first argument position

## 4. Routing

| If you need... | Load instead |
|---|---|
| Full anti-patterns catalog (80+ entries) | `reviewing/anti-patterns-catalog.md` |
| HEEx template syntax mistakes | `heex` |
| Ecto/changeset mistakes | `ecto` |
| LiveView lifecycle mistakes | `liveview` |
| Security-related gotchas | `security` |
