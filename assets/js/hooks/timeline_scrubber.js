/**
 * TimelineScrubber — NVR-style draggable DVR timeline below each camera.
 *
 * Renders an absolute-time axis, draggable cursor, hover tooltip, LIVE
 * badge, and motion markers. Single source of truth for timezone: the
 * `tz_offset_minutes` field on `dvr:bounds`, pushed by the server based on
 * what the browser sent via the TimezoneDetector hook. We deliberately do
 * NOT use `toLocaleTimeString()` — that would silently disagree with the
 * server's `fmt_ts_local` (which other timestamps in the app use) if the
 * browser's tz and the server's stored tz_offset diverge.
 *
 * Pointer Events unify mouse + touch + pen on a single set of handlers
 * (replaces the previous mouse-only and touch-only listener pairs, which
 * caused taps to either scroll the page or be ignored on phones).
 *
 * Server events handled:
 *   dvr:bounds        %{server_time, oldest, newest, axis_start, axis_end,
 *                        has_recordings, day_label, tz_offset_minutes, tz_known}
 *   dvr:markers       %{markers: [{ts: ...}], append}
 *   dvr:mode          %{mode: "live" | "playback"}
 *   dvr:playback_pos  %{ts: ...}
 *   dvr:seek_rejected %{reason, oldest?, newest?}
 *
 * Server events pushed:
 *   dvr:seek          %{camera_id, from}
 *   dvr:go_live       %{camera_id}
 */

const SEGMENT_DURATION = 6
const LIVE_MARGIN = 5

