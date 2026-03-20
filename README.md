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

## Security notes

- CSRF protection enabled for browser forms
- Secure headers enabled in endpoint/router pipeline
- Host-side in-memory auth rate limiting for login/register
