# Phase 1 - Stabilize Baseline

## Goal
Make the current host and app baseline deterministic and green before implementing real media features.

## Why this phase exists
- Current test runs are mostly green but have at least one flaky/failing test in the pipeline area.
- Building real camera and WebRTC features on an unstable baseline will hide regressions.

## Scope
- Test determinism and reliability.
- Cleanup of brittle timing-based tests.
- Baseline CI-equivalent local validation.

## In Scope Implementation Tasks
1. Make pipeline test deterministic.
   - Refactor `test/nerves_view/pipeline/manager_test.exs` to avoid fixed sleeps.
   - Add polling helper with timeout for frame count assertions.
2. Audit known timing-sensitive tests.
   - Search tests that rely on `Process.sleep/1` and replace with state-based waits where possible.
3. Add repeatability run.
   - Execute `MIX_TARGET=host mix test` multiple times to catch flakes.
4. Keep behavior unchanged in production paths.
   - This phase is reliability-first, no user-facing feature changes.

## Files Expected To Change
- `test/nerves_view/pipeline/manager_test.exs`
- `test/support/*` (if helper modules are added)
- Potentially a small test utility module under `test/support`

## Test Plan
- Command: `MIX_TARGET=host mix test`
- Run at least 3 consecutive times.
- Confirm no flake in pipeline manager tests.

## Acceptance Criteria
- Host test suite passes consistently (3 consecutive full runs).
- No known flaky tests remain in critical media/signaling paths.
- No changes to app behavior beyond test reliability.

## Risks
- Overfitting tests to current implementation details.

## Mitigation
- Assert on observable API outcomes, not private process internals.

## Exit Artifacts
- Green and repeatable host test baseline.
- Short notes in commit message describing flake fix approach.
