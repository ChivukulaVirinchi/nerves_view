# Phase 3 - WebRTC End-to-End Media Path

## Goal
Deliver real browser playback over WebRTC from the live camera pipeline, replacing placeholder SDP/signaling behavior.

## Why this phase exists
- Current signaling APIs and hook are structurally present but still placeholder-oriented.
- End users need real live media in `/dashboard`.

## Scope
- Real offer/answer and ICE lifecycle.
- Session lifecycle correctness.
- Browser hook reliability.

## In Scope Implementation Tasks
1. Replace placeholder server SDP generation.
   - Remove `server_offer_sdp` static path from `WebRTCController`.
   - Integrate real offer generation from peer/session runtime.
2. Upgrade signaling session model.
   - Ensure `create_offer`, `apply_answer`, and ICE updates map to live peer objects.
   - Track session states (`new`, `connecting`, `connected`, `failed`, `closed`).
3. Attach media track(s) to peer connection.
   - Connect camera pipeline output to WebRTC sender path.
   - Confirm codec/profile compatibility for browser playback.
4. Improve connection lifecycle handling.
   - Disconnect cleanup to avoid session leaks.
   - Server-side timeout/reaping for stale sessions.
5. Harden browser hook `webrtc_player.js`.
   - Keep exponential reconnect.
   - Add explicit state handling for failed/disconnected transitions.
   - Ensure idempotent mount/destroy behavior.
6. Update dashboard rendering and statuses.
   - Surface per-camera stream state where useful.

## Files Expected To Change
- `lib/nerves_view_web/controllers/webrtc_controller.ex`
- `lib/nerves_view/streaming/signaling.ex`
- `lib/nerves_view/streaming/peer_connection.ex`
- `lib/nerves_view/streaming/peer_manager.ex`
- `assets/js/hooks/webrtc_player.js`
- `lib/nerves_view_web/live/dashboard_live.ex`
- Related tests under `test/nerves_view/streaming` and `test/nerves_view_web/controllers`

## Test Plan
- Controller integration tests:
  - offer success/failure
  - answer apply
  - ICE candidate flow
- Session lifecycle tests:
  - cleanup on stop
  - stale session pruning
- Manual LAN validation:
  - stream appears in browser
  - reconnect after temporary network interruption

## Acceptance Criteria
- `/dashboard` shows live camera stream over WebRTC.
- API signaling flow uses real SDP and valid session lifecycle.
- Multiple viewers can connect to one camera in LAN test.

## Risks
- Browser codec mismatch and negotiation issues.
- Resource leaks from abandoned peer sessions.

## Mitigation
- Restrict codec profile to known-compatible baseline settings.
- Add cleanup timers and explicit stop paths.

## Exit Artifacts
- Real WebRTC live stream path operational.
- Updated signaling/controller tests passing.
