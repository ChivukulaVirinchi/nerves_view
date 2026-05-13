# LiveView Optimistic UI

> Depth file for [liveview/SKILL.md](SKILL.md). Load the parent skill first.

## 1. Rules

1. ALWAYS keep data state on the server, visual feedback on the client.
2. ALWAYS apply immediate client feedback first, then push the event to the server.
3. ALWAYS use `phx-disable-with` on buttons that trigger server mutations.
4. ALWAYS plan for failure -- optimistic visuals need revert paths on server rejection.
5. ALWAYS use `JS.push` (not bare `phx-click`) when combining with other JS commands.
6. ALWAYS respect `prefers-reduced-motion` with a CSS guard on animations.
7. ALWAYS provide `aria-live` regions for announcing mutation outcomes to screen readers.
8. NEVER manually mutate DOM where `JS.*` commands work.
9. NEVER use `phx-update="ignore"` and expect server patches to revert inside it.
10. NEVER use `phx-hook` for things JS commands handle natively.
11. NEVER rely on independent response order for correctness -- track request IDs for async.

## 2. Decision Table

### Interaction Classification

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Purely visual toggle (open/close/expand) | `JS.toggle` / `JS.toggle_class` | Server round-trip | No server state change needed |
| Server mutation (save/delete/archive) | `JS.push` + optimistic visuals | Waiting for response before feedback | Instant perceived response |
| Rich browser behavior (media, drag/drop) | `phx-hook` or colocated hooks | Server-side workaround | JS APIs require client execution |
| Large collections | Streams with optimistic insert | Full list re-render | Minimal DOM updates |

### Loading Feedback Level

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Button-only feedback | `phx-disable-with` | No feedback at all | Prevents double-click, shows progress |
| Button + related UI element | `JS.push(..., loading: "#other-element")` | Only disabling button | Shows context of what's loading |
| Whole page transition | `JS.push(..., page_loading: true)` | Multiple element targets | Heavy operation indication |
| Multiple elements | Compose `JS.add_class` calls in pipe | Single loading target | Fine-grained feedback |

### Error Recovery Strategy

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Simple server-rendered revert | Let server diff restore correct state | Manual JS revert | Server patches are automatic |
| JS.add_class optimistic visuals | `push_event` + hook to remove classes | Hoping server patches revert them | `JS.add_class` persists through patches |
| Destructive action with undo | Delayed execution with `Process.send_after` + cancel | Immediate delete + apologize | User gets a recovery window |
| Concurrent click protection | `phx-disable-with` or `JS.add_class("pointer-events-none")` | No protection | Prevents duplicate mutations |

## 3. Patterns

### No Loading Feedback

**Severity: WARN** | **Why: User has no indication their action was received -- leads to double-clicks**

```heex
<%!-- BAD --%>
<button phx-click="save">Save</button>

<%!-- GOOD --%>
<button phx-click="save" phx-disable-with="Saving...">Save</button>
```

### Optimistic Row Delete

**Severity: SUGGEST** | **Why: Visual fade before server confirms makes UI feel instant**

```heex
<button
  phx-click={
    JS.push("delete", loading: "#row-#{item.id}")
    |> JS.add_class("opacity-50 pointer-events-none", to: "#row-#{item.id}")
  }
  phx-disable-with="Removing..."
>
  Remove
</button>
```

### Instant Toggle Without Round-Trip

**Severity: SUGGEST** | **Why: Pure visual state changes don't need server confirmation**

```heex
<button phx-click={JS.toggle(to: "#details-#{@id}", display: "inline")}>
  More info
</button>
```

### Instant ARIA State Transitions

**Severity: SUGGEST** | **Why: Immediate accessibility state without waiting for server**

```heex
<button
  id={"expander-#{@id}"}
  phx-click={JS.toggle_attribute({"aria-expanded", "true", "false"})}
  aria-expanded="false"
>
  Toggle
</button>
```

### Composing Multiple Loading Indicators

**Severity: SUGGEST** | **Why: Multiple UI areas reflect the in-progress operation**

```heex
<button phx-click={
  JS.push("checkout", loading: "#cart-summary")
  |> JS.add_class("opacity-50", to: "#cart-items")
  |> JS.add_class("animate-pulse", to: "#order-total")
}>
  Place order
</button>
```

### Optimistic Stream Insert with Temp ID

**Severity: SUGGEST** | **Why: Item appears immediately, swapped with real record on server confirmation**

```elixir
def handle_event("add_item", params, socket) do
  temp_id = "temp-#{System.unique_integer([:positive])}"
  temp_item = %{id: temp_id, title: params["title"], pending?: true}

  socket =
    socket
    |> stream_insert(:items, temp_item, at: 0)
    |> start_async({:create_item, temp_id}, fn ->
      {temp_id, MyApp.Items.create(params)}
    end)

  {:noreply, socket}
end

def handle_async({:create_item, _}, {:ok, {temp_id, {:ok, item}}}, socket) do
  {:noreply,
   socket
   |> stream_delete(:items, %{id: temp_id})
   |> stream_insert(:items, item, at: 0)}
end

def handle_async({:create_item, _}, {:ok, {temp_id, {:error, _}}}, socket) do
  {:noreply,
   socket
   |> stream_delete(:items, %{id: temp_id})
   |> put_flash(:error, "Could not create item")}
end
```

