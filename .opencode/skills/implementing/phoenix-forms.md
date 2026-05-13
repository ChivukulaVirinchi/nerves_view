---
name: elixir-phoenix-forms
description: >
  Phoenix LiveView forms covering create/edit patterns, validation display,
  nested forms, component forms, debounce, recovery, phx-trigger-action, and
  input edge cases. ALWAYS use when implementing LiveView forms, changesets
  in views, phx-change/phx-submit events, or editing existing records. For
  Ecto changeset internals -> load ecto. For file uploads -> load
  phoenix-uploads. For HEEx template syntax -> load heex.
---

# Phoenix LiveView Forms

LiveView forms are the most error-prone surface in Phoenix development. LLMs
consistently miss the `id` attribute on `<.form>`, use `@changeset` instead of
`@form`, forget `action: :validate` in validate handlers, use `%Item{}` instead
of the existing record in edit forms, and skip `on_replace: :delete` for nested
associations. This skill is a complete reference for correct form implementation.

## 1. Rules

1. **Always provide a stable `id` on `<.form>`.** LiveView uses it for DOM patching, form recovery on reconnect, and phx-feedback tracking.
2. **Always include both `phx-change="validate"` and `phx-submit="save"` on forms.** Missing `phx-change` means no live validation; missing `phx-submit` means no submission.
3. **Use `@form[:field_name]`, not `@form.field_name`.** The bracket syntax returns a `Phoenix.HTML.FormField` struct; dot access does not.
4. **Convert changesets with `to_form/2` before assigning.** Never store raw changesets in socket assigns. Always `assign(socket, form: to_form(changeset))`.
5. **Pass `action: :validate` to `to_form/2` in validate handlers.** Without an action, all errors are suppressed regardless of validation state.
6. **Do NOT pass `action: :validate` on mount.** The initial form should show no errors. Only set the action after user interaction.
7. **Use the existing record (not `%Item{}`) in edit form validate handlers.** Using an empty struct loses existing data and produces incorrect changesets.
8. **Add `on_replace: :delete` to all `has_many`/`embeds_many` used in forms.** Without it, Ecto raises when nested items are removed.
9. **Use `type="button"` + `JS.dispatch("change")` for nested form add/remove buttons.** Without `type="button"`, the button submits the form. Without `JS.dispatch("change")`, the `phx-change` handler doesn't fire.
10. **Use `phx-trigger-action` for flows that need HTTP (login, OAuth, cookies).** LiveView WebSocket cannot set cookies or issue HTTP redirects.

## 2. Decision Tables

### 2.1 Form Architecture Selection

| Situation | Use | Why |
|-----------|-----|-----|
| Single form on a page, parent owns state | Function component (stateless) | Simplest; parent handles all events |
| Multiple independent forms on one page | LiveComponent per form | Each component owns its own form state and events |
| Form reused across pages with different parent logic | LiveComponent | Encapsulates form behavior, parent gets notified via `send(self(), ...)` |
| Auth flow needing cookies/redirects | `phx-trigger-action` + HTTP `action` | WebSocket cannot set cookies |
| Multi-step wizard | Single LiveView with step assigns | Maintains all state in one process |

### 2.2 Error Display Behavior

| Changeset Action | Errors Shown? | When Set |
|-----------------|---------------|----------|
| `nil` | No | Initial mount (default) |
| `:ignore` | No | Explicitly suppressed |
| `:validate` | Yes, for used inputs | `to_form(changeset, action: :validate)` in validate handler |
| `:insert` / `:update` | Yes, all fields | Automatically set by failed `Repo.insert/update` |

### 2.3 Input Debounce Strategy

| Input Type | Strategy | Value | Why |
|-----------|----------|-------|-----|
| Email, password | `phx-debounce` | `"blur"` | Validate on field leave, no mid-typing noise |
| Search, filter text | `phx-debounce` | `"300"` | Wait for typing pause before firing event |
| Sliders, ranges | `phx-throttle` | `"300"` | Continuous but rate-limited |
| Toggles, checkboxes, radio | `phx-debounce` | `"0"` | Instant feedback on discrete choice |
| General text input | `phx-debounce` | `"300"` | Default balanced choice |
| Number (type="number") | N/A | N/A | Browser does not fire change for invalid input; use `type="text"` + `inputmode="numeric"` if server validation needed |

