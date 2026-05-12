# Phase 2 — Scrubber + playback UI

## Goal

The timeline scrubber on the camera page is **fully functional**:

1. Motion alerts appear as markers on the timeline within ~1 s of being recorded.
2. Dragging the scrubber seeks the video to that timestamp (HLS playback).
3. While HLS is playing back, the scrubber cursor follows the playback position.
4. A "live" button / right-edge tap returns to live (WebRTC).
5. Server and client agree on `mode` (live / playback) — no UI confusion.

## Pre-flight

- Phase 1 complete and verified — WebRTC live stream stable.
- Recording is working (segments exist in `/data/nerves_view/recordings/test-cam/`).
- Browser closed before testing.

## Files you'll touch

| File | Section | Change |
|---|---|---|
| `lib/nerves_view_web/live/camera_live.ex` | `mount/3`, `handle_info/2`, `handle_event/3` | Push markers, push cursor, track mode |
| `assets/js/hooks/timeline_scrubber.js` | hook body | Listen for `dvr:mode`, render cursor accordingly |

Everything else (`camera_player.js`, `dvr_controller.ex`, `segment_index.ex`, `playlist_builder.ex`, `alerts.ex`) is already correct — **read-only references** for this phase.

## Pre-read

Read these files in full before editing:

1. `assets/js/hooks/timeline_scrubber.js` (full file, ~215 lines).
2. `assets/js/hooks/camera_player.js` (focus on `dvr:play`, `dvr:live`, `dvr:time_update`).
3. `lib/nerves_view_web/live/camera_live.ex` (full).
4. `lib/nerves_view/alerts.ex` (full — to understand the alert struct).
5. `lib/nerves_view/dvr/segment_index.ex` — function `retention_window/1`.

## Architecture (the data flow you're wiring)

```
Motion (alerts.ex) --PubSub "alerts:motion"-->  camera_live.ex
                                                     |
                                                     v push_event("dvr:markers", %{markers: [...]})
                                                 timeline_scrubber.js (renders red ticks)

User drags scrubber  ---push_event("dvr:seek")--->  camera_live.ex
                                                     |
                                                     v push_event("dvr:play", %{url: hls_playlist_url})
                                                 camera_player.js (switches to HLS)
                                                     |
                                                     v on HTMLMediaElement timeupdate
                                                       push_event("dvr:time_update", %{current_time})
                                                                |
                                                     <----------+
                                                     v push_event("dvr:playback_pos", %{ts: ...})
                                                 timeline_scrubber.js (moves cursor)

User clicks live   ---push_event("dvr:go_live")-->  camera_live.ex
                                                     v push_event("dvr:live", %{}) + push_event("dvr:mode", %{mode: "live"})
                                                 camera_player.js (tears down HLS, reopens WebRTC)
```

## Steps

### Step 1 — Add `mode` and `playback_start_ts` to LiveView assigns

`lib/nerves_view_web/live/camera_live.ex`, in `mount/3` (around line 30–40), add to the initial assigns:

```elixir
|> assign(:mode, :live)
|> assign(:playback_start_ts, nil)
```

