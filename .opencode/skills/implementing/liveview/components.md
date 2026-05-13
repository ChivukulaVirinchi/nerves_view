# LiveView Components

> Depth file for [liveview/SKILL.md](SKILL.md). Load the parent skill first.

## 1. Rules

1. ALWAYS pick the simplest component type that fits -- function component before LiveComponent before hook.
2. ALWAYS keep the source of truth in the parent LiveView unless the component needs true local state.
3. ALWAYS provide unique `id` on every LiveComponent.
4. ALWAYS use `phx-target={@myself}` on LiveComponent events -- without it, events go to parent.
5. ALWAYS use `send(self(), ...)` or callback assigns to communicate from child to parent.
6. ALWAYS pair hooks that own DOM with `phx-update="ignore"` and a stable `id`.
7. NEVER use LiveComponents for code organization alone -- function components have zero overhead.
8. NEVER have parent and child both mutating the same domain state independently.
9. ALWAYS design component APIs with explicit `attr` and `slot` contracts.
10. ALWAYS use `update_many/1` in LiveComponents to batch-load data and prevent N+1 queries.

## 2. Decision Table

### Component Type Selection

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Reusable stateless markup | Function component | LiveComponent | No process overhead, simpler API |
| Shared layout wrapper | Function component with slots | `embed_templates` alone | Composable, slot-driven |
| Encapsulated state + event handling | LiveComponent with `id` | Function component with assigns hack | Proper isolation, `phx-target` |
| Multiple instances needing batch data load | LiveComponent with `update_many/1` | Function component (N+1) | Single batch query for all instances |
| Independent process surviving navigation | `live_render` with `sticky: true` | LiveComponent | Separate process, own lifecycle |
| Browser-owned behavior (media, drag, canvas) | JS Hook | LiveComponent | JS APIs require client execution |
| Third-party JS library integration | JS Hook with `phx-update="ignore"` | Server-side workaround | Library manages its own DOM |
| Tabular data with custom columns | Function component + slot attrs | Hardcoded table | Declarative `:col` with `:let` |

### Communication Direction

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Parent to function component | Props via `attr` assigns | Process messages | Function components are not processes |
| Parent to LiveComponent | Props in `<.live_component>` tag | Direct assign manipulation | LiveComponent `update/2` receives them |
| Parent to LiveComponent (imperative) | `send_update(Module, id: "x", key: val)` | Direct socket access | Async update to specific instance |
| LiveComponent to parent | `send(self(), {:event, data})` | Reaching into parent socket | Parent's `handle_info` decides what to do |
| LiveComponent to parent (callback) | Callback assign: `on_close={fn -> send(self(), :closed) end}` | Hardcoded parent coupling | Component stays generic |
| Hook to LiveView | `this.pushEvent(event, payload)` | Direct DOM manipulation for data | Server is source of truth |
| LiveView to Hook | `push_event(socket, event, payload)` | Data attributes alone | Explicit server-to-client channel |

## 3. Patterns

### LiveComponent for Static Markup

**Severity: WARN** | **Why: LiveComponent has process overhead -- function component is zero-cost for stateless UI**

```elixir
# BAD - LiveComponent wrapping static markup
defmodule MyAppWeb.BadgeComponent do
  use Phoenix.LiveComponent
  def render(assigns) do
    ~H"""<span class="badge">{@label}</span>"""
  end
end

# GOOD - function component
attr :label, :string, required: true
def badge(assigns) do
  ~H"""<span class="badge">{@label}</span>"""
end
```

### Missing phx-target on LiveComponent Events

**Severity: BLOCK** | **Why: Without `phx-target={@myself}`, events go to parent -- wrong handler executes**

```heex
<%!-- BAD - event goes to parent LiveView --%>
<button phx-click="increment">+</button>

<%!-- GOOD - event stays in component --%>
<button phx-click="increment" phx-target={@myself}>+</button>
```

### Parent and Child Mutating Same State

**Severity: BLOCK** | **Why: Race conditions, stale data, inconsistent UI**

```elixir
# BAD - both parent and component call Items.update_item independently
# Parent: handle_event("save", ...) -> Items.update_item(item, params)
# Component: handle_event("quick_edit", ...) -> Items.update_item(item, params)

# GOOD - component notifies parent, parent is single source of truth
# Component:
def handle_event("quick_edit", params, socket) do
  send(self(), {:item_edited, socket.assigns.item.id, params})
  {:noreply, socket}
end

# Parent:
def handle_info({:item_edited, id, params}, socket) do
  item = Items.get_item!(id)
  case Items.update_item(item, params) do
    {:ok, updated} -> {:noreply, stream_insert(socket, :items, updated)}
    {:error, _} -> {:noreply, put_flash(socket, :error, "Update failed")}
  end
end
```

