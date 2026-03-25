# Phase 7 - Release Certification + Hub/Node TODO Track

## Goal
Finalize a release candidate for camera-arrival day and explicitly park Hub/Node (Option 2) as a tracked TODO roadmap.

## Why this phase exists
- We need confidence that Option 1 (all-in-one) is deployable now.
- Option 2 should be deferred intentionally, not forgotten.

## Scope
- Validation checklist for all-in-one readiness.
- Build/release packaging and runbook.
- Documented TODO backlog for Hub/Node implementation.

## In Scope Implementation Tasks
1. Readiness checklist execution.
   - Host test suite.
   - Target smoke tests on Pi Zero 2W.
   - Stream and recording manual verification.
2. Firmware release candidate.
   - Build reproducible target firmware artifact.
   - Verify fresh SD boot path.
3. Camera-day runbook.
   - Step-by-step setup from first boot to first live stream.
   - Troubleshooting section with common failure signatures.
4. Document Option 2 as TODO roadmap.
   - Hub/node registration protocol improvements.
   - Node stream forwarding.
   - Discovery UX and distributed reliability concerns.
   - Security and auth model across nodes.
5. Add release sign-off table.
   - Owner, status, date, evidence links.

## Files Expected To Change
- `README.md` (camera-day runbook + troubleshooting)
- `PLAN.md` (Option 1 complete, Option 2 TODO breakdown)
- New release checklist doc under `plans/camera_ready/`

## Test Plan
- `MIX_TARGET=host mix test` final run.
- Target smoke script/manual matrix:
  - boot
  - login/setup
  - camera detect
  - live stream
  - recording playback
  - reboot persistence

## Acceptance Criteria
- All-in-one path is validated end-to-end.
- User can follow runbook and reach live stream quickly.
- Option 2 backlog is explicit and prioritized.

## Risks
- Last-minute regressions under target-only constraints.

## Mitigation
- Freeze release candidate after certification.
- Keep rollback image and known-good build notes.

## Exit Artifacts
- Camera-arrival-ready software release and checklist evidence.
- Hub/node TODO roadmap documented and visible.
