---
name: heex
description: >
  HEEx template syntax for Phoenix LiveView. ALWAYS use when writing HEEx templates,
  component markup, or conditional rendering. For LiveView lifecycle → load liveview.
  For JS hooks → load hooks. For form templates → load phoenix-forms.
---

# HEEx Template Syntax

HEEx (HTML+EEx) is Phoenix's template engine. It enforces compile-time validation of
attributes, interpolation, and control flow. LLMs consistently generate invalid syntax
because they mix up EEx (`<%= %>`), curly-brace (`{}`), and string interpolation rules.

## 1. Rules

1. **Attribute values always use `{expr}`** -- never `<%= %>` inside tags.
2. **Body text uses `{expr}`** -- `{@name}`, `{some_var}`.
3. **Control flow (`if`/`for`/`case`/`cond`) uses `<%= %>`** for opening, `<% end %>` for closing.
4. **There is no `else if`** in Elixir. Use `cond` for multi-branch conditionals.
5. **Dynamic class lists must use `{[...]}`** -- square brackets inside curlies.
6. **`phx-no-curly-interpolation`** is required on `<code>`, `<pre>`, or `<script>` tags that contain literal curly braces (e.g., JavaScript objects).
7. **Comments use `<%!-- ... --%>`** -- not HTML `<!-- -->` (which leaks to the client).
8. **Component slots use `<:slot_name>` syntax** -- not `<slot>` or arbitrary nesting.
9. **Boolean attributes** use `{@flag}` -- e.g., `disabled={@disabled}`. When the value is `false`/`nil`, the attribute is omitted from output.

## 2. Decision Table

| Intent / Situation | Use | Avoid | Why |
|---|---|---|---|
| Set an attribute value | `id={@id}` | `id="<%= @id %>"` | `<%= %>` inside tags is invalid HEEx and will not compile |
| Display a value in body | `{@name}` | `<%= @name %>` | `<%= %>` for body values works but `{}` is idiomatic HEEx (Phoenix 1.7+) |
| Conditional rendering | `<%= if @show do %> ... <% end %>` | `{if @show do} ... {end}` | Control flow must use EEx tags, not curly interpolation |
| Multi-branch conditional | `<%= cond do %> <% x -> %> ... <% end %>` | `<%= if x do %> <% else if y do %>` | `else if` does not exist in Elixir; use `cond` |
| Dynamic CSS classes | `class={["base", @flag && "extra"]}` | `class={"base", @flag && "extra"}` | Must be a single list expression; bare tuple/multiple args fail |
| Static + conditional class | `class={["px-2 text-sm", @active && "bg-blue-500"]}` | `class="px-2 text-sm #{if @active, do: "bg-blue-500"}"` | String interpolation bypasses HEEx class merging and is fragile |
| Iteration over collection | `<%= for item <- @items do %> ... <% end %>` | `{Enum.map(@items, ...)}` | `for` comprehension with EEx tags is the standard pattern |
| JS object in template | `<code phx-no-curly-interpolation>{key: "val"}</code>` | `<code>{key: "val"}</code>` | Without the attr, HEEx tries to parse `{key: "val"}` as Elixir |
| Boolean attribute | `disabled={@disabled}` | `disabled="<%= @disabled %>"` | Curlies handle boolean omission; string attrs always render |
| Component with slot | `<.card><:header>Title</:header></.card>` | `<.card header="Title" />` | Named slots use `<:name>` syntax for rich content |

## 3. Patterns

### 3.1 Attribute Interpolation

**Severity:** BLOCK

```elixir
# BAD -- EEx tags inside HTML attributes; will not compile
<div id="<%= @id %>" class="<%= @class %>">

# GOOD -- curly-brace interpolation for all attributes
<div id={@id} class={@class}>
```

**Why:** HEEx validates attributes at compile time. `<%= %>` inside a tag is a syntax error. Curly braces are the only valid interpolation syntax for attribute values.

### 3.2 Missing Brackets in Class Lists

**Severity:** BLOCK

```elixir
# BAD -- tuple, not a list; will crash or produce wrong output
<div class={"px-2", @flag && "py-5"}>

# GOOD -- list with conditional entries
<div class={["px-2", @flag && "py-5"]}>
```

**Why:** Class merging requires a list. Without brackets, you get a tuple which HEEx cannot process as a class list. `false`/`nil` entries in the list are automatically filtered out.

### 3.3 Non-Existent `else if`

**Severity:** BLOCK

```elixir
# BAD -- else if does not exist in Elixir
<%= if @role == :admin do %>
  Admin panel
<% else if @role == :mod do %>
  Mod panel
<% end %>

# GOOD -- use cond for multi-branch
<%= cond do %>
  <% @role == :admin -> %>
    Admin panel
  <% @role == :mod -> %>
    Mod panel
  <% true -> %>
    Default panel
<% end %>
```

**Why:** Elixir has `if/else` and `cond`, but no `else if` construct. The BAD example compiles as `else` followed by a nested `if` that is never properly closed, causing confusing errors.

### 3.4 Curly Interpolation for Control Flow

**Severity:** BLOCK

```elixir
# BAD -- curly braces cannot contain control flow
{if @show do}
  {@content}
{end}

# GOOD -- control flow uses EEx tags
<%= if @show do %>
  {@content}
<% end %>
```