### Hook Without phx-update="ignore"

**Severity: WARN** | **Why: LiveView DOM patches overwrite hook's DOM changes**

```heex
<%!-- BAD - LiveView will overwrite Chart.js canvas --%>
<canvas id="chart" phx-hook="Chart"></canvas>

<%!-- GOOD - LiveView leaves this DOM node alone --%>
<canvas id="chart" phx-hook="Chart" phx-update="ignore"
        data-values={Jason.encode!(@values)}></canvas>
```

**Exception:** Omit `phx-update="ignore"` when you WANT LiveView to update `data-*` attributes that trigger the hook's `updated()` callback.

### N+1 in List of LiveComponents

**Severity: WARN** | **Why: Each component instance fires a separate query in `update/2`**

```elixir
# BAD - each component loads its own product
def update(assigns, socket) do
  product = Products.get_product!(assigns.id)  # N+1!
  {:ok, assign(socket, product: product)}
end

# GOOD - batch load with update_many
def update_many(assigns_list) do
  ids = Enum.map(assigns_list, & &1.id)
  products = Products.get_many(ids) |> Map.new(&{&1.id, &1})
  Enum.map(assigns_list, fn assigns ->
    Map.put(assigns, :product, products[assigns.id])
  end)
end
```

### Huge Dispatcher Component

**Severity: SUGGEST** | **Why: One component that knows every domain variant -- violates single responsibility**

```elixir
# BAD - knows about every content type
def render(%{type: :video} = assigns), do: ~H"..."
def render(%{type: :article} = assigns), do: ~H"..."
def render(%{type: :podcast} = assigns), do: ~H"..."
# ... 15 more clauses

# GOOD - dispatch to focused components
def render(assigns) do
  ~H"""
  <.video_card :if={@type == :video} item={@item} />
  <.article_card :if={@type == :article} item={@item} />
  <.podcast_card :if={@type == :podcast} item={@item} />
  """
end
```

## 4. Component API Design

### Function Component with Attrs and Slots

```elixir
attr :name, :string, required: true
attr :class, :string, default: nil
attr :size, :string, default: "md", values: ["sm", "md", "lg"]
attr :rest, :global

slot :inner_block
slot :header

def card(assigns) do
  ~H"""
  <div class={["rounded-lg border shadow", @class]} {@rest}>
    <div :if={@header != []} class="border-b px-4 py-2 bg-gray-50">
      {render_slot(@header)}
    </div>
    <div class="px-4 py-3">{render_slot(@inner_block)}</div>
  </div>
  """
end
```

### Table Component with Slot Attributes

```elixir
slot :col, required: true do
  attr :label, :string, required: true
end
attr :rows, :list, required: true

def table(assigns) do
  ~H"""
  <table>
    <thead>
      <tr><th :for={col <- @col}>{col.label}</th></tr>
    </thead>
    <tbody>
      <tr :for={row <- @rows}>
        <td :for={col <- @col}>{render_slot(col, row)}</td>
      </tr>
    </tbody>
  </table>
  """
end
```

Usage: `<.table rows={@users}><:col :let={user} label="Name">{user.name}</:col></.table>`

### LiveComponent with Callback Communication

```elixir
defmodule MyAppWeb.ModalComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div class="modal">
      {render_slot(@inner_block)}
      <button phx-click="close" phx-target={@myself}>Close</button>
    </div>
    """
  end

  def handle_event("close", _, socket) do
    if socket.assigns[:on_close], do: socket.assigns.on_close.()
    {:noreply, socket}
  end
end

# Usage in parent
<.live_component module={ModalComponent} id="modal"
  on_close={fn -> send(self(), :modal_closed) end}>
  <p>Modal content</p>
</.live_component>
```

## 5. Boundary Guidelines

```
LiveView      -> loads data, authorizes, navigates, streams, is source of truth
Function comp -> renders cards/forms/sections, receives data via attrs
LiveComponent -> editor row, modal form, repeated stateful widget
Hook          -> media capture, editor integration, drag/drop, third-party JS
```

## 6. Checklist

- [ ] Simplest component type chosen (function > LiveComponent > hook)
- [ ] LiveComponents have unique `id` attrs
- [ ] LiveComponent events use `phx-target={@myself}`
- [ ] Child-to-parent communication via `send/2` or callback assigns
- [ ] Hooks that own DOM use `phx-update="ignore"` with stable `id`
- [ ] No N+1 queries in component render -- batch-load or preload in parent
- [ ] Component API uses explicit `attr` and `slot` declarations
- [ ] Single source of truth for domain state (parent, not distributed across children)