### 2.4 Form Recovery on Reconnect

| Form Configuration | Recovery Behavior | Use Case |
|-------------------|-------------------|----------|
| `phx-change` + stable `id` | Auto-recovers on reconnect | Standard forms |
| `phx-change` + `phx-auto-recover="recover_form"` | Calls custom recovery event | Multi-step wizards |
| `phx-change` + `phx-auto-recover="ignore"` | No recovery | Sensitive forms (payment) |
| Missing `phx-change` or `id` | No recovery | Broken; fix the form |

## 3. Patterns (BAD -> GOOD)

### 3.1 Missing Form ID

**Severity:** BLOCK

```heex
<%!-- BAD -- no id, breaks DOM patching and form recovery --%>
<.form for={@form} phx-change="validate" phx-submit="save">

<%!-- GOOD -- stable id present --%>
<.form for={@form} id="item-form" phx-change="validate" phx-submit="save">
```

**Why:** LiveView uses the `id` to correlate the client-side form DOM with server-side state. Without it, DOM patching fails, form recovery on reconnect breaks, and `phx-feedback-for` error display doesn't work.

### 3.2 Raw Changeset in Assigns

**Severity:** BLOCK

```elixir
# BAD -- storing changeset directly
assign(socket, changeset: changeset)
# Template: <.form for={@changeset}>

# GOOD -- convert to form
assign(socket, form: to_form(changeset))
# Template: <.form for={@form}>
```

**Why:** `to_form/2` wraps the changeset in a `Phoenix.HTML.Form` struct that provides change tracking, field metadata, and error formatting. Raw changesets lack these capabilities.

### 3.3 Missing action: :validate in Validate Handler

**Severity:** BLOCK

```elixir
# BAD -- errors never display during live validation
def handle_event("validate", %{"item" => params}, socket) do
  form =
    %Item{}
    |> Context.change_item(params)
    |> to_form()  # no action!

  {:noreply, assign(socket, form: form)}
end

# GOOD -- action triggers error display
def handle_event("validate", %{"item" => params}, socket) do
  form =
    %Item{}
    |> Context.change_item(params)
    |> to_form(action: :validate)

  {:noreply, assign(socket, form: form)}
end
```

**Why:** The changeset action is a global gate for error display. With `nil` action, all errors are suppressed. `action: :validate` enables per-field error display for fields the user has interacted with (`used_input?/1`).

### 3.4 action: :validate on Mount

**Severity:** WARN

```elixir
# BAD -- shows errors before user types anything
def mount(_params, _session, socket) do
  form = Context.change_item(%Item{}) |> to_form(action: :validate)
  {:ok, assign(socket, form: form)}
end

# GOOD -- clean form on mount, errors only after interaction
def mount(_params, _session, socket) do
  form = Context.change_item(%Item{}) |> to_form()
  {:ok, assign(socket, form: form)}
end
```

**Why:** Setting `:validate` on mount means required field errors ("can't be blank") show before the user has touched anything. This is a hostile user experience.

### 3.5 Empty Struct in Edit Form Validate

**Severity:** BLOCK

```elixir
# BAD -- using %Item{} for edit loses existing data
def handle_event("validate", %{"item" => params}, socket) do
  form =
    %Item{}  # WRONG for edit!
    |> Context.change_item(params)
    |> to_form(action: :validate)

  {:noreply, assign(socket, form: form)}
end

# GOOD -- use the existing record
def handle_event("validate", %{"item" => params}, socket) do
  form =
    socket.assigns.item
    |> Context.change_item(params)
    |> to_form(action: :validate)

  {:noreply, assign(socket, form: form)}
end
```

