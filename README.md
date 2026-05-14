# NervesView

Local NVR for Nerves devices. It captures camera input on the device, streams live video over WebRTC, and writes HLS/DVR segments for playback in the Phoenix LiveView UI.

Working name note: if you want a product name with a more distinct feel than `NervesView`, `Drishti` is the one I would pick. It is short, readable, and means sight/vision.

## What it does

- Live view over WebRTC
- Timeline playback over HLS
- On-device recording to `.ts` segments
- User auth and role-based access
- Camera sources for `libcamera`

## Build

```bash
git clone https://github.com/ChivukulaVirinchi/nerves_view
cd nerves_view
mix deps.get
MIX_ENV=prod MIX_TARGET=rpi0_2 mix firmware
MIX_ENV=prod MIX_TARGET=rpi0_2 mix burn
```

## First boot

1. Boot the Pi and let it join your network.
2. Open `http://nervesview.local:4000` or the device IP.
3. Register the first user. That account becomes admin.
4. Add cameras from the Settings page.

## Wi-Fi on the Pi

The target config reads Wi-Fi credentials from environment variables:

```bash
export NERVES_WIFI_SSID='Tenda_0E98A0'
export NERVES_WIFI_PSK='61338806'
```

Those values are used at build time for the firmware image and are not committed to the repo.

## Camera sources

- `libcamera`: local Pi CSI camera

RTSP ingest is planned, not a finished supported path yet. The intended design is
to pull H.264 RTSP from IP cameras on the device, then keep the browser-facing
live stream on WebRTC and the DVR path on HLS.

## Future Plan

- RTSP ingest for common H.264 IP cameras
- Better source diagnostics for auth, codec, and network failures
- ONVIF discovery so users do not need to type RTSP URLs by hand
- Secure camera credential storage
- Optional support for additional camera classes beyond the local CSI path

## Development

```bash
MIX_TARGET=host mix test
mix phx.server
```

## Storage

- Recordings: `/data/nerves_view/recordings/<camera_id>/`
- Database: `/data/nerves_view/nerves_view.db`
- Persistent app state: `/data/nerves_view/persistence`

## Notes

- This is designed for a local appliance, not a public-facing cloud service.
- Keep `SECRET_KEY_BASE` set in production.
- Use a high-endurance SD card.
