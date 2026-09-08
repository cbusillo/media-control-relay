# Apple Companion Runtime Provenance

Last verified: September 7, 2026.

This record covers the qualified self-contained Apple Companion runtime for
Developer ID distribution. Approval is limited to the exact runtime and artifact
recorded below. This is an engineering provenance record, not legal advice or
authorization to publish a release.

## Decision

The first candidate is the stripped `install_only` CPython 3.13.7 arm64
artifact from `astral-sh/python-build-standalone` release `20250818`. The exact
asset and GitHub-published sha256 digest are pinned in
`AppleCompanionHelper/runtime-source.json`.

This candidate is preferred over an embedded `Python.framework` because it is
a small transparent directory tree, matches the runtime family already used by
the local uv-managed qualification path, and can be staged without an installer
or framework relocation. Freeze tools remain out of scope because they add a
bootloader and another binary provenance surface.

The runtime proxy and package notice reviews are complete. Local Developer ID
signing, same-Team runtime launch, notarization, quarantine assessment, rollback,
and App Store exclusion evidence also pass. The exact arm64 runtime and recorded artifact are now qualified using the
combined physical development-Mac and pristine virtualized acceptance below.
New release artifacts still require the notarization runbook and release approval.

## Architecture

The universal application remains available on both Apple silicon and Intel.
The first helper-runtime candidate is arm64-only. On Intel, Apple Companion
controls must report unsupported while the rest of Media Control Relay remains
useful.

The exact locked `cryptography==50.0.1` release publishes a macOS wheel for
arm64 but not x86_64. Building a replacement Intel wheel from source would
introduce an additional Rust compiler, reproducibility, and artifact-audit
surface. The `zeroconf==0.151.3` wheel also contains arm64 Cython extensions,
but those optional modules are now removed and its architecture-neutral
pure-Python implementation is retained. The arm64 standalone interpreter and
`cryptography` wheel still make Intel helper support out of scope.

## Staging Contract

`scripts/stage-apple-companion-runtime.sh` produces an ignored candidate under
`scratch/`. It:

- downloads the pinned standalone-runtime asset and the pinned same-release
  full-variant notice proxy, and verifies both sha256 digests;
- rejects absolute, parent-traversing, or non-`python/` archive paths;
- fixes generated runtime permissions independently of the caller's umask;
- installs the complete production lock directly into the standalone runtime's
  own `site-packages`, without a virtualenv or absolute interpreter link;
- verifies every installed wheel file against its original `RECORD` before
  pruning, then removes and records the ten generated console entries and the
  exact 18 optional zeroconf Cython extensions approved by the license policy;
- removes pip, generated console entry points, headers, tests, bytecode caches,
  Tcl/Tk, IDLE, and build-only metadata that the Companion helper does not use;
- rejects absolute or escaping symlinks;
- proves the staged interpreter version and architecture;
- loads the real helper with isolated Python and proves zeroconf resolves to
  its retained `.py` modules;
- validates each package's exact metadata evidence against
  `AppleCompanionHelper/license-policy.json`;
- regenerates `AppleCompanionHelper/NOTICES.md` from the pinned runtime notice
  proxy and retained wheel files, requiring byte-for-byte equality; and
- emits a deterministic manifest of packages, license evidence, runtime notice
  sources, native code, input hashes, and the complete staged-content digest.

Two independent clean stages produced the same pinned requirements digest,
31-package inventory, 19-file runtime notice proxy, 38-file package license
inventory, 17-file native-code inventory, notice digest, and complete content
digest. Those expected values are part of `runtime-source.json`, so tool,
wheel-selection, notice, metadata, or pruning drift fails instead of silently
changing the candidate.

The staging script deliberately does not modify an app bundle, Xcode project,
archive, signing identity, or notarization submission. It is evidence for the
candidate audit, not a release-packaging path.

## License State

The standalone build project source declares MPL-2.0. That is the build
project's license, not a single license for the produced runtime. The stripped
candidate artifact carries CPython's license text but does not carry the build
project's bundled-library notice set. The inventory therefore pins the
`pgo+lto-full` asset from the same project release and records all 19 of its
`python/licenses/` files as a conservative proxy. Artifact-level comparison
establishes that all 1,828 paths in the stripped install artifact exist in the
full artifact's `python/install` tree: 1,812 are byte-identical and the other 16
are executable or library files changed by stripping. The proxy may over-report
components later removed by pruning, but it does not omit a source-runtime path.

