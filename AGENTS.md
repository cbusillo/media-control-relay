# Media Control Relay Agent Notes

## Direction and execution

Read the Director's [overall direction](https://github.com/cbusillo/direction/blob/HEAD/DIRECTION.md)
before starting work. This repository has no `DIRECTION.md` of its own.
`AGENTS.md` is the repository's only agent-instruction file. The Director is
this product's Client.

Use the maintained [executing loop](https://github.com/cbusillo/codex-skills/blob/main/skills/references/executing-loop.md)
and its owning skills for issue claims, linked worktrees, bot commits, validation,
PR follow-through and closeout. Keep recovery state on the owning GitHub issue.
Apply [reviews by another model](https://github.com/cbusillo/codex-skills/blob/main/skills/references/model-review.md)
for when to request a review and how to weigh its findings, instead of treating
reviewer approval as a gate.

## GitHub Workflow

Train routing follows the Director's
[overall direction](https://github.com/cbusillo/direction/blob/HEAD/DIRECTION.md#stop-boundaries);
use the shared [merging procedure](https://github.com/cbusillo/codex-skills/blob/main/skills/github/SKILL.md#merging).
Standing merge authorization: [the Director's recorded grant](https://github.com/cbusillo/media-control-relay/issues/129#issuecomment-5988376026).
This repository uses normal merge commits, with `validation` and `Analyze Swift`
required on the current PR head.

TestFlight uploads through the supported path in
[App Store distribution](docs/app-store-distribution.md) are agent work. App
Review submission and store release stay Chris's decision
([Q479](https://github.com/cbusillo/codex-skills/issues/1228#issuecomment-6244384620)).

## Host Safety

- Before restarting this Mac, follow the Chris-Studio restart rule in
  shiny-infra-ops [AGENTS.md Safety rules](https://github.com/cbusillo/shiny-infra-ops/blob/main/AGENTS.md#safety-rules).
  Nothing in this repository authorizes a restart.

## What Media Control Relay does

Media Control Relay routes Mac keyboard volume and mute keys to compatible Samsung TVs, preserving normal Mac behavior on unmatched routes; one model is hardware-qualified.
It retains direct Samsung UPnP control and active-route matching. Companion owns control-surface pages and Apple TV actions; Home Assistant owns automation.
Keep keyboard routing independent of those services. Evidence: [product scope](docs/product-scope.md) and [README.md](README.md).

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

Follow the shared [Tests rule](https://github.com/cbusillo/codex-skills/blob/main/instructions/global.md#tests).
The focused package-test command is declared in [workflow metadata](.github/github.json);
replace `{test_filter}` with the affected Swift package suite or case. Hosted app
behavior uses `xcodebuild test -only-testing:<target>/<suite>`, with DerivedData
and TMPDIR in the task worktree. CI uses the complete validation command declared in
that metadata. Real-device tests are opt-in and never required for public CI.

Run scope-applicable secret, action-pin, shell, workflow, type and platform checks.
Select full safety modules through changed code and its callers; record missing
evidence. For Swift app tests, inspect the built bundle or product code rather
than repository files read through `#filePath`. A byte-exact icon check belongs
on the built icon.