**Why:** `change_item(%Item{}, params)` compares against an empty struct. Fields not in `params` (because the user hasn't changed them) appear as no-change, losing their existing values. The changeset must diff against the existing record.

### 3.6 Using :let={f} in LiveView Forms

**Severity:** WARN

```heex
<%!-- BAD -- :let bypasses change tracking --%>
<.form :let={f} for={@form} id="item-form" phx-change="validate" phx-submit="save">
  <.input field={f[:title]} />
</.form>

<%!-- GOOD -- use @form directly --%>
<.form for={@form} id="item-form" phx-change="validate" phx-submit="save">
  <.input field={@form[:title]} />
</.form>
```

**Why:** `:let={f}` creates a new form binding that doesn't participate in LiveView's change tracking. This means the form may not re-render correctly when the changeset changes. `:let` is only appropriate for dead views (non-LiveView) or HTTP action forms.

### 3.7 Missing on_replace for Nested Forms

**Severity:** BLOCK

```elixir
# BAD -- crashes when removing nested items
has_many :items, Item
embeds_many :settings, Setting

# GOOD -- on_replace required for add/remove
has_many :items, Item, on_replace: :delete
embeds_many :settings, Setting, on_replace: :delete
```

**Why:** When a nested form item is removed, Ecto needs to know what to do with the existing database record. Without `on_replace`, Ecto raises `RuntimeError` because the default `:raise` strategy forbids replacement.

### 3.8 Nested Form Button Without type="button"

**Severity:** BLOCK

```heex
<%!-- BAD -- submits the form instead of dispatching change --%>
<button name="parent[items_drop][]" value={item_form.index}
        phx-click={JS.dispatch("change")}>
  Remove
</button>

<%!-- GOOD -- type="button" prevents form submission --%>
<button type="button" name="parent[items_drop][]" value={item_form.index}
        phx-click={JS.dispatch("change")}>
  Remove
</button>
```

**Why:** The default button type in HTML is `"submit"`. Without `type="button"`, clicking "Remove" submits the entire form instead of triggering the change event for item removal.

### 3.9 Missing Empty Drop Input for Nested Forms

**Severity:** WARN

```heex
<%!-- BAD -- removing all items doesn't work --%>
<.inputs_for :let={item_form} field={@form[:items]}>
  <button type="button" name="parent[items_drop][]" value={item_form.index}
          phx-click={JS.dispatch("change")}>Remove</button>
</.inputs_for>

<%!-- GOOD -- empty hidden input ensures the key is always present --%>
<.inputs_for :let={item_form} field={@form[:items]}>
  <button type="button" name="parent[items_drop][]" value={item_form.index}
          phx-click={JS.dispatch("change")}>Remove</button>
</.inputs_for>
<input type="hidden" name="parent[items_drop][]" />
```

**Why:** If all nested items are removed, the `items_drop[]` input name has no entries in the form. Without the empty hidden input, the key is absent from params entirely, so the server doesn't know items were removed.

### 3.10 Params Not Nested Under Form Name

**Severity:** BLOCK

```elixir
# BAD -- params are always nested under the form name key
def handle_event("save", params, socket) do
  case Context.create_item(params) do
    # params is %{"item" => %{...}, "_csrf_token" => ...}
    # This passes the whole map including CSRF token!
  end
end

# GOOD -- destructure the nested params
def handle_event("save", %{"item" => item_params}, socket) do
  case Context.create_item(item_params) do
    {:ok, item} -> {:noreply, push_navigate(socket, to: ~p"/items/#{item}")}
    {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
  end
end
```

**Why:** Form params arrive nested under the form name key (derived from the changeset schema). Passing the outer map to context functions includes extra keys (`_csrf_token`, `_target`) that cause unexpected behavior or changeset errors.

### 3.11 LiveComponent Form Missing phx-target

**Severity:** BLOCK

```elixir
# BAD -- events go to parent LiveView, not the component
def render(assigns) do
  ~H"""
  <.form for={@form} id="item-form" phx-change="validate" phx-submit="save">
    <.input field={@form[:title]} />
  </.form>
  """
end

# GOOD -- phx-target routes events to the component
def render(assigns) do
  ~H"""
  <.form for={@form} id="item-form" phx-target={@myself}
         phx-change="validate" phx-submit="save">
    <.input field={@form[:title]} />
  </.form>
  """
end
```

**Why:** Without `phx-target={@myself}`, form events are sent to the parent LiveView process, which doesn't have the component's `handle_event` callbacks. The parent crashes with a function clause error or silently ignores the event.

## 4. Checklist

### Before Writing a Form
- [ ] Schema has `changeset/2` with cast, validations, constraints
- [ ] Context has `change_item/2` (wraps changeset for form init)
- [ ] Context has `create_item/1` and/or `update_item/2`
- [ ] For nested forms: association has `on_replace: :delete`

### Mount
- [ ] Initializes `form: to_form(changeset)` in assigns
- [ ] Does NOT set `action: :validate` on mount
- [ ] For edit: loads existing record and stores in assigns
- [ ] `@impl true` on mount callback

### Validate Handler
- [ ] Uses `to_form(changeset, action: :validate)`
- [ ] For edit: diffs against `socket.assigns.item` (not `%Item{}`)
- [ ] `@impl true` on handle_event

### Save Handler
- [ ] Destructures params: `%{"item" => item_params}`
- [ ] Handles both `{:ok, _}` and `{:error, changeset}`
- [ ] On error: `assign(socket, form: to_form(changeset))`
- [ ] On success: `push_navigate` or `put_flash`
- [ ] `@impl true` on handle_event

### Template
- [ ] `<.form>` has `id`, `phx-change`, and `phx-submit`
- [ ] Uses `@form` (not `@changeset`)
- [ ] Inputs use `field={@form[:field_name]}`
- [ ] No `:let={f}` for LiveView forms
- [ ] Nested form buttons have `type="button"` + `JS.dispatch("change")`
- [ ] Empty hidden input for `items_drop[]` / `items_sort[]`

### LiveComponent Forms
- [ ] `phx-target={@myself}` on the `<.form>`
- [ ] Notifies parent via `send(self(), {__MODULE__, msg})`
- [ ] `update/2` callback assigns form from parent data

## 5. Complete Create Form Pattern

```elixir
# Context
def change_item(%Item{} = item, attrs \\ %{}), do: Item.changeset(item, attrs)
def create_item(attrs), do: %Item{} |> Item.changeset(attrs) |> Repo.insert()

# LiveView
@impl true
def mount(_params, _session, socket) do
  changeset = Context.change_item(%Item{})
  {:ok, assign(socket, form: to_form(changeset))}
end

@impl true
def handle_event("validate", %{"item" => params}, socket) do
  form = %Item{} |> Context.change_item(params) |> to_form(action: :validate)
  {:noreply, assign(socket, form: form)}
end

@impl true
def handle_event("save", %{"item" => params}, socket) do
  case Context.create_item(params) do
    {:ok, item} ->
      {:noreply, socket |> put_flash(:info, "Created") |> push_navigate(to: ~p"/items/#{item}")}
    {:error, changeset} ->
      {:noreply, assign(socket, form: to_form(changeset))}
  end
end
```

```heex
<.form for={@form} id="item-form" phx-change="validate" phx-submit="save">
  <.input field={@form[:title]} label="Title" required />
  <.input field={@form[:email]} type="email" label="Email" phx-debounce="blur" />
  <.button type="submit" disabled={not @form.source.valid?}>Save</.button>
</.form>
```

## 6. Complete Edit Form Pattern

```elixir
@impl true
def mount(%{"id" => id}, _session, socket) do
  item = Context.get_item!(id)
  changeset = Context.change_item(item)
  {:ok, assign(socket, item: item, form: to_form(changeset))}
end

@impl true
def handle_event("validate", %{"item" => params}, socket) do
  form = socket.assigns.item |> Context.change_item(params) |> to_form(action: :validate)
  {:noreply, assign(socket, form: form)}
end

@impl true
def handle_event("save", %{"item" => params}, socket) do
  case Context.update_item(socket.assigns.item, params) do
    {:ok, item} ->
      {:noreply, socket |> put_flash(:info, "Updated") |> push_navigate(to: ~p"/items/#{item}")}
    {:error, changeset} ->
      {:noreply, assign(socket, form: to_form(changeset))}
  end
end
```

## 7. Routing

- **Ecto changeset internals (cast, validations)** -> load `ecto`
- **File upload forms** -> load `phoenix-uploads`
- **HEEx template syntax** -> load `heex`
- **LiveView lifecycle (mount, handle_params)** -> load `liveview-lifecycle`
- **LiveComponent state management** -> load `liveview-components`
- **Form security (auth, CSRF)** -> load `security`