const TimelineScrubber = {
  mounted() {
    this.cameraId = this.el.dataset.cameraId
    this.oldest = parseInt(this.el.dataset.oldest, 10) || 0
    this.newest = parseInt(this.el.dataset.newest, 10) || 0
    this.axisStart =
      parseInt(this.el.dataset.axisStart, 10) || this.oldest || nowSec() - 24 * 3600
    this.axisEnd = parseInt(this.el.dataset.axisEnd, 10) || this.newest || nowSec()
    this.hasRecordings = this.el.dataset.hasRecordings === "1"
    this.dayLabel = this.el.dataset.dayLabel || null
    this.serverTime = parseInt(this.el.dataset.serverTime, 10) || nowSec()
    this.timeOffset = this.serverTime - nowSec()
    this.tzOffsetMinutes = parseInt(this.el.dataset.tzOffset, 10) || 0
    this.tzKnown = this.el.dataset.tzKnown === "1"
    this.markers = []
    this.mode = "live"
    this.dragging = false
    this.activePointer = null
    this.hoverTs = null

    this.buildDOM()
    this.bindEvents()
    this.render()

    this._tick = setInterval(() => this.tickAdvance(), 1000)

    this.handleEvent(
      "dvr:bounds",
      ({
        server_time,
        oldest,
        newest,
        axis_start,
        axis_end,
        has_recordings,
        day_label,
        tz_offset_minutes,
        tz_known,
      }) => {
        this.serverTime = server_time
        this.timeOffset = server_time - nowSec()
        this.oldest = oldest
        this.newest = newest
        this.axisStart = axis_start ?? oldest
        this.axisEnd = axis_end ?? newest
        this.hasRecordings = !!has_recordings
        this.dayLabel = day_label || null
        this.tzOffsetMinutes = tz_offset_minutes ?? 0
        this.tzKnown = !!tz_known
        this.render()
      },
    )

    this.handleEvent("dvr:markers", ({ markers, append }) => {
      this.markers = append ? (this.markers || []).concat(markers || []) : markers || []
      this.renderMarkers()
    })

    this.handleEvent("dvr:mode", ({ mode }) => {
      this.mode = mode
      this.el.classList.toggle("scrubbing", mode === "playback")
      if (mode === "live") this.setCursorAt(this.serverNow())
      this.renderLive()
    })

    this.handleEvent("dvr:playback_pos", ({ ts }) => {
      if (this.mode === "playback" && !this.dragging) this.setCursorAt(ts)
    })

    this.handleEvent("dvr:seek_rejected", () => {
      this.mode = "live"
      this.setCursorAt(this.serverNow())
      this.renderLive()
    })
  },

  destroyed() {
    if (this._tick) clearInterval(this._tick)
  },

  // ── DOM construction ─────────────────────────────────────────────────────

  buildDOM() {
    this.el.innerHTML = ""

    this.track = el("div", "tl-track")
    this.oobLeft = el("div", "tl-oob tl-oob-left")
    this.oobRight = el("div", "tl-oob tl-oob-right")
    this.fill = el("div", "tl-fill")
    this.cursor = el("div", "tl-cursor")
    this.tooltip = el("div", "tl-tooltip")
    this.tooltip.style.display = "none"
    this.emptyOverlay = el("div", "tl-empty")
    this.emptyOverlay.style.display = "none"

    this.track.append(
      this.oobLeft,
      this.oobRight,
      this.fill,
      this.cursor,
      this.tooltip,
      this.emptyOverlay,
    )

    this.labels = el("div", "tl-labels")

    this.liveLabel = el("button", "tl-live-lbl")
    this.liveLabel.type = "button"
    this.liveLabel.textContent = "LIVE"

    this.el.append(this.track, this.labels, this.liveLabel)
  },

  bindEvents() {
    // Pointer Events: unify mouse / touch / pen. `setPointerCapture` keeps
    // events flowing to the track even when the pointer leaves it, which is
    // critical for drag-to-seek on a phone where the finger easily strays
    // off the 6px tall bar.
    this.track.addEventListener("pointerdown", (e) => this.onPointerDown(e))
    this.track.addEventListener("pointermove", (e) => this.onPointerMove(e))
    this.track.addEventListener("pointerup", (e) => this.onPointerUp(e))
    this.track.addEventListener("pointercancel", (e) => this.onPointerUp(e))
    this.track.addEventListener("pointerleave", () => this.onHoverEnd())

    this.liveLabel.addEventListener("click", () => {
      if (!this.hasRecordings && !this.tzKnown) return
      this.mode = "live"
      this.setCursorAt(this.serverNow())
      this.renderLive()
      this.pushEvent("dvr:go_live", { camera_id: this.cameraId })
    })
  },

  // ── Render ───────────────────────────────────────────────────────────────

  render() {
    this.renderEmpty()
    this.renderLabels()
    this.renderMarkers()
    this.renderOobRegions()
    if (this.mode === "live" && this.hasRecordings) this.setCursorAt(this.serverNow())
    this.renderLive()
  },

  renderEmpty() {
    if (this.hasRecordings && this.tzKnown) {
      this.emptyOverlay.style.display = "none"
      this.el.classList.remove("empty")
      return
    }
    this.emptyOverlay.textContent = !this.tzKnown
      ? "Loading…"
      : this.dayLabel
        ? `No recordings on ${this.dayLabel}`
        : "No recordings yet"
    this.emptyOverlay.style.display = "flex"
    this.el.classList.add("empty")
    this.cursor.style.left = "-100%"
    this.fill.style.width = "0%"
  },

  renderLabels() {
    this.labels.innerHTML = ""
    if (!this.tzKnown) return
    if (this.axisSpan() <= 0) return

    // 5 evenly-spaced labels across the axis. Format via server-supplied
    // tz_offset so the labels match every other timestamp in the app.
    const count = 5
    for (let i = 0; i <= count; i++) {
      const ts = this.axisStart + Math.round((i / count) * this.axisSpan())
      const lbl = el("span", "tl-time-lbl")
      lbl.textContent = formatLocal(ts, this.tzOffsetMinutes, false)
      lbl.style.left = `${(i / count) * 100}%`
      this.labels.appendChild(lbl)
    }
  },

  renderMarkers() {
    Array.from(this.track.querySelectorAll(".tl-marker")).forEach((m) => m.remove())
    if (!this.hasRecordings) return
    const span = this.axisSpan()
    if (span <= 0) return

    this.markers.forEach(({ ts }) => {
      const pct = (ts - this.axisStart) / span
      if (pct < 0 || pct > 1) return

      const m = el("div", "tl-marker")
      m.style.left = `${pct * 100}%`
      m.title = formatLocal(ts, this.tzOffsetMinutes, true)
      m.addEventListener("click", (e) => {
        e.stopPropagation()
        this.seekTo(ts)
      })
      this.track.appendChild(m)
    })
  },

  renderOobRegions() {
    if (!this.hasRecordings) {
      this.oobLeft.style.width = "0%"
      this.oobRight.style.width = "0%"
      return
    }
    const span = this.axisSpan()
    if (span <= 0) return

    const leftPct = clamp((this.oldest - this.axisStart) / span, 0, 1)
    const rightPct = clamp((this.axisEnd - this.newest) / span, 0, 1)
    this.oobLeft.style.width = `${leftPct * 100}%`
    this.oobRight.style.width = `${rightPct * 100}%`
  },

  renderLive() {
    const live = this.mode === "live"
    this.liveLabel.classList.toggle("active", live)
    this.el.classList.toggle("at-live", live)
  },

  // ── Cursor / tooltip ─────────────────────────────────────────────────────

  setCursorAt(ts) {
    const span = this.axisSpan()
    if (span <= 0) return
    const pct = clamp((ts - this.axisStart) / span, 0, 1)
    this.cursor.style.left = `${pct * 100}%`
    this.fill.style.width = `${pct * 100}%`
  },

  showTooltip(pct, ts) {
    this.tooltip.style.left = `${pct * 100}%`
    this.tooltip.textContent = formatLocal(ts, this.tzOffsetMinutes, true)
    this.tooltip.style.display = "block"
  },

  hideTooltip() {
    this.tooltip.style.display = "none"
  },

  tickAdvance() {
    if (this.mode !== "live") return
    if (!this.hasRecordings) return
    if (this.axisSpan() <= 0) return
    this.setCursorAt(this.serverNow())
  },

  // ── Pointer interaction ──────────────────────────────────────────────────

  onPointerDown(e) {
    if (!this.tzKnown) return
    if (!this.hasRecordings) return
    if (this.axisSpan() <= 0) return

    this.dragging = true
    this.activePointer = e.pointerId
    this.cursor.classList.add("dragging")

    try {
      this.track.setPointerCapture(e.pointerId)
    } catch (_) {
      // Some older browsers may not support setPointerCapture on this element.
      // Fall back to global listeners — not needed because pointer events
      // bubble even without capture in most modern engines.
    }

    this.moveCursorToEvent(e)
  },

  onPointerMove(e) {
    if (this.dragging && e.pointerId === this.activePointer) {
      this.moveCursorToEvent(e)
    } else if (!this.dragging && e.pointerType === "mouse") {
      // Hover tooltip on mouse only — on phones we don't get hover, and the
      // tap-to-seek interaction already shows a tooltip at the touch point
      // during drag.
      const rect = this.track.getBoundingClientRect()
      const pct = clamp((e.clientX - rect.left) / rect.width, 0, 1)
      const ts = Math.round(this.axisStart + pct * this.axisSpan())
      this.hoverTs = ts
      this.showTooltip(pct, ts)
    }
  },

  onPointerUp(e) {
    if (!this.dragging || e.pointerId !== this.activePointer) return
    this.dragging = false
    this.cursor.classList.remove("dragging")
    this.hideTooltip()

    try {
      this.track.releasePointerCapture(e.pointerId)
    } catch (_) {}

    const pct = parseFloat(this.cursor.style.left) / 100
    const ts = Math.round(this.axisStart + pct * this.axisSpan())
    this.activePointer = null
    this.seekTo(ts)
  },

  onHoverEnd() {
    if (this.dragging) return
    this.hoverTs = null
    this.hideTooltip()
  },

  moveCursorToEvent(e) {
    const rect = this.track.getBoundingClientRect()
    const pct = clamp((e.clientX - rect.left) / rect.width, 0, 1)
    const ts = Math.round(this.axisStart + pct * this.axisSpan())
    this.cursor.style.left = `${pct * 100}%`
    this.fill.style.width = `${pct * 100}%`
    this.showTooltip(pct, ts)
  },

  // Snap to nearest segment boundary, clamp to playable window, dispatch
  // either a "go live" (cursor within LIVE_MARGIN of now) or a seek event.
  seekTo(rawTs) {
    if (!this.hasRecordings) return

    const snapped = Math.round(rawTs / SEGMENT_DURATION) * SEGMENT_DURATION
    const ts = clamp(snapped, this.oldest, this.newest)
    const now = this.serverNow()

    if (ts >= now - LIVE_MARGIN) {
      this.mode = "live"
      this.setCursorAt(now)
      this.renderLive()
      this.pushEvent("dvr:go_live", { camera_id: this.cameraId })
    } else {
      this.mode = "playback"
      this.setCursorAt(ts)
      this.renderLive()
      this.pushEvent("dvr:seek", { camera_id: this.cameraId, from: ts })
    }
  },

  // ── Helpers ──────────────────────────────────────────────────────────────

  axisSpan() {
    return Math.max(this.axisEnd - this.axisStart, 0)
  },

  serverNow() {
    return nowSec() + this.timeOffset
  },
}

function el(tag, cls) {
  const e = document.createElement(tag)
  if (cls) e.className = cls
  return e
}

function nowSec() {
  return Math.floor(Date.now() / 1000)
}

function clamp(x, lo, hi) {
  return Math.max(lo, Math.min(x, hi))
}

// Format a UTC unix timestamp using a fixed offset, locale-free 24-hour.
// We add the offset to the unix ts (i.e. fake the date as UTC of the
// shifted moment) then read components with getUTC* — so the rendered
// digits are the local wall clock, independent of the JS engine's idea
// of the user's tz. This guarantees identical output to the server's
// Elixir `fmt_ts_local`.
function formatLocal(unixSeconds, tzOffsetMinutes, withSeconds = false) {
  const ms = (unixSeconds + tzOffsetMinutes * 60) * 1000
  const d = new Date(ms)
  const hh = String(d.getUTCHours()).padStart(2, "0")
  const mm = String(d.getUTCMinutes()).padStart(2, "0")
  if (withSeconds) {
    const ss = String(d.getUTCSeconds()).padStart(2, "0")
    return `${hh}:${mm}:${ss}`
  }
  return `${hh}:${mm}`
}

export default TimelineScrubber
