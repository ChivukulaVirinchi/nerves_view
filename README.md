# NervesView

Self-hosted home surveillance running on a Raspberry Pi. Phoenix LiveView UI,
H.264 over WebRTC for live view, MPEG-TS + HLS for recording and playback,
SQLite for auth. All in Elixir + a Nerves firmware image.

This is a personal project I open-sourced. It works for me, it might not work
for you out of the box — expect rough edges, and please file issues when you
hit them.

## What you need

- **Raspberry Pi Zero 2 W** (the only board I've tested on).
- **Raspberry Pi Camera Module v2** (IMX219). v1 / v3 / HQ may also work — auto-detected via `camera_auto_detect=1`.
- **22-pin 0.5 mm-pitch CSI ribbon cable** designed for the Pi Zero — the standard 15-pin Pi 4/5 cable will not fit.
- A **high-endurance microSD card** (≥32 GB; SanDisk Max Endurance / Samsung Pro Endurance recommended for 24/7 recording).
- Linux host with Elixir 1.19 + OTP 28 (`mise` / `asdf` configured) and the [Nerves toolchain](https://hexdocs.pm/nerves/installation.html).

## Build & flash

```bash
git clone https://github.com/ChivukulaVirinchi/nerves_view
cd nerves_view
mix deps.get
MIX_ENV=prod MIX_TARGET=rpi0_2 mix firmware
MIX_ENV=prod MIX_TARGET=rpi0_2 mix burn   # or `mix upload nervesview.local` after first boot
```

## First boot

1. Pi boots, gets a DHCP address, and announces itself as `nervesview.local`.
2. Open `http://nervesview.local:4000` in a browser on the same network.
3. The first user you register becomes the admin.
4. The default camera (`cam-local`) starts streaming immediately.

## Putting the Pi on home Wi-Fi

SSH in (`ssh nervesview.local`) and run from IEx:

```elixir
VintageNetWiFi.quick_configure("YourSSID", "YourPassword")
```

Settings persist to `/data/vintage_net.config` and survive reboots.

## Where things live on the device

| Concern | Path |
|---|---|
| App rootfs (read-only) | `/` |
| Recordings (persistent) | `/data/nerves_view/recordings/<camera_id>/seg-*.ts` |
| Accounts DB (persistent) | `/data/nerves_view/nerves_view.db` |
| Wi-Fi config | `/data/vintage_net.config` |

## Development (host)

```bash
mix test              # full suite
mix phx.server        # Phoenix on http://localhost:4000 (no camera; synthetic source)
```

## Architecture in two paragraphs

`libcamera-vid` is launched as a Port and emits an H.264 bitstream. The producer
splits it into NALs, groups them into access units, and publishes each AU to a
`StreamBus`. Two subscribers consume it: the **per-viewer `PeerConnection`
GenServer** packetizes the AU into RTP (STAP-A for SPS/PPS, FU-A for the slice,
marker bit only on the last packet) and forwards it through `ex_webrtc` to the
browser. The **`SegmentWriter`** muxes the NALs into MPEG-TS and writes 6-second
segments to disk; `PlaylistManager` emits an HLS m3u8 over the segments for
DVR playback in the same UI.

DTLS uses a patched `ex_dtls` ([fork](https://github.com/ChivukulaVirinchi/ex_dtls/tree/fix/openssl3-dgram-mem-bio))
that accepts any X.509 cert during the handshake — necessary because Pi RTCs
typically lag behind the browser's freshly-minted cert's `notBefore` at boot.
The WebRTC trust model relies on the SDP fingerprint check that `ex_webrtc`
already does post-handshake.

## Caveats

- The SD card is the bottleneck for long-term reliability. Use a high-endurance card.
- HTTP only by default. For external access, run Tailscale on the Pi — don't port-forward.
- One Pi Zero 2 W can comfortably serve ~2 concurrent WebRTC viewers per camera. Beyond that, SRTP encryption becomes the bottleneck.
- Audio is not captured.
- Motion detection is wired conceptually (alerts + scrubber markers) but the producer side is not yet hooked up to `libcamera-vid`'s `motion_detect` post-processor.

## License

MIT. See `LICENSE`.
