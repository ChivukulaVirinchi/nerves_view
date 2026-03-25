# Phase 2 - Real Camera Capture on Target (All-in-One)

## Goal
Replace descriptor/test-only camera paths with a real target capture pipeline for Pi Zero 2W CSI camera operation.

## Why this phase exists
- Current pipeline manager and camera pipeline are scaffold-oriented.
- We need actual frame ingest on target before WebRTC and recording can be completed.

## Target Runtime Model (Option 1)
- Single device mode (`:standalone` / all-in-one):
  - Camera capture
  - Pipeline processing
  - WebRTC serving
  - Recording
  - Phoenix UI

## Scope
- Real pipeline lifecycle on target.
- Source selection for `:libcamera` (primary) and fallback compatibility.
- Health/status reporting for pipeline.

## In Scope Implementation Tasks
1. Introduce runtime pipeline abstraction.
   - Keep host test source for `MIX_TARGET=host`.
   - Add target runtime source branch for real camera ingest.
2. Implement target camera source startup and supervision.
   - Extend `NervesView.Pipeline.Manager` to track real pipeline PIDs.
   - Ensure restart behavior and clean shutdown on stop/remove.
3. Resolve source normalization and defaults.
   - Validate `:libcamera` default path and fallback handling.
   - Ensure camera config from settings maps to runtime source reliably.
4. Add runtime status fields.
   - `:starting | :running | :error`
   - last error cause
   - started_at and optional last_frame_at
5. Add diagnostics API surface through existing app API module.
   - Expose pipeline health query for UI and tests.

## Files Expected To Change
- `lib/nerves_view/pipeline/manager.ex`
- `lib/nerves_view/pipeline/camera.ex`
- `lib/nerves_view/camera/source.ex`
- `lib/nerves_view/camera/source/libcamera.ex`
- `lib/nerves_view.ex`
- `lib/nerves_view/application.ex` (if supervision adjustments needed)
- `config/target.exs` / `config/runtime.exs` for defaults

## Test Plan
- Host tests for manager behavior still pass.
- Add target-safe unit tests for source normalization and manager status transitions.
- Manual smoke on target:
  1. boot device
  2. register camera
  3. start pipeline
  4. verify status is `:running`

## Acceptance Criteria
- Pi Zero 2W target can start a real camera pipeline.
- Pipeline state is observable and actionable from app code.
- Host behavior remains functional for CI/test flows.

## Risks
- Plugin or target runtime constraints around capture backend.
- Device path differences across kernels/camera firmware.

## Mitigation
- Keep backend selection configurable.
- Add clear error propagation to diagnostics/status UI.

## Exit Artifacts
- Real target capture lifecycle integrated in manager.
- Verified target start/stop flow.
