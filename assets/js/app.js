import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import WebRTCPlayer from "./hooks/webrtc_player"
import HLSPlayer from "./hooks/hls_player"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: {
    WebRTCPlayer,
    HLSPlayer,
  },
})

liveSocket.connect()

window.liveSocket = liveSocket
