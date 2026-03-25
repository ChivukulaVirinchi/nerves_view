# NervesView

NervesView is a self-hosted surveillance stack built with Nerves, Elixir, Phoenix LiveView, and Membrane-oriented services.

## Development

Run tests on host:

```bash
MIX_TARGET=host mix test
```

Run Phoenix server on host:

```bash
MIX_TARGET=host mix phx.server
```

## Hardware setup guide (Pi Zero 2W)

1. Flash Nerves firmware and boot your Pi Zero 2W.
2. Confirm network and SSH access.
3. Attach camera and verify `/dev/video*` entries.
4. Add the camera in Settings (`/settings`) with source type and device path.
5. Open dashboard (`/dashboard`) and verify stream status.

## Camera-day runbook (Option 1 all-in-one)

1. Flash firmware to SD and boot Pi Zero 2W.
2. Open the app root URL and complete initial setup (`/setup`) for first admin.
3. Add local camera in Settings using `libcamera` and `/dev/video0`.
4. Confirm diagnostics in Settings show pipeline healthy.
5. Open Dashboard for live stream and Recordings for playback checks.

## Deferred roadmap

- Option 2 (hub/node distributed mode) is intentionally deferred and tracked in `plans/camera_ready/phase_7_release_checklist.md`.

## Security notes

- CSRF protection enabled for browser forms
- Secure headers enabled in endpoint/router pipeline
- Host-side in-memory auth rate limiting for login/register
