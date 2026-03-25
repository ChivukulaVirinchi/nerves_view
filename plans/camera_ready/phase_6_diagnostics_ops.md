# Phase 6 - Diagnostics and Operational UX

## Goal
Add practical observability and recovery controls so failures can be diagnosed quickly on device.

## Why this phase exists
- Camera and stream failures are inevitable in embedded/networked environments.
- Users need actionable status, not generic placeholders.

## Scope
- Settings/dashboard diagnostics.
- Recovery controls (restart pipeline).
- Better runtime logging and troubleshooting hooks.

## In Scope Implementation Tasks
1. Add diagnostic status model.
   - Camera detected state.
   - Selected backend and active device path.
   - Pipeline state and last error.
   - Last frame/packet timestamp if available.
2. Extend Settings UI.
   - Render status cards with health indicators.
   - Show actionable error hints.
3. Add operator actions.
   - Restart camera pipeline.
   - Re-run camera probe.
4. Logging improvements.
   - Structured logs around capture start/stop/failure.
   - Correlate stream session IDs to camera IDs where feasible.
5. Optional debug endpoint (auth-protected).
   - Runtime diagnostics snapshot for support/troubleshooting.

## Files Expected To Change
- `lib/nerves_view_web/live/settings_live.ex`
- `lib/nerves_view_web/live/dashboard_live.ex`
- `lib/nerves_view/pipeline/manager.ex`
- `lib/nerves_view.ex`
- Potentially a new diagnostics module under `lib/nerves_view/diagnostics/*`

## Test Plan
- LiveView tests for diagnostic rendering.
- Event tests for restart/probe actions.
- Ensure unauthorized users cannot trigger admin operations.

## Acceptance Criteria
- Operator can identify why stream is down from UI.
- Operator can restart pipeline from UI and observe status transition.
- Logs contain enough context to debug startup and stream issues.

## Risks
- UI over-complexity for first version.

## Mitigation
- Keep status concise: state, reason, and one suggested action.

## Exit Artifacts
- Practical diagnostics and recovery workflow in app.
