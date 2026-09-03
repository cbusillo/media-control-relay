# Apple Companion Runtime Provenance

Last verified: September 3, 2026.

This record covers the first candidate for a self-contained Apple Companion
runtime in Developer ID distribution. It is an engineering provenance record,
not legal advice and not distribution approval.

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

The candidate remains blocked from distribution. Its notice inventory is now
deterministic and reviewable, but the recorded runtime proxy and package review
items remain unresolved. Approval also requires inside-out signing proof,
notarization, quarantine and clean-Mac qualification, rollback, and App Store
exclusion evidence.

## Architecture

The universal application remains available on both Apple silicon and Intel.
The first helper-runtime candidate is arm64-only. On Intel, Apple Companion
controls must report unsupported while the rest of Media Control Relay remains
useful.

The exact locked versions of `cryptography==50.0.1` and
`zeroconf==0.151.3` publish macOS wheels for arm64 but not x86_64. Building
replacement Intel wheels from source would introduce an additional compiler,
Rust/Cython, reproducibility, and artifact-audit surface. That work is not part
of the first candidate.

## Staging Contract

`scripts/stage-apple-companion-runtime.sh` produces an ignored candidate under
`scratch/`. It:

- downloads the pinned standalone-runtime asset and the pinned same-release
  full-variant notice proxy, and verifies both sha256 digests;
- rejects absolute, parent-traversing, or non-`python/` archive paths;
- installs the complete production lock directly into the standalone runtime's
  own `site-packages`, without a virtualenv or absolute interpreter link;
- verifies every installed wheel file against its original `RECORD` before
  pruning, then removes and records only the ten generated console entries;
- removes pip, generated console entry points, headers, tests, bytecode caches,
  Tcl/Tk, IDLE, and build-only metadata that the Companion helper does not use;
- rejects absolute or escaping symlinks;
- proves the staged interpreter version and architecture;
- loads the real helper with isolated Python to verify imports;
- validates each package's exact metadata evidence against
  `AppleCompanionHelper/license-policy.json`;
- regenerates `AppleCompanionHelper/NOTICES.md` from the pinned runtime notice
  proxy and retained wheel files, requiring byte-for-byte equality; and
- emits a deterministic manifest of packages, license evidence, runtime notice
  sources, native code, input hashes, and the complete staged-content digest.

Two independent clean stages produced the same pinned requirements digest,
31-package inventory, 19-file runtime notice proxy, 38-file package license
inventory, 35-file native-code inventory, notice digest, and complete content
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
`python/licenses/` files as a conservative proxy. This is not an identity claim:
some listed components may be absent after pruning, and the proxy does not prove
that no other obligation exists.

`AppleCompanionHelper/license-policy.json` records the exact metadata evidence,
resolved expression, and review state for all 31 locked distributions. The
generated `AppleCompanionHelper/NOTICES.md` includes the 19 runtime-proxy files
and all 38 retained package license, notice, copying, and author files with
their sha256 digests. Staging regenerates that file and fails on any package,
metadata, path, file, or text drift.

Three review items remain explicit and distribution-blocking:

- `certifi==2026.7.22` uses MPL-2.0 and carries the Mozilla CA bundle; its
  file-level source and bundle attribution/update obligations need review.
- `chacha20poly1305-reuseable==0.13.2` has a legacy Apache-2.0 OR BSD-3-Clause
  field and a conflicting proprietary classifier; that metadata conflict needs
  resolution.
- `zeroconf==0.151.3` uses LGPL-2.1-or-later and includes compiled extension
  modules; source and relinking obligations need review.

The generated notice set is an engineering integrity record, not a claim that
the notices are legally sufficient or that every obligation has been
discharged. The candidate must remain `candidate` until the review items and
the remaining distribution gates are resolved.

## Signing and Distribution Gates

The next slice must sign every recorded Mach-O leaf before signing the helper
payload and outer application. It may not add library-validation, JIT, unsigned
memory, or similar hardened-runtime exceptions without a separate review.

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
the live adapter, signs the exact 35 native-code leaves from the manifest
inside-out with hardened runtime and no entitlements, and then requires the
outer app to be signed after every leaf is final. It rejects the App Store
partition before creating the runtime destination.

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
tamper failures. Distribution remains unapproved until the recorded notice
review, notarization, quarantine, rollback, and clean-Mac gates are complete.
The same-Team Developer ID runbook must also prove that the locator accepts the
runtime-carrying app and that Python launches without weakened entitlements;
ad-hoc CI cannot establish that accepting direction.

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
