/**
 * CameraZoom — pinch / wheel / drag pan + fullscreen on the camera viewport.
 *
 * All client-side: the video stream is unchanged, we just apply a CSS
 * transform to the <video> element. Zero CPU cost on the Pi.
 *
 * Mounted on the viewport wrapper. Looks for a child <video> with class
 * `cam-vid`, plus the button stack:
 *   [data-zoom-in], [data-zoom-out], [data-zoom-reset],
 *   [data-fullscreen], [data-zoom-badge]
 */
const MIN_ZOOM = 1
const MAX_ZOOM = 5
const ZOOM_STEP = 0.25
const PAN_LIMIT = 1 // factor of (zoom-1) applied to half-width/height

const CameraZoom = {
  mounted() {
    this.video = this.el.querySelector(".cam-vid")
    if (!this.video) return

    this.zoom = 1
    this.panX = 0
    this.panY = 0

    this.badge = this.el.querySelector("[data-zoom-badge]")
    this.btnIn = this.el.querySelector("[data-zoom-in]")
    this.btnOut = this.el.querySelector("[data-zoom-out]")
    this.btnReset = this.el.querySelector("[data-zoom-reset]")
    this.btnFullscreen = this.el.querySelector("[data-fullscreen]")

    this.bindButtons()
    this.bindWheel()
    this.bindPinch()
    this.bindDrag()

    this.applyTransform()
  },

  destroyed() {
    // CSS transform is on the <video> element which gets cleaned up with
    // the LV; no explicit teardown needed. Active gestures are bound on
    // `this.el` and `document`, which get unbound when LV unmounts.
  },

  bindButtons() {
    this.btnIn?.addEventListener("click", () => this.setZoom(this.zoom + ZOOM_STEP))
    this.btnOut?.addEventListener("click", () => this.setZoom(this.zoom - ZOOM_STEP))
    this.btnReset?.addEventListener("click", () => this.reset())
    this.btnFullscreen?.addEventListener("click", () => this.toggleFullscreen())
  },

  bindWheel() {
    this.el.addEventListener(
      "wheel",
      (e) => {
        // Only intercept when the cursor is over the video itself, not over
        // a control button (so the button's own scroll behaviour isn't
        // affected). Wheel up = zoom in, wheel down = zoom out.
        if (e.target.closest(".cam-controls")) return
        e.preventDefault()
        const delta = -Math.sign(e.deltaY) * ZOOM_STEP
        this.setZoom(this.zoom + delta)
      },
      { passive: false },
    )
  },

  // Two-finger pinch on touchscreens. We track the starting distance between
  // the two touches; ratio of current/start distance scales the starting zoom.
  bindPinch() {
    let startDist = 0
    let startZoom = 1

    const dist = (t1, t2) => {
      const dx = t1.clientX - t2.clientX
      const dy = t1.clientY - t2.clientY
      return Math.hypot(dx, dy)
    }

    this.el.addEventListener(
      "touchstart",
      (e) => {
        if (e.touches.length === 2) {
          startDist = dist(e.touches[0], e.touches[1])
          startZoom = this.zoom
        }
      },
      { passive: true },
    )

    this.el.addEventListener(
      "touchmove",
      (e) => {
        if (e.touches.length === 2 && startDist > 0) {
          const d = dist(e.touches[0], e.touches[1])
          this.setZoom(startZoom * (d / startDist))
          e.preventDefault()
        }
      },
      { passive: false },
    )

    this.el.addEventListener("touchend", () => {
      startDist = 0
    })
  },

  // Click + drag (or single-finger touch + drag) to pan, but only when zoomed in.
  bindDrag() {
    let active = false
    let startX = 0
    let startY = 0
    let basePanX = 0
    let basePanY = 0

    const start = (clientX, clientY) => {
      if (this.zoom <= MIN_ZOOM) return
      active = true
      startX = clientX
      startY = clientY
      basePanX = this.panX
      basePanY = this.panY
      this.video.style.cursor = "grabbing"
    }

    const move = (clientX, clientY) => {
      if (!active) return
      this.panX = basePanX + (clientX - startX)
      this.panY = basePanY + (clientY - startY)
      this.clampPan()
      this.applyTransform()
    }

    const end = () => {
      active = false
      this.video.style.cursor = ""
    }

    this.video.addEventListener("mousedown", (e) => {
      if (e.button !== 0) return
      start(e.clientX, e.clientY)
    })
    document.addEventListener("mousemove", (e) => move(e.clientX, e.clientY))
    document.addEventListener("mouseup", end)

    this.video.addEventListener(
      "touchstart",
      (e) => {
        if (e.touches.length === 1) start(e.touches[0].clientX, e.touches[0].clientY)
      },
      { passive: true },
    )
    this.el.addEventListener(
      "touchmove",
      (e) => {
        if (e.touches.length === 1 && active) {
          move(e.touches[0].clientX, e.touches[0].clientY)
        }
      },
      { passive: true },
    )
    this.el.addEventListener("touchend", end)
  },

  setZoom(z) {
    const next = clamp(z, MIN_ZOOM, MAX_ZOOM)
    if (next === this.zoom) return
    this.zoom = next
    // When zooming back to 1×, snap pan to centre.
    if (next === MIN_ZOOM) {
      this.panX = 0
      this.panY = 0
    } else {
      this.clampPan()
    }
    this.applyTransform()
  },

  reset() {
    this.zoom = 1
    this.panX = 0
    this.panY = 0
    this.applyTransform()
  },

  clampPan() {
    const rect = this.el.getBoundingClientRect()
    const maxX = ((this.zoom - 1) / 2) * rect.width * PAN_LIMIT
    const maxY = ((this.zoom - 1) / 2) * rect.height * PAN_LIMIT
    this.panX = clamp(this.panX, -maxX, maxX)
    this.panY = clamp(this.panY, -maxY, maxY)
  },

  applyTransform() {
    this.video.style.transform = `translate(${this.panX}px, ${this.panY}px) scale(${this.zoom})`
    this.video.style.transformOrigin = "center center"
    if (this.badge) {
      this.badge.textContent = `${this.zoom.toFixed(1)}×`
      this.badge.style.display = this.zoom > 1.01 ? "block" : "none"
    }
    this.el.classList.toggle("zoomed", this.zoom > 1.01)
  },

  toggleFullscreen() {
    if (document.fullscreenElement) {
      document.exitFullscreen().catch(() => {})
    } else {
      // Some iOS Safari versions only fullscreen <video>, not arbitrary divs.
      // Try the wrapper first; fall back to the video element.
      const req =
        this.el.requestFullscreen || this.el.webkitRequestFullscreen || this.el.msRequestFullscreen
      if (req) {
        req.call(this.el).catch(() => this.fullscreenVideoFallback())
      } else {
        this.fullscreenVideoFallback()
      }
    }
  },

  fullscreenVideoFallback() {
    const req =
      this.video.requestFullscreen ||
      this.video.webkitEnterFullscreen ||
      this.video.webkitRequestFullscreen
    req?.call(this.video)
  },
}

function clamp(x, lo, hi) {
  return Math.max(lo, Math.min(x, hi))
}

export default CameraZoom
