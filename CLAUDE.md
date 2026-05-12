# CLAUDE.md

## Build Rules

- Always build firmware in production mode for the target device:
  ```
  MIX_ENV=prod MIX_TARGET=rpi0_2 mix firmware
  ```
- Upload with: `MIX_ENV=prod MIX_TARGET=rpi0_2 mix upload nervesview.local`
- For host development: `MIX_ENV=dev mix phx.server`

## Architecture

- Camera: libcamera-vid -> H.264 NAL extraction -> FramePublisher -> StreamBus
- Live streaming: StreamBus -> PeerConnection (RTP packetization) -> ExWebRTC -> Browser
- Recording: StreamBus -> SegmentWriter -> MPEG-TS -> HLS
- WebRTC signaling: HTTP API (`/api/webrtc/*`), not LiveView events
- Target: Raspberry Pi Zero 2 W (`rpi0_2`)