**Why:** `{}` in HEEx evaluates a single expression and inserts the result. Block constructs (`if`, `for`, `case`, `cond`) require `<%= %>` / `<% %>` tags.

### 3.5 String Interpolation in Classes

**Severity:** WARN

```elixir
# BAD -- string interpolation bypasses class merging
<div class="px-2 #{if @active, do: "bg-blue-500"}">

# GOOD -- list-based conditional classes
<div class={["px-2", @active && "bg-blue-500"]}>
```

**Why:** String interpolation produces `"px-2 "` (with trailing space) when `@active` is false, and does not integrate with Tailwind CSS class merging. The list form cleanly drops `false`/`nil` entries.

### 3.6 HTML Comments Leak to Client

**Severity:** SUGGEST

```elixir
# BAD -- visible in page source, may expose implementation details
<!-- TODO: fix this hack for admin users -->

# GOOD -- HEEx comment, stripped at compile time
<%!-- TODO: fix this hack for admin users --%>
```

**Why:** HTML comments are sent to the browser. HEEx comments are removed during compilation and never reach the client.

### 3.7 Inline Ternary Abuse

**Severity:** WARN

```elixir
# BAD -- hard to read, especially with nested ternaries
<div class={if(@a, do: if(@b, do: "x", else: "y"), else: "z")}>

# GOOD -- list with multiple conditions
<div class={[
  @a && @b && "x",
  @a && !@b && "y",
  !@a && "z"
]}>

# GOOD -- for complex logic, compute in the LiveView and assign
# In mount/handle_event:
assign(socket, :panel_class, compute_panel_class(a, b))
# In template:
<div class={@panel_class}>
```

**Why:** Nested `if` expressions in attributes are hard to read and error-prone. For simple cases, list entries with `&&` are clearer. For complex cases, move logic to the LiveView.

### 3.8 Component Slot Misuse

**Severity:** WARN

```elixir
# BAD -- passing rich content as a string attribute
<.card header="<strong>Title</strong>" />

# BAD -- using raw HTML slot element
<.card>
  <slot name="header">Title</slot>
</.card>

# GOOD -- named slot with HEEx syntax
<.card>
  <:header>
    <strong>Title</strong>
  </:header>
  Card body content here.
</.card>

# Component definition:
slot :header, required: true
slot :inner_block, required: true

def card(assigns) do
  ~H"""
  <div class="card">
    <div class="card-header">{render_slot(@header)}</div>
    <div class="card-body">{render_slot(@inner_block)}</div>
  </div>
  """
end
```

**Why:** Named slots (`<:name>`) are HEEx's mechanism for passing rich content to components. String attributes cannot contain HTML markup. The `<slot>` element is a Web Components concept that does not exist in HEEx.

### 3.9 For Comprehension Without Key

**Severity:** WARN

```elixir
# BAD -- no key for diffing; LiveView cannot efficiently track items
<%= for item <- @items do %>
  <div>{item.name}</div>
<% end %>

# GOOD -- :if and collections in components should use id for diffing
<div :for={item <- @items} id={"item-#{item.id}"}>
  {item.name}
</div>

# GOOD -- with streams (preferred for large collections)
<div id="items" phx-update="stream">
  <div :for={{dom_id, item} <- @streams.items} id={dom_id}>
    {item.name}
  </div>
</div>
```

**Why:** Without unique IDs, LiveView cannot efficiently diff the collection. It must compare every element on every update. Adding `id` enables targeted DOM patching. For large collections, use streams instead of `for`.

## 4. Checklist

- [ ] No `<%= %>` inside HTML tag attributes (use `{expr}` instead)
- [ ] All dynamic class lists use `{[...]}` with square brackets
- [ ] No `else if` anywhere -- use `cond` for multi-branch
- [ ] `phx-no-curly-interpolation` on tags containing literal `{}`
- [ ] Comments use `<%!-- --%>`, not `<!-- -->`
- [ ] Component slots use `<:name>` syntax
- [ ] No string interpolation for conditional classes

## 5. Routing

| If you need... | Load instead |
|---|---|
| LiveView mount/lifecycle | `liveview` |
| Form handling, `phx-change`/`phx-submit` | `phoenix-forms` |
| JS hooks, `phx-hook` | `hooks` |
| File uploads in templates | `phoenix-uploads` |
| Component design (function vs LiveComponent) | `liveview-components` |
| Conditional class merging with Tailwind | This skill covers the syntax; for design → `frontend-design` |

## Quick Reference

| Context | Syntax | Example |
|---------|--------|---------|
| Attribute values | `{expr}` | `id={@id}` |
| Body text | `{expr}` | `{@name}` |
| Control flow | `<%= %>`/`<% %>` | `<%= if @x do %>` |
| Multi-branch | `cond` | No `else if` |
| Dynamic classes | `{[...]}` | `class={["a", @b && "c"]}` |
| Boolean attrs | `{expr}` | `disabled={@disabled}` |
| JS in templates | `phx-no-curly-interpolation` | On `<code>`, `<script>` |
| Comments | `<%!-- --%>` | Server-side only |
| Named slots | `<:name>` | `<:header>Title</:header>` |
