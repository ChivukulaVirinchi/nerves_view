# Camera-Ready Software Plan (Option 1 First)

This directory contains the detailed implementation plan to make `nerves_view` ready for immediate use when the camera arrives.

## Strategy Decision
- **Primary path now:** Option 1 (all-in-one on Pi Zero 2W)
- **Deferred path:** Option 2 (hub/node distributed architecture) tracked as TODO in Phase 7

## Phase Index
1. `phase_1_stabilize_baseline.md`
2. `phase_2_real_camera_capture_target.md`
3. `phase_3_webrtc_e2e_media.md`
4. `phase_4_recording_real_hls.md`
5. `phase_5_persistence_bootstrap.md`
6. `phase_6_diagnostics_ops.md`
7. `phase_7_release_certification_and_todo_hub_node.md`

## Execution Order
Execute phases strictly in order. Do not start a later phase until acceptance criteria for the current phase are met.

## Global Definition of Done
- Live camera stream works on Pi Zero 2W in browser dashboard.
- Recording and playback are real (not synthetic).
- Reboot preserves camera configuration and boot resumes service.
- Basic diagnostics and recovery actions are available in UI.
- Camera-day runbook is complete and validated.
