# LiveView Streams

> Depth file for [liveview/SKILL.md](SKILL.md). Load the parent skill first.

## 1. Rules

1. ALWAYS use streams for collections of database records -- never store large lists in assigns.
2. ALWAYS provide `id` on the stream container and `id={dom_id}` on each item.
3. ALWAYS use `phx-update="stream"` on the container element.
4. NEVER enumerate streams -- `@streams.items` is not `Enum`-compatible.
5. NEVER use deprecated `phx-update="append"` or `phx-update="prepend"`.
6. ALWAYS use `stream(socket, :items, filtered, reset: true)` to filter -- refetch and reset.
7. ALWAYS track counts separately when needed -- streams don't support `length/1`.
8. ALWAYS use stable, unique IDs for stream items -- never timestamps or list indexes.

## 2. Decision Table

| Intent | Use | Avoid | Why |
|--------|-----|-------|-----|
| Display a list of records | `stream(socket, :items, items)` | `assign(socket, items: items)` | Memory-efficient, DOM-diffed |
| Add single item | `stream_insert(socket, :items, item)` | Re-streaming entire list | Minimal DOM update |
| Prepend item | `stream_insert(socket, :items, item, at: 0)` | `phx-update="prepend"` | Deprecated attribute |
| Remove item | `stream_delete(socket, :items, item)` | Filtering assigns | Stream-native operation |
| Remove by DOM ID | `stream_delete_by_dom_id(socket, :items, "items-123")` | Fetching record first | When you only have the DOM ID |
| Replace entire list | `stream(socket, :items, new_items, reset: true)` | Manual clear + re-stream | Atomic reset |
| Filter/search | Refetch data, `stream(socket, :items, filtered, reset: true)` | `Enum.filter(@streams.items)` | Streams are not enumerable |
| Show empty state | CSS `hidden only:block` on child div | Conditional assign check | Works with stream diffing |
| Track list count | `assign(socket, count: length(items))` separately | `length(@streams.items)` | Streams don't support length |
| Lazy load large list | `stream_async/3` or `start_async` + `stream(..., reset: true)` | Blocking in mount | Non-blocking initial load |
| Optimistic insert | Temp ID + `start_async` + swap on confirmation | Waiting for server | Instant feedback |
| Item re-render when assign changes | `stream_insert(socket, :items, item)` after assign change | Expecting auto-re-render | Streams don't re-render on external assign changes |

## 3. Patterns

### List in Assigns Instead of Stream

**Severity: BLOCK** | **Why: Entire list held in process memory, sent as full diff on every change**

```elixir
# BAD
assign(socket, items: Context.list_items())

# GOOD
stream(socket, :items, Context.list_items())
```

### Missing Container or Item IDs

**Severity: BLOCK** | **Why: LiveView can't track items for DOM diffing without stable IDs**

```heex
<%!-- BAD --%>
<div phx-update="stream">
  <div :for={{_id, item} <- @streams.items}>{item.name}</div>
</div>

<%!-- GOOD --%>
<div id="items" phx-update="stream">
  <div :for={{dom_id, item} <- @streams.items} id={dom_id}>{item.name}</div>
</div>
```

### Enumerating Streams

**Severity: BLOCK** | **Why: Streams are not Enum-compatible -- will crash or return unexpected results**

```elixir
# BAD
length(@streams.items)
Enum.filter(@streams.items, &(&1.active?))

# GOOD - track count separately
socket |> assign(item_count: length(items)) |> stream(:items, items)

# GOOD - refetch and reset for filtering
filtered = Context.list_items(active: true)
stream(socket, :items, filtered, reset: true)
```

### Unstable Stream Item IDs

**Severity: WARN** | **Why: Timestamps or indexes change between renders, causing ghost or duplicate DOM nodes**

```elixir
# BAD - index changes when list reorders
%{id: index, name: item.name}

# BAD - timestamps are not stable
%{id: DateTime.utc_now() |> to_string(), name: item.name}

# GOOD - database ID or deterministic unique key
%{id: item.id, name: item.name}
```

### Using Deprecated phx-update Values

**Severity: WARN** | **Why: `append`/`prepend` are deprecated -- use stream operations instead**