Style pending items:

```heex
<div :for={{dom_id, item} <- @streams.items} id={dom_id}
     class={if item[:pending?], do: "opacity-50 animate-pulse"}>
  {item.title}
</div>
```

### Stream Delete with CSS Transition

**Severity: SUGGEST** | **Why: Delay DOM removal so CSS animation completes**

```heex
<button phx-click={
  JS.push("delete_item", value: %{id: item.id})
  |> JS.transition(
    {"transition-opacity duration-300", "opacity-100", "opacity-0"},
    to: "#items-#{item.id}")
}>
  Delete
</button>
```

```elixir
def handle_event("delete_item", %{"id" => id}, socket) do
  case MyApp.Items.delete(id) do
    {:ok, item} ->
      Process.send_after(self(), {:remove_from_stream, item}, 300)
      {:noreply, socket}
    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Delete failed")}
  end
end

def handle_info({:remove_from_stream, item}, socket) do
  {:noreply, stream_delete(socket, :items, item)}
end
```

### Undo Window for Destructive Actions

**Severity: SUGGEST** | **Why: User gets recovery window before permanent deletion**

```elixir
def handle_event("delete", %{"id" => id}, socket) do
  ref = make_ref()
  Process.send_after(self(), {:confirm_delete, id, ref}, 5_000)

  {:noreply,
   socket
   |> assign(:pending_delete, {id, ref})
   |> put_flash(:info, "Item will be deleted. Undo?")}
end

def handle_event("undo_delete", _params, socket) do
  {:noreply, assign(socket, :pending_delete, nil)}
end

def handle_info({:confirm_delete, id, ref}, socket) do
  case socket.assigns.pending_delete do
    {^id, ^ref} ->
      MyApp.Items.delete!(id)
      {:noreply,
       socket
       |> stream_delete(:items, %{id: id})
       |> assign(:pending_delete, nil)}
    _ ->
      {:noreply, socket}  # Undo was clicked
  end
end
```

## 4. Error Recovery

### Server-Driven Revert

Server patches restore server-rendered attributes naturally. But classes added via `JS.add_class` are **not** reverted by server patches -- they persist until explicitly removed.

### Explicit Revert via push_event

```elixir
# Server side - on mutation failure
{:error, _reason} ->
  {:noreply,
   socket
   |> push_event("revert-optimistic", %{id: id})
   |> put_flash(:error, "Archive failed")}
```

```javascript
// Client side - hook removes optimistic classes
Hooks.OptimisticContainer = {
  mounted() {
    this.handleEvent("revert-optimistic", ({ id }) => {
      const el = document.getElementById(`item-${id}`)
      if (el) {
        el.classList.remove("opacity-50", "pointer-events-none", "line-through")
      }
    })
  }
}
```

## 5. Race Conditions

### Request ID Tracking

```elixir
def handle_event("search", %{"q" => query}, socket) do
  request_id = System.unique_integer([:positive])

  socket =
    socket
    |> assign(:search_request_id, request_id)
    |> assign(:searching?, true)
    |> start_async(:search, fn -> {request_id, Search.run(query)} end)

  {:noreply, socket}
end

def handle_async(:search, {:ok, {request_id, results}}, socket) do
  if request_id == socket.assigns.search_request_id do
    {:noreply, assign(socket, results: results, searching?: false)}
  else
    {:noreply, socket}  # Stale response, discard
  end
end
```

### Serializing Concurrent Clicks

```heex
<%!-- Button-level: disable during processing --%>
<button phx-click={JS.push("process")} phx-disable-with="Processing...">
  Submit
</button>

<%!-- Row-level: lock the entire row --%>
<button phx-click={
  JS.push("archive", loading: "#row-#{item.id}")
  |> JS.add_class("pointer-events-none", to: "#row-#{item.id}")
}>
  Archive
</button>
```

## 6. Accessibility

### Screen Reader Announcements

```heex
<div role="status" aria-live="polite" class="sr-only" id="live-status">
  {@status_message}
</div>
```

### Busy State on Containers

```heex
<section id="items-list" aria-busy={@saving?}>
  ...
</section>
```

### Reduced Motion Guard

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

## 7. Validation with Latency

Always test optimistic UI under simulated latency:

```javascript
// Browser console
liveSocket.enableLatencySim(1000)  // 1 second simulated latency
```

Check for:
- Rollback flicker (optimistic class removed too fast)
- Wrong-row updates (ID mismatch)
- Duplicate submissions (missing disable-with)
- Stale response ordering

## 8. Checklist

- [ ] Interactions classified: pure visual (JS-only) vs server mutation (JS.push + optimistic)
- [ ] Submit buttons have `phx-disable-with`
- [ ] Optimistic visuals composed with `JS.push |> JS.add_class |> JS.transition`
- [ ] Failure paths revert optimistic visuals (push_event + hook for JS.add_class)
- [ ] Concurrent clicks serialized (disable-with or pointer-events-none)
- [ ] `aria-live` region present for status announcements
- [ ] `prefers-reduced-motion` CSS guard applied
- [ ] Tested with `liveSocket.enableLatencySim(1000)` in browser console
- [ ] Stream items have stable IDs (not timestamps or indexes)
