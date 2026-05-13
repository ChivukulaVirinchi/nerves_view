import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import Hls from "../vendor/hls.min.js"
import CameraPlayer from "./hooks/camera_player"
import ClipPlayer from "./hooks/clip_player"
import TimelineScrubber from "./hooks/timeline_scrubber"

// Make Hls available globally for the CameraPlayer hook
window.Hls = Hls

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: {
    CameraPlayer,
    ClipPlayer,
    TimelineScrubber,
  },
})

liveSocket.connect()

window.liveSocket = liveSocket
