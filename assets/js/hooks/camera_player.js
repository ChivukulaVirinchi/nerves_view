/**
 * CameraPlayer — dual-mode video player hook.
 *
 * Live mode:  WebRTC via HTTP signaling endpoints
 * Playback:   HLS via hls.js (or native on Safari)
 */
const CameraPlayer = {
  mounted() {
    this.mode = "live"
    this.webrtc = {
      pc: null,
      sessionId: null,
      retries: 0,
      stopped: false,
      pendingIce: [],
    }
    this.hls = null

    // DVR mode switches
    this.handleEvent("dvr:play", ({ url, start_offset }) => this.switchToHLS(url, start_offset))
    this.handleEvent("dvr:live", () => this.switchToLive())

    // Start live via WebRTC (low latency)
    this.startWebRTC()
  },

  destroyed() {
    this.webrtc.stopped = true
    this.teardownWebRTC()
    this.teardownHLS()
  },

  // ── WebRTC (live) via API signaling ──

  async startWebRTC() {
    if (this.webrtc.stopped) return

    try {
      this.teardownWebRTC()
      this.webrtc.pendingIce = []

      this.webrtc.pc = new RTCPeerConnection({
        iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
      })

      // We only receive H264 video
      const transceiver = this.webrtc.pc.addTransceiver("video", { direction: "recvonly" })

      // Limit to the single H264 profile the Pi supports (42e01f, packetization-mode=1).
      // This keeps the SDP tiny so the Pi Zero 2 W can parse it quickly.
      if (transceiver.setCodecPreferences) {
        const codecs = RTCRtpReceiver.getCapabilities("video")?.codecs || []
        const h264 = codecs.filter(
          (c) =>
            c.mimeType === "video/H264" &&
            c.sdpFmtpLine?.includes("profile-level-id=42e01f") &&
            c.sdpFmtpLine?.includes("packetization-mode=1"),
        )
        if (h264.length > 0) {
          transceiver.setCodecPreferences(h264)
        }
      }

      this.webrtc.pc.onicecandidate = async (e) => {
        if (!e.candidate) return

        const candidate = e.candidate.toJSON()

        try {
          if (!this.webrtc.sessionId) {
            this.webrtc.pendingIce.push(candidate)
            return
          }

          await this.postIceCandidate(candidate)
        } catch (err) {
          console.error("[CameraPlayer] ICE candidate post failed:", err)
        }
      }

      this.webrtc.pc.onconnectionstatechange = () => {
        const s = this.webrtc.pc?.connectionState
        if (s === "failed" || s === "disconnected") {
          this.scheduleReconnect()
        }
      }

      this.webrtc.pc.ontrack = (e) => {
        const stream = e.streams[0] || new MediaStream([e.track])
        if (this.el.srcObject !== stream) {
          this.el.srcObject = stream
        }
      }

      const cameraId = this.el.dataset.cameraId
      const viewerId = this.el.dataset.viewerId || `viewer-${Date.now()}`
      const token = this.el.dataset.streamToken

      // Browser creates offer (browser = controlling agent, server = controlled)
      const offer = await this.webrtc.pc.createOffer()
      await this.webrtc.pc.setLocalDescription(offer)

      // Send browser's offer, get server's answer
      const res = await fetch("/api/webrtc/offer", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          camera_id: cameraId,
          viewer_id: viewerId,
          token,
          offer_sdp: offer.sdp,
        }),
      })

      if (!res.ok) throw new Error("offer_failed")

      const { session_id, answer_sdp } = await res.json()
      this.webrtc.sessionId = session_id

      await this.webrtc.pc.setRemoteDescription({ type: "answer", sdp: answer_sdp })

      // Send any ICE candidates that were queued before we had a session_id
      if (this.webrtc.pendingIce.length > 0) {
        const pending = this.webrtc.pendingIce.slice()
        this.webrtc.pendingIce = []

        for (const candidate of pending) {
          await this.postIceCandidate(candidate)
        }
      }

      this.webrtc.retries = 0
    } catch (e) {
      console.error("[CameraPlayer] WebRTC setup failed:", e)
      this.scheduleReconnect()
    }
  },

  async postIceCandidate(candidate) {
    if (!this.webrtc.sessionId) return

    const res = await fetch("/api/webrtc/ice-candidate", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        session_id: this.webrtc.sessionId,
        role: "viewer",
        candidate,
      }),
    })

    if (!res.ok) {
      throw new Error("ice_candidate_failed")
    }
  },

  scheduleReconnect() {
    if (this.webrtc.stopped || this.mode !== "live") return
    this.teardownWebRTC()
    const wait = Math.min(1000 * 2 ** this.webrtc.retries, 15000)
    this.webrtc.retries += 1
    setTimeout(() => this.startWebRTC(), wait)
  },

  teardownWebRTC() {
    const oldSessionId = this.webrtc.sessionId

    if (oldSessionId) {
      this.closeSession(oldSessionId)
    }

    if (this.webrtc.pc) {
      this.webrtc.pc.close()
      this.webrtc.pc = null
    }

    this.webrtc.sessionId = null
    this.webrtc.pendingIce = []
  },

  async closeSession(sessionId) {
    try {
      await fetch("/api/webrtc/close", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ session_id: sessionId }),
      })
    } catch (_) {
      // Best-effort cleanup
    }
  },

  // ── HLS (playback) ──

  switchToHLS(url, startOffset = 0) {
    this.mode = "playback"
    this.teardownWebRTC()
    this.el.srcObject = null

    if (window.Hls && window.Hls.isSupported()) {
      this.hls = new window.Hls({ maxBufferLength: 10, maxMaxBufferLength: 30 })
      this.hls.loadSource(url)
      this.hls.attachMedia(this.el)
      this.hls.on(window.Hls.Events.MANIFEST_PARSED, () => {
        this.el.play().catch(() => {})
        if (startOffset > 0) {
          this.el.currentTime = startOffset
        }
      })
    } else if (this.el.canPlayType("application/vnd.apple.mpegurl")) {
      this.el.src = url
      this.el.play().catch(() => {})
      if (startOffset > 0) {
        this.el.currentTime = startOffset
      }
    }

    this.el.ontimeupdate = () => {
      if (this.mode === "playback") {
        this.pushEvent("dvr:time_update", {
          camera_id: this.el.dataset.cameraId,
          current_time: this.el.currentTime,
        })
      }
    }
  },

  startLiveHLS() {
    const cameraId = this.el.dataset.cameraId
    const recordingsPath = `/cameras/${cameraId}/live.m3u8`

    this.mode = "live"
    this.teardownWebRTC()
    this.el.srcObject = null

    if (window.Hls && window.Hls.isSupported()) {
      this.hls = new window.Hls({
        maxBufferLength: 4,
        maxMaxBufferLength: 8,
        liveSyncDurationCount: 1, // stay close to live edge
        liveMaxLatencyDurationCount: 3,
      })
      this.hls.loadSource(recordingsPath)
      this.hls.attachMedia(this.el)
      this.hls.on(window.Hls.Events.MANIFEST_PARSED, () => {
        this.el.play().catch(() => {})
      })
    } else if (this.el.canPlayType("application/vnd.apple.mpegurl")) {
      this.el.src = recordingsPath
      this.el.play().catch(() => {})
    }
  },

  switchToLive() {
    this.mode = "live"
    this.teardownHLS()
    this.el.ontimeupdate = null
    this.webrtc.stopped = false
    this.webrtc.retries = 0
    this.startWebRTC()
  },

  teardownHLS() {
    if (this.hls) {
      this.hls.destroy()
      this.hls = null
    }
    this.el.removeAttribute("src")
    this.el.srcObject = null
  },
}

export default CameraPlayer