(Place these next to the existing `motion: nil` and `playback_from: nil` lines. Remove `playback_from: nil` — it's the same thing under a different name; consolidate.)

### Step 2 — Push motion markers when alerts arrive

`lib/nerves_view_web/live/camera_live.ex`, in `handle_info({:motion_alert, alert}, socket)` (currently around line 55–61):

Replace the body with:

```elixir
def handle_info({:motion_alert, alert}, socket) do
  if alert.camera_id == socket.assigns.camera.id do
    marker = %{ts: alert.inserted_at}

    {:noreply,
     socket
     |> assign(:motion, alert)
     |> push_event("dvr:markers", %{markers: [marker], append: true})}
  else
    {:noreply, socket}
  end
end
```

The `append: true` flag tells the JS to add this marker without clobbering existing ones (see Step 5).

### Step 3 — On `:tick`, send the full marker set within the retention window

`lib/nerves_view_web/live/camera_live.ex`, find the `handle_info(:tick, ...)` clause (around line 48–53). Append marker pushing to the existing body:

```elixir
def handle_info(:tick, socket) do
  Process.send_after(self(), :tick, @tick_ms)
  cam_id = socket.assigns.camera.id

  alerts = NervesView.Alerts.list(camera_id: cam_id, since: System.system_time(:second) - dvr_window_seconds())
  markers = Enum.map(alerts, &%{ts: &1.inserted_at})

  {:noreply,
   socket
   |> assign(:diag, NervesView.diagnostics(cam_id))
   |> assign(:retention, NervesView.DVR.SegmentIndex.retention_window(cam_id))
   |> push_event("dvr:markers", %{markers: markers, append: false})}
end
```

(Replace the existing body — keep the existing `Process.send_after` and `assign` calls, but add the alerts query and the `push_event`.)

`dvr_window_seconds/0` is a small module-private helper — defined once near the top of the module:

```elixir
defp dvr_window_seconds, do: 30 * 24 * 3600   # 30 days, matches retention
```

If `NervesView.Alerts.list/1` doesn't exist with these params, add it as a thin wrapper around whatever does (see `lib/nerves_view/alerts.ex`). If alerts aren't being generated yet (motion detection is deferred to a later phase), this is fine — the markers list will just be empty.

### Step 4 — Wire the `dvr:time_update` cursor echo

`lib/nerves_view_web/live/camera_live.ex`, replace the existing no-op `handle_event("dvr:time_update", ...)` (around line 88–90) with:

```elixir
def handle_event("dvr:time_update", %{"current_time" => ct}, socket) do
  case socket.assigns.playback_start_ts do
    nil ->
      {:noreply, socket}

    start_ts when is_integer(start_ts) ->
      ts = start_ts + round(ct)
      {:noreply, push_event(socket, "dvr:playback_pos", %{ts: ts})}
  end
end
```

### Step 5 — Set `playback_start_ts` and `mode` on seek; clear on go-live

`lib/nerves_view_web/live/camera_live.ex`, in `handle_event("dvr:seek", ...)` (around line 71–79):

```elixir
def handle_event("dvr:seek", %{"from" => from_ts} = params, socket) do
  cam_id = socket.assigns.camera.id
  from = ensure_int(from_ts)
  hls_url = "/api/dvr/#{cam_id}/playlist.m3u8?from=#{from}&to=#{from + 600}"

  {:noreply,
   socket
   |> assign(:mode, :playback)
   |> assign(:playback_start_ts, from)
   |> push_event("dvr:play", %{url: hls_url})
   |> push_event("dvr:mode", %{mode: "playback"})}
end
```

In `handle_event("dvr:go_live", ...)` (around line 81–86):

```elixir
def handle_event("dvr:go_live", _params, socket) do
  {:noreply,
   socket
   |> assign(:mode, :live)
   |> assign(:playback_start_ts, nil)
   |> push_event("dvr:live", %{})
   |> push_event("dvr:mode", %{mode: "live"})}
end
```

Add a tiny coercion helper at the bottom of the module:

```elixir
defp ensure_int(v) when is_integer(v), do: v
defp ensure_int(v) when is_binary(v), do: String.to_integer(v)
```

### Step 6 — Teach the scrubber about `dvr:mode` and `append`

`assets/js/hooks/timeline_scrubber.js`:

**6.1** Where the hook handles `dvr:markers` (around line 25), accept the `append` flag:

```js
this.handleEvent("dvr:markers", ({markers, append}) => {
  if (append) {
    this.markers = (this.markers || []).concat(markers || [])
  } else {
    this.markers = markers || []
  }
  this.renderMarkers()
})
```

**6.2** Add a new handler right below, for mode:

```js
this.handleEvent("dvr:mode", ({mode}) => {
  this.mode = mode  // "live" | "playback"
  this.el.classList.toggle("scrubbing", mode === "playback")
  if (mode === "live") {
    this.cursor.style.left = "100%"
  }
})
```

**6.3** The existing `dvr:playback_pos` handler already moves the cursor. Confirm it bails out cleanly when `this.mode !== "playback"` (add the guard if missing):

```js
this.handleEvent("dvr:playback_pos", ({ts}) => {
  if (this.mode !== "playback") return
  // ...existing cursor positioning...
})
```

### Step 7 — Styling (Sutra-only) for the new states

The scrubber already has dedicated CSS classes in `assets/css/app.css` (`.cam-tl`, `.tl-track`, `.tl-cursor`, `.tl-marker`, `.tl-tooltip`). Add **one** new variant for the playback state:

In `assets/css/app.css`, append to the `.cam-tl` block (or create one if missing):

```css
.cam-tl.scrubbing .tl-track {
  border-color: oklch(0.55 0.2 38 / 0.5);    /* ember accent — same token as nav-dot */
}
.cam-tl.scrubbing .tl-cursor {
  background: oklch(0.55 0.2 38);
  box-shadow: 0 0 8px oklch(0.55 0.2 38 / 0.6);
}
```

**Style mandate (do NOT violate):**

- Colors only via the existing OKLCH tokens. The ember (`oklch(0.55 0.2 38)`) is the project's primary accent — reuse it. Don't introduce new hues.
- Spacing only via Tailwind utilities or the existing `.cam-tl` / `.tl-*` measurements. No magic pixels.
- The "live" / "back to live" button on the camera page MUST be a `<.button variant="...">` from Sutra UI — never a raw `<button>`.

## Verification

Restart the Pi with the new firmware:

```fish
cd ~/code/nerves/nerves_view
MIX_ENV=prod MIX_TARGET=rpi0_2 mix firmware
MIX_ENV=prod MIX_TARGET=rpi0_2 mix upload nervesview.local
```

After it comes back (~30 s):

1. **Live mode default.** Open `/cameras/test-cam`. Stream plays. Cursor sits at 100% right. No markers visible (unless motion alerts have been firing).
2. **Synthetic motion alert** to test marker rendering — in IEx on the Pi:
   ```elixir
   NervesView.Alerts.notify_motion("test-cam", System.system_time(:second), [])
   ```
   A red marker should appear on the timeline within 1 s.
3. **Click a marker.** Cursor jumps to that position, `mode` flips to "playback", HLS playlist loads in the `<video>` element, and the cursor advances **in sync** with playback.
4. **Drag the cursor.** Same — HLS loads from the dragged-to point, cursor follows playback.
5. **Live button.** Click "Live" (or whichever Sutra `<.button>` you wired). Cursor snaps to 100%, mode flips to "live", WebRTC restarts.

In IEx, sanity check `mode` tracking:
```elixir
keys = Registry.select(NervesView.Streaming.Registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
{_, pid} = Enum.find(keys, fn {_, p} -> :sys.get_state(p).state == :connected end)
:sys.get_state(pid) |> Map.take([:camera_id, :state])
```

## Style / safety rules (read again before merging)

- **Sutra components only.** No raw `<button>`, `<input>`, `<form>`, `<select>`, `<div class="bg-blue-...">`. Anything you add must use `<.button>`, `<.input>`, `<.card>`, `<.badge>`, `<.tabs>`, `<.empty>`, `<.dialog>`, `<.dropdown_menu>`, etc. The codebase is already 100% Sutra — keep it that way.
- **Reuse existing domain CSS tokens** (`.cam-*`, `.tl-*`, `.dot`, `.kv`). Add new tokens only if a genuinely new domain appears (e.g. `.rec-*` for recordings detail panel, only if needed).
- **Font:** Headings = Fraunces. Body = DM Sans. Both already global. Don't add new fonts.
- **Color:** Only the OKLCH tokens defined in `app.css` (`--primary`, `--background`, `--card`, `--sage`, `--rose`, `--ember`, etc.). No hex, no rgb, no Tailwind palette colors (`text-blue-500` and friends are forbidden).
- **Dark-mode parity.** Any new CSS must work in both light and dark modes. Test by clicking `<.theme_switcher>` in the top nav.

## Common pitfalls

- **Forgetting `phx-update="ignore"` on a parent.** If the scrubber DOM is inside a LiveView region that re-renders, LV may replace the scrubber's children and wipe its markers. The current template should already handle this via the hook's `data-*` attributes; if you change the template, verify the scrubber survives a re-render.
- **`current_time` as a string.** `dvr:time_update` may serialize as `"3.42"` not `3.42`. The `round(ct)` call will explode. Coerce with `Float.parse/1` if needed, or have the JS push a number explicitly.
- **Marker dedup.** If you push `append: true` for every motion alert, markers accumulate across reconnects. The `:tick` re-send (Step 3) periodically replaces the full list with `append: false`, which cleans things up. Don't remove that re-send.

## Rollback

```fish
git -C ~/code/nerves/nerves_view checkout lib/nerves_view_web/live/camera_live.ex assets/js/hooks/timeline_scrubber.js assets/css/app.css
```

Re-flash. Scrubber goes back to its previous (non-working) state.

## Estimated time

30 minutes coding + 10 minutes verification.

## Done when

- Motion markers visible on timeline.
- Dragging scrubber plays back HLS from that timestamp.
- Cursor follows playback.
- Live button returns to live WebRTC.
- All buttons / inputs are Sutra components; no raw HTML controls were added.