`AppleCompanionHelper/license-policy.json` records the exact metadata evidence,
resolved expression, and review state for all 31 locked distributions. The
generated `AppleCompanionHelper/NOTICES.md` includes the 19 runtime-proxy files
and all 38 retained package license, notice, copying, and author files with
their sha256 digests. Staging regenerates that file and fails on any package,
metadata, path, file, or text drift.

The three package reviews are resolved:

- `certifi==2026.7.22` is shipped unmodified in source form with its MPL-2.0
  notice and Mozilla-derived CA bundle. File-level terms do not extend to the
  surrounding application, and update cadence is a security-maintenance concern
  rather than an additional license condition.
- `chacha20poly1305-reuseable==0.13.2` declares Apache-2.0 OR BSD-3-Clause in
  the exact sdist and includes both grants in the retained wheel license file.
  Distribution elects BSD-3-Clause; the generic proprietary classifier is
  packaging metadata for the compound expression, not a conflicting grant.
- `zeroconf==0.151.3` remains under LGPL-2.1-or-later, but its 18 optional
  Cython modules are pruned. The distributed helper retains the unmodified
  preferred `.py` source, package metadata, and complete LGPL notice, and its
  isolated import check proves the pure-Python path is used.

The generated notice set is an engineering integrity record, not a claim that
the notices are legally sufficient or that every obligation has been
discharged. The source manifest now records `qualified` status. Existing candidate staging
markers and generated notice terminology remain stable; they identify the
validated payload format and do not override distribution approval metadata.

## Signing and Distribution Gates

Every recorded Mach-O leaf is signed before the helper payload and outer
application. The qualified path does not add library-validation, JIT, unsigned
memory, or similar hardened-runtime exceptions.

The existing notarization runbook remains authoritative for the outer app,
designated-requirement continuity, submission, stapling, quarantine, rollback,
and private evidence handling. Runtime-specific qualification must additionally
prove:

- no ad-hoc nested Mach-O remains;
- the signed native-code inventory exactly matches the staged manifest;
- the helper launches from the application bundle on a clean Apple silicon Mac
  without Homebrew, uv, or another Python installation;
- whole-app rollback replaces the helper runtime atomically and preserves
  Keychain credentials; and
- the App Store artifact contains no helper, Python runtime, package metadata,
  native extension, or executable-download path.

`AppleCompanionHelper/runtime-contract.json` now defines the staged marker,
manifest, launcher, interpreter, Python version, architecture, exact candidate
content digest, and future bundle location. Swift tests require the compiled
locator constants to match that file, and staged-runtime validation requires
the candidate to satisfy it.

Debug and Developer ID code paths now check the future
`Contents/Resources/AppleCompanionRuntime` location before falling back to the
owner-installed Application Support runtime. A present but invalid bundled
runtime fails closed instead of silently falling back. Intel hosts report Apple
Companion as unsupported while the rest of the app remains useful. No current
build copies the candidate into an app bundle, and validation requires both
Release and App Store artifacts to keep that location absent.

Developer ID qualification uses a separate out-of-band packaging step on a copy
of the unsigned Release archive. `scripts/package-apple-companion-runtime.sh`
validates the pristine candidate, copies it only into an application containing
the live adapter, signs the exact 17 native-code leaves from the manifest
inside-out with hardened runtime and no entitlements, and then requires the
outer app to be signed after every leaf is final. It rejects the App Store
partition before creating the runtime destination. Developer ID archives retain
their global Swift symbol table through runtime admission so the live-adapter
gate stays tied to linked arm64 code. The outer executable is stripped only
after the runtime is admitted and before final application signing; validation
exercises that exact archive-to-sign sequence and proves a symbol-stripped input
is rejected without leaving runtime material behind.

The unsigned candidate digest, native-code hashes, and package `RECORD` entries
remain the pre-sign provenance boundary. Because `codesign` changes Mach-O
bytes, those hashes are not recomputed after signing. The outer application code
signature is the shipped integrity boundary: it seals the signed native leaves
and every runtime resource. The Swift locator verifies the containing
application with Security.framework strict, nested-code, and all-architecture
checks, and requires its bundle identifier and Team ID to match the running
process under a Developer ID Application certificate before it accepts a
present runtime. The live runtime provider performs that potentially expensive
verification away from the main actor. Missing Team IDs, ad-hoc signatures,
invalid nested code, or altered resources fail closed as damaged.

