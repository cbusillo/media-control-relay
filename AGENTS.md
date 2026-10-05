# Media Control Relay Agent Notes

## Direction and execution

Read the Director's [overall direction](https://github.com/cbusillo/direction/blob/HEAD/DIRECTION.md)
before starting work. This repository has no `DIRECTION.md` of its own.
`AGENTS.md` is the repository's only agent-instruction file.

Use the maintained [executing loop](https://github.com/cbusillo/codex-skills/blob/main/skills/references/executing-loop.md)
and its owning skills for issue claims, linked worktrees, bot commits, validation,
PR follow-through and closeout. Keep recovery state on the owning GitHub issue.
Apply [reviews by another model](https://github.com/cbusillo/codex-skills/blob/main/skills/references/model-review.md)
to execution-guidance, approval and safety changes; account for the findings
instead of treating reviewer approval as a gate.

## GitHub Workflow

- Treat `main` and any future shared, release, or production branch as a
  protected no-direct-work zone.
- Create a focused task branch before editing or committing implementation or
  repository-policy changes.
- Push task branches and open or update pull requests; do not probe protection
  by attempting a direct push to `main`.
- Use normal merge commits. Do not squash or rebase pull requests.
- Run `scripts/check.sh` and wait for both required checks, `validation` and
  `Analyze Swift`, on the current PR head before merge.
- Follow `.github/github.json`'s merge policy and
  [task scope and authorization](https://github.com/cbusillo/codex-skills/blob/main/skills/references/execution-scope.md):
  Chris's explicit approval covers the change and destination and may already
  come from an instruction to land, an approved plan ending in a merge, or a
  standing grant. With current checks green and any required review findings
  accounted for, carry an authorized merge through. Ask only when approval is
  missing; keep the PR open and record that question on its issue and in the
  final handoff while waiting.
- Delete merged task branches and clean merged worktrees during closeout.

## Host Safety

- Never restart this Mac without obtaining fresh, explicit user confirmation
  immediately before initiating the restart. Earlier or general authorization
  does not carry forward, and an automatic or scheduled restart is not a
  substitute for asking again.

## Product Shape

Media Control Relay retains native keyboard volume/mute routing, active-route
matching, direct Samsung UPnP transport and native Mac fallback. Companion owns
control-surface pages and Apple TV actions; Home Assistant owns automation. Keep
keyboard routing independent of those services. See docs/product-scope.md.

## Engineering Defaults

- Prefer Swift 6, SwiftUI, Swift Package Manager, and XcodeGen.
- Keep `MediaControlCore` pure and testable without AppKit, IOKit, Network, or
  real TV hardware.
- Keep control surfaces and media-target protocol families behind adapters. Do
  not let Samsung-, Apple-, or device-specific framing leak into routing or UI
  state.
- Use Keychain for credentials. Never log or commit hosts, session keys,
  session IDs, device UUIDs, tokens, or raw pairing responses.
- Model dormant, permission, unsupported, offline, and unconfigured states
  explicitly. Dormant is normal, not an error.
- Do not add pairing source, firmware-derived keys, or protocol code until the
  provenance audit explicitly permits it.
- Keep the App Store app useful without Loupedeck or any other third-party
  integration.

## UI Direction

- Use native macOS controls and system colors.
- Keep the menu short and glanceable.
- Use setup and settings windows for explanation and recovery.
- Do not show a working or connected state that the implementation has not
  actually established.
- Accessibility, keyboard navigation, light/dark mode, reduced motion, and
  increased contrast are first-release requirements.

## Validation

Run `scripts/check.sh` before review. Real-device tests are opt-in and must never
be required for public CI.

A test or check stays only if it fails when the product is broken and passes
when someone makes an intended change:

- Do not assert a literal that is defined elsewhere, such as a version, build
  number, toolchain, hash, UI copy, SF Symbol name, or config value. Check
  agreement with the single source of truth instead, or check behavior.
- Do not assert workflow or config text. Enforce the rule where it executes:
  the workflow itself, the built product, or `actionlint`.
- Verification code must not depend on working-tree state. Inspect the built
  app bundle or product code, not repository files read through `#filePath`.
- Keep byte-exact and hash gates on real artifacts, such as the built icon.
