const WebRTCPlayer = {
  mounted() {
    this.state = {
      retries: 0,
      stopped: false,
    }

    this.connect()
  },

  destroyed() {
    this.state.stopped = true
    if (this.pc) {
      this.pc.close()
    }
  },

  async connect() {
    if (this.state.stopped) return

    const cameraId = this.el.dataset.cameraId
    const viewerId = this.el.dataset.viewerId || `viewer-${Date.now()}`

    try {
      const offerResp = await fetch("/api/webrtc/offer", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ camera_id: cameraId, viewer_id: viewerId }),
      })

      if (!offerResp.ok) throw new Error("offer_failed")

      const { session_id, offer_sdp } = await offerResp.json()
      this.sessionId = session_id
      this.pc = new RTCPeerConnection()

      this.pc.onicecandidate = async (event) => {
        if (!event.candidate) return

        await fetch("/api/webrtc/ice-candidate", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            session_id: this.sessionId,
            role: "viewer",
            candidate: event.candidate.toJSON(),
          }),
        })
      }

      this.pc.onconnectionstatechange = () => {
        const state = this.pc?.connectionState
        if (state === "failed" || state === "disconnected") {
          this.scheduleReconnect()
        }
      }

      this.pc.ontrack = (event) => {
        if (this.el.srcObject !== event.streams[0]) {
          this.el.srcObject = event.streams[0]
        }
      }

      await this.pc.setRemoteDescription({ type: "offer", sdp: offer_sdp })
      const answer = await this.pc.createAnswer()
      await this.pc.setLocalDescription(answer)

      await fetch("/api/webrtc/answer", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          session_id: this.sessionId,
          answer_sdp: answer.sdp,
        }),
      })

      this.state.retries = 0
    } catch (_error) {
      this.scheduleReconnect()
    }
  },

  scheduleReconnect() {
    if (this.state.stopped) return
    if (this.pc) {
      this.pc.close()
      this.pc = null
    }

    const waitMs = Math.min(1000 * 2 ** this.state.retries, 15000)
    this.state.retries += 1
    setTimeout(() => this.connect(), waitMs)
  },
}

export default WebRTCPlayer