```heex
<%!-- BAD --%>
<div id="items" phx-update="append">...</div>

<%!-- GOOD --%>
<div id="items" phx-update="stream">...</div>
```

With `stream_insert(socket, :items, item, at: 0)` for prepend behavior.

## 4. Stream Operations Reference

```elixir
# Initialize
stream(socket, :items, items)

# Append (default)
stream_insert(socket, :items, item)

# Prepend
stream_insert(socket, :items, item, at: 0)

# Update existing (same ID replaces)
stream_insert(socket, :items, updated_item)

# Delete by struct
stream_delete(socket, :items, item)

# Delete by DOM ID
stream_delete_by_dom_id(socket, :items, "items-123")

# Reset entire stream
stream(socket, :items, new_items, reset: true)
```

## 5. Template Patterns

### Basic Stream

```heex
<div id="items" phx-update="stream">
  <div :for={{dom_id, item} <- @streams.items} id={dom_id}>
    {item.name}
  </div>
</div>
```

### Empty State (CSS-Only)

```heex
<div id="items" phx-update="stream">
  <div class="hidden only:block text-gray-500 p-4">No items yet</div>
  <div :for={{dom_id, item} <- @streams.items} id={dom_id}>
    {item.name}
  </div>
</div>
```

The `hidden only:block` div shows only when it's the only child (CSS `:only-child`).

### Re-Insert When Assigns Change

If an external assign affects how a streamed item renders, re-stream the item to trigger a re-render:

```elixir
socket
|> assign(:editing_id, message.id)
|> stream_insert(:messages, message)
```

## 6. Advanced Patterns

### Combining Streams with Async

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:loading, true)
   |> stream(:notes, [])
   |> start_async(:load_notes, fn -> Notes.list_all() end)}
end

def handle_async(:load_notes, {:ok, notes}, socket) do
  {:noreply,
   socket
   |> assign(:loading, false)
   |> stream(:notes, notes, reset: true)}
end
```

Note: `assign_async` doesn't directly support streams. Use `start_async` with `stream(..., reset: true)` in the callback.

### stream_async (v1.1.5+)

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> stream(:items, [])
   |> stream_async(:items, fn -> {:ok, MyApp.Items.list_all()} end)}
end
```

### Dynamic Forms with Streams

Use streams to manage collections of independent, editable forms:

```elixir
defp build_item_form(item, params \\ %{}, action \\ nil) do
  changeset = Items.change_item(item, params) |> Map.put(:action, action)
  to_form(changeset, id: "item-form-#{changeset.data.id || "new"}")
end

def mount(%{"list_id" => list_id}, _session, socket) do
  item_forms = list_id |> Items.list_items() |> Enum.map(&build_item_form/1)
  {:ok, socket |> assign(:list_id, list_id) |> stream(:items, item_forms)}
end

def handle_event("validate", %{"item" => params, "id" => id}, socket) do
  item = Items.get_item(id)
  {:noreply, stream_insert(socket, :items, build_item_form(item, params, :validate))}
end
```

**Key:** Custom form IDs are critical -- `to_form(changeset, id: "unique-id")` enables stream tracking.

### Optimistic Stream Insert with Temp ID

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
```

Style pending items:

```heex
<div :for={{dom_id, item} <- @streams.items} id={dom_id}
     class={if item[:pending?], do: "opacity-50 animate-pulse"}>
  {item.title}
</div>
```

### Nested Forms vs Stream Forms

| Aspect | Nested Forms (`inputs_for`) | Stream Forms |
|--------|----------------------------|--------------|
| Data structure | Parent with children | Independent items |
| Validation | All at once on parent submit | Each item independently |
| Save | Single transaction | Per-item saves |
| Use case | Recipe with ingredients | Todo list, kanban |

## 7. Checklist

- [ ] Collections use `stream()`, not `assign()` with lists
- [ ] Container has `id` attribute and `phx-update="stream"`
- [ ] Each item uses `id={dom_id}` from the stream tuple
- [ ] No `Enum` operations on `@streams.*`
- [ ] Counts tracked via separate assign when needed
- [ ] Filtering done via refetch + `reset: true`
- [ ] Stream item IDs are stable (database IDs, not timestamps/indexes)
- [ ] Empty state uses `hidden only:block` CSS pattern
