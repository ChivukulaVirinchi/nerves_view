/**
 * ClipPlayer — minimal HLS player for a single recorded clip.
 *
 * Reads `data-src` on the <video> element (the m3u8 URL) and plays it via
 * hls.js (with native fallback for Safari). Used by ClipPlayerLive.
 */
const ClipPlayer = {
  mounted() {
    const url = this.el.dataset.src
    if (!url) return

    if (window.Hls && window.Hls.isSupported()) {
      this.hls = new window.Hls({ maxBufferLength: 10, maxMaxBufferLength: 30 })
      this.hls.loadSource(url)
      this.hls.attachMedia(this.el)
      this.hls.on(window.Hls.Events.MANIFEST_PARSED, () => {
        this.el.play().catch(() => {})
      })
      this.hls.on(window.Hls.Events.ERROR, (_evt, data) => {
        if (data.fatal) {
          console.warn("ClipPlayer HLS error:", data)
        }
      })
    } else if (this.el.canPlayType("application/vnd.apple.mpegurl")) {
      this.el.src = url
      this.el.play().catch(() => {})
    }
  },

  destroyed() {
    if (this.hls) {
      this.hls.destroy()
      this.hls = null
    }
  },
}

export default ClipPlayer
