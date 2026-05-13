/**
 * TimelineScrubber — NVR-style draggable DVR timeline below each camera.
 *
 * Renders an absolute-time axis (HH:MM:SS labels), a draggable cursor, a
 * hover tooltip, a LIVE badge, and motion markers. Always-visible — re-renders
 * every dvr:bounds tick. Bounds-checked: out-of-retention clicks clamp instead
 * of auto-jumping forward.
 *
 * DOM data attributes (read once at mount, then maintained via dvr:bounds):
 *   data-camera-id, data-oldest, data-newest, data-server-time
 *
 * Server events handled:
 *   dvr:bounds        %{server_time, oldest, newest}   — every ~5s, source of truth
 *   dvr:markers       %{markers: [{ts: ...}], append}  — motion event markers
 *   dvr:mode          %{mode: "live" | "playback"}     — when mode changes
 *   dvr:playback_pos  %{ts: ...}                       — playback cursor sync
 *   dvr:seek_rejected %{reason, oldest?, newest?}      — seek failed; reset cursor
 *
 * Server events pushed:
 *   dvr:seek         %{camera_id, from}  — seek to timestamp
 *   dvr:go_live      %{camera_id}        — return to live
 */

const SEGMENT_DURATION = 6  // seconds — for snap-to-segment
const LIVE_MARGIN = 5       // seconds — how close to "now" counts as live

