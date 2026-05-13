# Component Interface Conventions

## Attribute Naming

### Visibility & State

| Attribute | Type | Purpose |
|-----------|------|---------|
| `show` | boolean | Modal/dialog visibility |
| `open` | boolean | Drawer/panel open state |
| `expanded` | boolean | Collapsible/accordion state |
| `loading` | boolean | Loading state indicator |
| `disabled` | boolean | Input/button disabled |
| `readonly` | boolean | Read-only field |

### Data Attributes

- **Single items**: singular (`user`, `workbook`, `exercise`) with `:map`
- **Collections**: plural (`users`, `workbooks`) with `:list`
- **Current/selected**: `current_user`, `selected_id`

### Configuration

| Attribute | Type | Typical Values |
|-----------|------|----------------|
| `variant` | atom | `:default`, `:compact`, `:horizontal` |
| `size` | atom | `:sm`, `:md`, `:lg`, `:xl` |
| `color` | atom | `:default`, `:success`, `:warning`, `:danger` |
| `position` | atom | `:left`, `:right`, `:top`, `:bottom` |

### Role & Permission

```elixir
attr :role, :atom, default: :learner, values: [:learner, :author]
attr :current_user_role, :atom, required: true
```

## Slot Naming

| Slot | Purpose |
|------|---------|
| `inner_block` | Default content (use unless semantic slots exist) |
| `header` | Top section with title/actions |
| `title` | Title text |
| `description` | Subtitle/helper text |
| `footer` | Bottom actions/info |
| `actions` | Action buttons |
| `action` | CTA in empty states |
| `empty` | Empty state content |

## Event Naming

Events are verb-based strings passed as attrs:

| Event | Purpose | Context |
|-------|---------|---------|
| `on_submit` | Form submission | Forms |
| `on_save` | Save action | Forms, editors |
| `on_change` | Value changed | Inputs |
| `on_search` | Search query | Search inputs |
| `on_cancel` | Reject/back out | Modals, forms |
| `on_close` | Close panel | Drawers, panels (neutral) |
| `on_confirm` | Confirm action | Confirmation modals |
| `on_delete` | Permanent deletion | Delete operations |
| `on_remove` | Remove from collection | List operations |

**Key distinctions:**
- `on_cancel` vs `on_close`: cancel = user rejects action; close = neutral panel closing
- `on_delete` vs `on_remove`: delete = permanent; remove = from a collection

## Component Categories

### Dialog (SutraUI)
- `show` boolean, `on_cancel` for dismissal
- Size via `class`: `sm:max-w-sm`, `sm:max-w-lg`, `sm:max-w-3xl`, `sm:max-w-5xl`
- Slots: `:title`, `:description`, `:inner_block`, `:footer`

### Drawer (BaseDrawer)
- `open` boolean, `on_close` for dismissal, `position: :left | :right`
- Slots: `:header_action`, `:content`, `:footer`

### List/Grid
- Domain-specific plural attr (`members`, `workbooks`), `loading`, `search`/`query`
- `on_search` event, built-in empty state
- Grids use LiveView streams with `phx-update="stream"`

### EmptyState
- Required `title`, optional `description`, `icon` (default `lucide-inbox`)
- Optional `:action` slot for CTA button

## Checklist

When creating a new component:
- [ ] Attribute names follow conventions (show/open/loading/disabled)
- [ ] All attrs have type declarations and docs
- [ ] Events use standard names (on_submit/on_cancel/on_close/on_delete)
- [ ] Slots follow naming conventions (inner_block/header/footer)
- [ ] Defaults provided for optional attributes
- [ ] Composition over complexity — break large components into smaller ones

## Quick Reference

```elixir
# Visibility
attr :show, :boolean        # Modals
attr :open, :boolean        # Drawers

# State
attr :loading, :boolean, default: false
attr :disabled, :boolean, default: false

# Events
attr :on_submit, :string    # Forms
attr :on_cancel, :string    # Modals/forms
attr :on_close, :string     # Drawers/panels
attr :on_delete, :string    # Deletion

# Slots
slot :inner_block           # Default content
slot :header                # Top section
slot :footer                # Bottom section
slot :action                # Action buttons

# Configuration
attr :variant, :atom, default: :default, values: [...]
attr :size, :atom, default: :md, values: [:sm, :md, :lg, :xl]
```
