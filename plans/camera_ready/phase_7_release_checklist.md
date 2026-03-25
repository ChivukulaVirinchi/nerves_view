# Phase 7 Release Checklist (Option 1 All-in-One)

## Build Validation
- [ ] `MIX_TARGET=host mix test` passes
- [ ] `MIX_TARGET=host mix compile` passes cleanly
- [ ] `MIX_TARGET=rpi0_2 mix firmware` builds

## Functional Validation
- [ ] First boot routes to `/setup` when no users exist
- [ ] Create first admin and login succeeds
- [ ] Add local camera in `/settings`
- [ ] Dashboard shows camera and WebRTC negotiation API works
- [ ] Recording appears in `/recordings`
- [ ] Playlist and segment URLs return content

## Persistence Validation
- [ ] Reboot keeps user account
- [ ] Reboot keeps camera configuration
- [ ] Pipeline starts after app reboot

## Diagnostics Validation
- [ ] Settings diagnostics render backend/path/health
- [ ] Restart pipeline action succeeds
- [ ] Dashboard shows pipeline and healthy indicators

## Camera-Day Runbook
1. Flash SD with latest firmware image.
2. Boot Pi Zero 2W and join LAN.
3. Open root URL and complete `/setup`.
4. Add local camera (default `/dev/video0`).
5. Confirm diagnostics healthy in `/settings`.
6. Open `/dashboard` and validate live stream.
7. Open `/recordings` and validate playback links.

## Option 2 TODO (Deferred)
- Hub/node registration protocol hardening
- Node stream forwarding to central hub
- Auto-discovery UI and node management
- Cross-node auth and permissions
- Cluster fault recovery and stream failover
