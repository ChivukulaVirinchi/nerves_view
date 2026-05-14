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
    this.axisStart =
      parseInt(this.el.dataset.axisStart, 10) || this.oldest || nowSec() - 24 * 3600
    this.axisEnd = parseInt(this.el.dataset.axisEnd, 10) || this.newest || nowSec()
    this.hasRecordings = this.el.dataset.hasRecordings === "1"
    this.dayLabel = this.el.dataset.dayLabel || null
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

    this.handleEvent(
      "dvr:bounds",
      ({ server_time, oldest, newest, axis_start, axis_end, has_recordings, day_label }) => {
        this.serverTime = server_time
        this.timeOffset = server_time - nowSec()
        this.oldest = oldest
        this.newest = newest
        this.axisStart = axis_start ?? oldest
        this.axisEnd = axis_end ?? newest
        this.hasRecordings = !!has_recordings
        this.dayLabel = day_label || null
        this.render()
      }
    )

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
    // markers, fill, cursor, hover-tooltip, empty-state overlay.
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
    this.renderEmpty()
    this.renderLabels()
    this.renderMarkers()
    this.renderOobRegions()
    if (this.mode === "live" && this.hasRecordings) this.setCursorAt(this.serverNow())
    this.renderLive()
  },

  renderEmpty() {
    if (this.hasRecordings) {
      this.emptyOverlay.style.display = "none"
      this.el.classList.remove("empty")
      return
    }
    this.emptyOverlay.textContent = this.dayLabel
      ? `No recordings on ${this.dayLabel}`
      : "No recordings yet"
    this.emptyOverlay.style.display = "flex"
    this.el.classList.add("empty")
    // Hide cursor and fill when empty — nothing to point at.
    this.cursor.style.left = "-100%"
    this.fill.style.width = "0%"
  },

  renderLabels() {
    this.labels.innerHTML = ""
    if (this.axisSpan() <= 0) return

    // 5 evenly-spaced labels across the axis (which is the day window or the
    // retention extent — not the playable window). Labels always reflect
    // real wall-clock time, even when no recordings exist for the day.
    const count = 5
    for (let i = 0; i <= count; i++) {
      const ts = this.axisStart + Math.round((i / count) * this.axisSpan())
      const lbl = el("span", "tl-time-lbl")
      lbl.textContent = formatClock(ts)
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
      m.title = formatClock(ts)
      m.addEventListener("click", (e) => {
        e.stopPropagation()
        this.seekTo(ts)
      })
      this.track.appendChild(m)
    })
  },

  // Shade the parts of the visible axis that are outside the playable window
  // (oldest..newest). Lets users see at a glance which chunk of the day has
  // recordings versus gaps at the start/end.
  renderOobRegions() {
    if (!this.hasRecordings) {
      // Whole axis is out-of-bounds in the empty state — overlay covers it.
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
    this.tooltip.textContent = formatClock(ts, true)
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

  // ── Interaction ──────────────────────────────────────────────────────────

  onHover(e) {
    if (this.dragging) return
    if (this.axisSpan() <= 0) return
    const rect = this.track.getBoundingClientRect()
    const pct = clamp((e.clientX - rect.left) / rect.width, 0, 1)
    const ts = Math.round(this.axisStart + pct * this.axisSpan())
    this.hoverTs = ts
    this.showTooltip(pct, ts)
  },

  onHoverEnd() {
    if (this.dragging) return
    this.hoverTs = null
    this.hideTooltip()
  },

  startDrag(e) {
    if (!this.hasRecordings) return
    if (this.axisSpan() <= 0) return
    this.dragging = true
    this.cursor.classList.add("dragging")
    this.onDrag(e)
  },

  onDrag(e) {
    if (!this.dragging) return
    const rect = this.track.getBoundingClientRect()
    const pct = clamp((e.clientX - rect.left) / rect.width, 0, 1)
    const ts = Math.round(this.axisStart + pct * this.axisSpan())
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
    const ts = Math.round(this.axisStart + pct * this.axisSpan())
    this.seekTo(ts)
  },

  // Snap to nearest 6s segment boundary, clamp to playable window (oldest..
  // newest, NOT the visual axis), then either go live (within LIVE_MARGIN of
  // now) or push a seek.
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

// Default: HH:MM. With `withSeconds = true`: HH:MM:SS. Locale-aware.
function formatClock(ts, withSeconds = false) {
  const d = new Date(ts * 1000)
  return withSeconds
    ? d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })
    : d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
}

export default TimelineScrubber
