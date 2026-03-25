# Phase 4 - Real Recording and HLS Playback

## Goal
Replace synthetic recording artifacts with real segment writing and playback for recorded camera streams.

## Why this phase exists
- Current HLS writer and playlist serving are scaffold/synthetic.
- Need production-like recording behavior for real usage.

## Scope
- Segment writing from live stream.
- Playlist/segment serving.
- Recording metadata and retention consistency.

## In Scope Implementation Tasks
1. Implement real segment writer pipeline.
   - Replace synthetic `NervesView.Pipeline.HLSWriter` behavior.
   - Produce actual `.m3u8` + `.ts` outputs under data path.
2. Align recording store metadata with file system outputs.
   - Ensure segment paths map to real files.
   - Keep size and timestamps accurate.
3. Extend recording controller routes.
   - Serve playlist and segments with appropriate MIME types.
   - Validate path handling/sanitization.
4. Wire recording mode controls.
   - Continuous and motion-triggered compatibility where supported.
5. Retention and cleanup.
   - `Storage.Manager` removes metadata and files coherently.

## Files Expected To Change
- `lib/nerves_view/pipeline/hls_writer.ex`
- `lib/nerves_view/recording/store.ex`
- `lib/nerves_view/storage/manager.ex`
- `lib/nerves_view_web/controllers/recording_controller.ex`
- `lib/nerves_view_web/live/recordings_live.ex`
- Routing if segment endpoints are added in `lib/nerves_view_web/router.ex`

## Test Plan
- Unit tests for writer metadata and file existence.
- Controller tests for playlist and segment responses.
- Retention tests that verify file removal plus store trim.
- Manual playback test from recordings UI.

## Acceptance Criteria
- New recordings produce real HLS files.
- Playback from UI works against real segments.
- Retention enforcement removes oldest recordings and associated files.

## Risks
- File path race conditions under concurrent writes.
- Partial writes causing invalid playlists.

## Mitigation
- Atomic file update strategy where possible.
- Robust error handling and retry policies for writer failures.

## Exit Artifacts
- Working recording and playback path for real camera stream.