const TimelineScrubber = {
  mounted() {
    this.cameraId = this.el.dataset.cameraId
    this.oldest = parseInt(this.el.dataset.oldest, 10) || 0
    this.newest = parseInt(this.el.dataset.newest, 10) || 0
    this.serverTime = parseInt(this.el.dataset.serverTime, 10) || nowSec()
    this.timeOffset = this.serverTime - nowSec()
    this.markers = []
    this.mode = "live"
    this.dragging = false
    this.hoverTs = null

    this.buildDOM()
    this.bindEvents()
    this.render()

    // Auto-advance the live cursor every second.
    this._tick = setInterval(() => this.tickAdvance(), 1000)

    this.handleEvent("dvr:bounds", ({ server_time, oldest, newest }) => {
      this.serverTime = server_time
      this.timeOffset = server_time - nowSec()
      this.oldest = oldest
      this.newest = newest
      this.render()
    })

    this.handleEvent("dvr:markers", ({ markers, append }) => {
      this.markers = append ? (this.markers || []).concat(markers || []) : (markers || [])
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
      // Snap cursor back to a safe spot — live edge — and exit playback.
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

    // Track is the click target. Layered children: out-of-bounds shading,
    // markers, fill, cursor, hover-tooltip.
    this.track = el("div", "tl-track")
    this.oobLeft = el("div", "tl-oob tl-oob-left")
    this.oobRight = el("div", "tl-oob tl-oob-right")
    this.fill = el("div", "tl-fill")
    this.cursor = el("div", "tl-cursor")
    this.tooltip = el("div", "tl-tooltip")
    this.tooltip.style.display = "none"

    this.track.append(this.oobLeft, this.oobRight, this.fill, this.cursor, this.tooltip)

    this.labels = el("div", "tl-labels")

    this.liveLabel = el("button", "tl-live-lbl")
    this.liveLabel.type = "button"
    this.liveLabel.textContent = "LIVE"

    this.el.append(this.track, this.labels, this.liveLabel)
  },

  bindEvents() {
    this.track.addEventListener("mousedown", (e) => this.startDrag(e))
    this.track.addEventListener("mousemove", (e) => this.onHover(e))
    this.track.addEventListener("mouseleave", () => this.onHoverEnd())
    document.addEventListener("mousemove", (e) => this.onDrag(e))
    document.addEventListener("mouseup", () => this.endDrag())

    this.track.addEventListener("touchstart", (e) => this.startDrag(e.touches[0]), { passive: true })
    document.addEventListener("touchmove", (e) => this.onDrag(e.touches[0]), { passive: true })
    document.addEventListener("touchend", () => this.endDrag())

    this.liveLabel.addEventListener("click", () => {
      this.mode = "live"
      this.setCursorAt(this.serverNow())
      this.renderLive()
      this.pushEvent("dvr:go_live", { camera_id: this.cameraId })
    })
  },

  // ── Render ───────────────────────────────────────────────────────────────

  render() {
    this.renderLabels()
    this.renderMarkers()
    this.renderOobRegions()
    if (this.mode === "live") this.setCursorAt(this.serverNow())
    this.renderLive()
  },

  renderLabels() {
    this.labels.innerHTML = ""
    if (this.windowSpan() <= 0) return

    // 5 evenly-spaced labels across the timeline.
    const count = 5
    for (let i = 0; i <= count; i++) {
      const ts = this.oldest + Math.round((i / count) * this.windowSpan())
      const lbl = el("span", "tl-time-lbl")
      lbl.textContent = formatClock(ts)
      lbl.style.left = `${(i / count) * 100}%`
      this.labels.appendChild(lbl)
    }
  },

  renderMarkers() {
    Array.from(this.track.querySelectorAll(".tl-marker")).forEach((m) => m.remove())
    const span = this.windowSpan()
    if (span <= 0) return

    this.markers.forEach(({ ts }) => {
      const pct = (ts - this.oldest) / span
      if (pct < 0 || pct > 1) return

      const m = el("div", "tl-marker")
      m.style.left = `${pct * 100}%`
      m.title = formatClock(ts)
      m.addEventListener("click", (e) => {
        e.stopPropagation()
        this.seekTo(ts)
      })
      this.track.appendChild(m)
    })
  },

  // The retention window IS the whole timeline span here, so no out-of-bounds
  // regions are shown in normal operation. Kept for the case where the visual
  // window is wider than the retention (future).
  renderOobRegions() {
    this.oobLeft.style.width = "0%"
    this.oobRight.style.width = "0%"
  },

  renderLive() {
    const live = this.mode === "live"
    this.liveLabel.classList.toggle("active", live)
    this.el.classList.toggle("at-live", live)
  },

  // ── Cursor / tooltip ─────────────────────────────────────────────────────

  setCursorAt(ts) {
    const span = this.windowSpan()
    if (span <= 0) return
    const pct = Math.max(0, Math.min((ts - this.oldest) / span, 1))
    this.cursor.style.left = `${pct * 100}%`
    this.fill.style.width = `${pct * 100}%`
  },

  showTooltip(pct, ts) {
    this.tooltip.style.left = `${pct * 100}%`
    this.tooltip.textContent = formatClock(ts, true)
    this.tooltip.style.display = "block"
  },

  hideTooltip() {
    this.tooltip.style.display = "none"
  },

  tickAdvance() {
    if (this.mode !== "live") return
    if (this.windowSpan() <= 0) return
    this.setCursorAt(this.serverNow())
  },

  // ── Interaction ──────────────────────────────────────────────────────────

  onHover(e) {
    if (this.dragging) return
    const rect = this.track.getBoundingClientRect()
    const pct = clamp((e.clientX - rect.left) / rect.width, 0, 1)
    const ts = Math.round(this.oldest + pct * this.windowSpan())
    this.hoverTs = ts
    this.showTooltip(pct, ts)
  },

  onHoverEnd() {
    if (this.dragging) return
    this.hoverTs = null
    this.hideTooltip()
  },

  startDrag(e) {
    if (this.windowSpan() <= 0) return
    this.dragging = true
    this.cursor.classList.add("dragging")
    this.onDrag(e)
  },

  onDrag(e) {
    if (!this.dragging) return
    const rect = this.track.getBoundingClientRect()
    const pct = clamp((e.clientX - rect.left) / rect.width, 0, 1)
    const ts = Math.round(this.oldest + pct * this.windowSpan())
    this.cursor.style.left = `${pct * 100}%`
    this.fill.style.width = `${pct * 100}%`
    this.showTooltip(pct, ts)
  },

  endDrag() {
    if (!this.dragging) return
    this.dragging = false
    this.cursor.classList.remove("dragging")
    this.hideTooltip()

    const pct = parseFloat(this.cursor.style.left) / 100
    const ts = Math.round(this.oldest + pct * this.windowSpan())
    this.seekTo(ts)
  },

  // Snap to nearest 6s segment boundary, clamp to retention, then either go
  // live (if within LIVE_MARGIN of now) or push a seek.
  seekTo(rawTs) {
    if (this.windowSpan() <= 0) return

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

  windowSpan() {
    return Math.max(this.newest - this.oldest, 0)
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

// Default: HH:MM. With `withSeconds = true`: HH:MM:SS. Locale-aware.
function formatClock(ts, withSeconds = false) {
  const d = new Date(ts * 1000)
  return withSeconds
    ? d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })
    : d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
}

export default TimelineScrubber
