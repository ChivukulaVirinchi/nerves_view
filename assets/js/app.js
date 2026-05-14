import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import Hls from "../vendor/hls.min.js"
import CameraPlayer from "./hooks/camera_player"
import CameraZoom from "./hooks/camera_zoom"
import ClipPlayer from "./hooks/clip_player"
import TimelineScrubber from "./hooks/timeline_scrubber"

window.Hls = Hls

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: {
    CameraPlayer,
    CameraZoom,
    ClipPlayer,
    TimelineScrubber,
  },
})

liveSocket.connect()

window.liveSocket = liveSocket
