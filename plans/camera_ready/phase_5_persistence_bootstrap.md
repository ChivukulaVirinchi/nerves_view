# Phase 5 - Persistence, Secrets, and Bootstrapping

## Goal
Ensure configuration and essential state survive reboot, and first-boot setup is safe and usable.

## Why this phase exists
- Current camera/auth/session stores are in-memory.
- Current runtime secret defaults are not production-safe.
- Plug-and-use requires reboot resilience.

## Scope
- Persistent storage for camera configuration.
- Practical auth bootstrap for first device setup.
- Runtime secret management and hardening.

## In Scope Implementation Tasks
1. Persist camera configuration.
   - Introduce persistence layer (file-backed or DB-backed) for camera definitions.
   - Load persisted cameras on app start.
2. Persist essential auth state.
   - Define minimum viable persistence for users and sessions.
   - Keep migration path open for stronger auth stack later.
3. First-boot admin setup flow.
   - Detect no-admin/no-user state and route to setup flow.
   - Create initial admin securely.
4. Secret handling in runtime config.
   - Remove weak fallback secrets from production runtime.
   - Define required env or generated-on-first-boot secret strategy.
5. Startup behavior.
   - Auto-start persisted enabled cameras at boot.
   - Recover gracefully if one camera fails.

## Files Expected To Change
- `lib/nerves_view/camera/registry.ex` (or new persistent wrapper)
- `lib/nerves_view/accounts/store.ex`
- `lib/nerves_view/accounts/session_store.ex`
- `lib/nerves_view/application.ex`
- `config/runtime.exs`
- `lib/nerves_view_web/router.ex` and auth/setup LiveView/controller files

## Test Plan
- Restart/reload tests validating persisted state restoration.
- First-boot flow tests for setup gating.
- Runtime config validation tests for missing secrets.
- End-to-end smoke: configure camera, reboot, verify camera still present.

## Acceptance Criteria
- Camera config persists across reboot.
- Initial admin setup only required once on clean install.
- Production runtime does not depend on insecure hardcoded secret.

## Risks
- Migration complexity from in-memory to persisted models.

## Mitigation
- Introduce adapters/interfaces first, then switch default implementation.

## Exit Artifacts
- Reboot-safe configuration and secure bootstrap path.
