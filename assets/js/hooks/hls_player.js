const HLSPlayer = {
  mounted() {
    const src = this.el.dataset.src
    if (!src) return

    if (window.Hls && window.Hls.isSupported()) {
      this.hls = new window.Hls()
      this.hls.loadSource(src)
      this.hls.attachMedia(this.el)
    } else {
      this.el.src = src
    }
  },
  destroyed() {
    if (this.hls) this.hls.destroy()
  },
}

export default HLSPlayer