The normal Release payload-absence gate remains in place, as does complete App
Store exclusion. CI proves the packaging and integrity boundary on copied build
products with ad-hoc signatures, including native, Python-resource, and marker
tamper failures. Local Developer ID qualification established same-Team locator
acceptance, Python launch without weakened entitlements, notarization,
quarantine assessment, rollback, and Keychain preservation. The combined qualification below completes the outstanding tooling-free
launch and online/offline Gatekeeper evidence for this exact artifact.

## Recorded Qualification

On September 7, 2026, the owner-approved combined qualification completed for:

- Source commit: `952fea3049913bd71014a0ca20b1f80d2c348157`.
- Notarized ZIP SHA-256: `b4a2a15c26be1964ecb75ed17c8b1a4f6d17c5798bcd113bcb879e2710b56644`.
- Application executable SHA-256: `2fc5e5e5d4c9279b691483b70b240e93464b0d156cdfbdd96dfacb04db57dc36`.
- Unsigned runtime content SHA-256: `10e741b0867c692e3ecf019d43f2c4bf0055246d0da66409a94cae9fcc219324`.

The physical development Mac supplied the prior 17-leaf signing, same-Team
locator/helper launch, Accepted notarization, staple validation, quarantined
installation, rollback/restoration, frontmost preservation, and Keychain
preservation evidence. A pristine arm64 macOS 26.6.2 (25G83) VM supplied the
absence of Homebrew, uv, Xcode/Command Line Tools, standalone Python, prior app,
and owner-installed fallback helper. This was not a second clean physical Mac.

A never-launched, never-assessed seed acquired the exact app through Safari and
Archive Utility, preserving propagated quarantine. Separate clones supplied:

- Offline strict signature and Gatekeeper acceptance with
  `source=Notarized Developer ID`. The guest Ethernet service was disabled,
  its interface inactive without an IP, and unscoped IPv4/IPv6 default routes
  absent. Two outbound controls failed during isolation; restoration and a
  positive outbound control passed. Scoped tunnel entries remained. This does
  not establish absence of undocumented trust caches or offline GUI launch.
- Fresh Finder installation and Internet-download confirmation, captured before
  clicking Open. The exact app executable and its parented helper ran directly
  from `/Applications/Media Control Relay.app`. Strict signatures passed,
  helper and outer app Teams matched, and the fallback helper was absent.
  Captured UI showed unconfigured and then offline states, with no Helper
  Damaged state. No real-device pairing or connectivity claim follows.
- Online Gatekeeper acceptance as `Notarized Developer ID` after GUI first open
  and the installed helper check, with a passing outbound connectivity control.

The first online attempt used a copy that launched under App Translocation;
its results remain preserved, but the fresh Finder installation supersedes it
for installed-path and first-open acceptance. The offline harness first stopped
before assessment on an incorrect route exit-status assumption; a reviewed
correction passed. A later guest-agent transport failure occurred after success
and network restoration were recorded and was independently reconciled. These
incidents do not imply a clean harness exit or an additional app assessment.

Opus and Gemini reviewed the combined qualification evidence and returned GO
for the recorded scope. The operator directly inspected the CUA screenshot captures;
reviewers assessed textual evidence summaries. Raw logs and captures stay in
private evidence. CI continues to enforce the exact approval record, runtime
content pin, normal Release payload absence, and complete App Store exclusion.
The out-of-band packager remains the only runtime admission path; this approval
does not copy payloads into ordinary builds or waive future signing checks.

## Verification

Run the offline source check:

```sh
scripts/check-apple-companion-runtime.sh
```

Stage and validate the candidate in ignored storage:

```sh
scripts/stage-apple-companion-runtime.sh \
  scratch/apple-companion-runtime-candidate
scripts/check-apple-companion-runtime.sh \
  scratch/apple-companion-runtime-candidate
```

No staged runtime or downloaded artifact belongs in Git.

Exercise the Developer ID packaging and signature boundary against existing
Release and App Store build products without a private identity:

```sh
scripts/check-apple-companion-runtime-signing.sh \
  "<release-app>" \
  scratch/apple-companion-runtime-candidate \
  "<app-store-app>"
```
