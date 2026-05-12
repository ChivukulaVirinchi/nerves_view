/**
 * TimelineScrubber — draggable DVR timeline below each camera.
 *
 * Reads data-oldest, data-newest, data-server-time from the element.
 * Builds a visual track with a draggable cursor.
 * On release: pushes "dvr:seek" to the server with the target timestamp.
 * Clicking "LIVE" pushes "dvr:go_live".
 *
 * Receives "dvr:markers" for motion event markers.
 * Receives "dvr:playback_pos" to move the cursor during playback.
 */
const TimelineScrubber = {
  mounted() {
    this.oldest = parseInt(this.el.dataset.oldest) || 0
    this.newest = parseInt(this.el.dataset.newest) || 0
    this.serverTime = parseInt(this.el.dataset.serverTime) || Math.floor(Date.now() / 1000)
    this.timeOffset = this.serverTime - Math.floor(Date.now() / 1000)
    this.markers = []
    this.dragging = false
    this.isLive = true

    this.buildDOM()
    this.bindEvents()

    this.handleEvent("dvr:markers", ({ markers }) => {
      this.markers = markers || []
      this.renderMarkers()
    })

    this.handleEvent("dvr:playback_pos", ({ ts }) => {
      if (!this.dragging && !this.isLive) {
        this.setCursorAt(ts)
      }
    })
  },

  updated() {
    const o = parseInt(this.el.dataset.oldest) || 0
    const n = parseInt(this.el.dataset.newest) || 0
    const st = parseInt(this.el.dataset.serverTime) || 0

    if (o !== this.oldest || n !== this.newest) {
      this.oldest = o
      this.newest = n
      this.renderLabels()
      this.renderMarkers()
    }

    if (st) {
      this.serverTime = st
      this.timeOffset = st - Math.floor(Date.now() / 1000)
    }
  },

  buildDOM() {
    this.el.innerHTML = ""

    this.track = el("div", "tl-track")
    this.fill = el("div", "tl-fill")
    this.cursor = el("div", "tl-cursor")
    this.tooltip = el("div", "tl-tooltip")
    this.tooltip.style.display = "none"
    this.labels = el("div", "tl-labels")
    this.liveLabel = el("span", "tl-live-lbl")
    this.liveLabel.textContent = "LIVE"

    this.track.append(this.fill, this.cursor, this.tooltip)
    this.labels.append(this.liveLabel)
    this.el.append(this.track, this.labels)

    this.renderLabels()

    // Start cursor at live edge
    this.cursor.style.left = "100%"
    this.fill.style.width = "100%"
  },

  bindEvents() {
    // Mouse
    this.track.addEventListener("mousedown", (e) => this.startDrag(e))
    document.addEventListener("mousemove", (e) => this.onDrag(e))
    document.addEventListener("mouseup", () => this.endDrag())

    // Touch
    this.track.addEventListener("touchstart", (e) => this.startDrag(e.touches[0]), { passive: true })
    document.addEventListener("touchmove", (e) => this.onDrag(e.touches[0]), { passive: true })
    document.addEventListener("touchend", () => this.endDrag())

    // LIVE button
    this.liveLabel.addEventListener("click", () => {
      this.isLive = true
      this.cursor.style.left = "100%"
      this.fill.style.width = "100%"
      this.pushEvent("dvr:go_live", { camera_id: this.el.dataset.cameraId })
    })
  },

  startDrag(e) {
    this.dragging = true
    this.cursor.classList.add("dragging")
    this.tooltip.style.display = "block"
    this.onDrag(e)
  },

  onDrag(e) {
    if (!this.dragging) return
    const rect = this.track.getBoundingClientRect()
    const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width))
    const pct = x / rect.width
    const ts = Math.round(this.oldest + pct * this.range())

    this.cursor.style.left = `${pct * 100}%`
    this.fill.style.width = `${pct * 100}%`
    this.tooltip.style.left = `${pct * 100}%`
    this.tooltip.textContent = this.formatTime(ts)
  },

  endDrag() {
    if (!this.dragging) return
    this.dragging = false
    this.cursor.classList.remove("dragging")
    this.tooltip.style.display = "none"

    const rect = this.track.getBoundingClientRect()
    const pct = parseFloat(this.cursor.style.left) / 100
    const ts = Math.round(this.oldest + pct * this.range())
    const now = this.serverNow()

    // If dragged to within 10 seconds of live edge, go live
    if (ts >= now - 10) {
      this.isLive = true
      this.cursor.style.left = "100%"
      this.fill.style.width = "100%"
      this.pushEvent("dvr:go_live", { camera_id: this.el.dataset.cameraId })
    } else {
      this.isLive = false
      this.pushEvent("dvr:seek", { camera_id: this.el.dataset.cameraId, from: ts })
    }
  },

  setCursorAt(ts) {
    if (this.range() <= 0) return
    const pct = Math.max(0, Math.min((ts - this.oldest) / this.range(), 1))
    this.cursor.style.left = `${pct * 100}%`
    this.fill.style.width = `${pct * 100}%`
  },

  renderLabels() {
    // Clear all labels except the LIVE label
    Array.from(this.labels.children).forEach((c) => {
      if (c !== this.liveLabel) c.remove()
    })

    const range = this.range()
    if (range <= 0) return

    // Show 4-6 evenly-spaced time labels
    const count = Math.min(6, Math.max(2, Math.floor(range / 3600)))
    const step = range / count

    for (let i = 0; i <= count; i++) {
      const ts = this.oldest + Math.round(i * step)
      const lbl = el("span", "tl-time-lbl")
      lbl.textContent = this.formatTime(ts)
      this.labels.insertBefore(lbl, this.liveLabel)
    }
  },

  renderMarkers() {
    // Remove existing markers
    this.track.querySelectorAll(".tl-marker").forEach((m) => m.remove())

    const range = this.range()
    if (range <= 0) return

    this.markers.forEach(({ ts }) => {
      const pct = (ts - this.oldest) / range
      if (pct >= 0 && pct <= 1) {
        const m = el("div", "tl-marker")
        m.style.left = `${pct * 100}%`
        m.title = this.formatTime(ts)
        m.addEventListener("click", (e) => {
          e.stopPropagation()
          this.isLive = false
          this.setCursorAt(ts)
          this.pushEvent("dvr:seek", { camera_id: this.el.dataset.cameraId, from: ts })
        })
        this.track.appendChild(m)
      }
    })
  },

  // ── Helpers ──

  range() {
    return Math.max(this.newest - this.oldest, 1)
  },

  serverNow() {
    return Math.floor(Date.now() / 1000) + this.timeOffset
  },

  formatTime(ts) {
    const d = new Date(ts * 1000)
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  },
}

function el(tag, cls) {
  const e = document.createElement(tag)
  if (cls) e.className = cls
  return e
}

export default TimelineScrubber
