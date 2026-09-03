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

The candidate remains blocked from distribution. Approval requires the full
license and notice inventory, inside-out signing proof, notarization, quarantine
and clean-Mac qualification, rollback, and App Store exclusion evidence.

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

- downloads only the pinned standalone-runtime asset and verifies its sha256;
- rejects absolute, parent-traversing, or non-`python/` archive paths;
- installs the complete production lock directly into the standalone runtime's
  own `site-packages`, without a virtualenv or absolute interpreter link;
- verifies every installed wheel file against its original `RECORD` before
  pruning, then removes and records only the ten generated console entries;
- removes pip, generated console entry points, headers, tests, bytecode caches,
  Tcl/Tk, IDLE, and build-only metadata that the Companion helper does not use;
- rejects absolute or escaping symlinks;
- proves the staged interpreter version and architecture;
- loads the real helper with isolated Python to verify imports; and
- emits a deterministic manifest of packages, license metadata, native code,
  input hashes, and the complete staged-content digest.

Two independent clean stages produced the same pinned requirements digest,
31-package inventory, 35-file native-code inventory, and complete content
digest. Those expected values are part of `runtime-source.json`, so tool,
wheel-selection, or pruning drift fails instead of silently changing the
candidate.

The staging script deliberately does not modify an app bundle, Xcode project,
archive, signing identity, or notarization submission. It is evidence for the
candidate audit, not a release-packaging path.

## License State

The standalone build project source declares MPL-2.0 and publishes separate
component license files. That is the build project's license, not a single
license for the produced runtime. The stripped candidate artifact carries
CPython's license text but does not carry the standalone project's bundled-
library notice set. Those notices must be sourced and reviewed out of band
before approval. The staged dependency manifest records each installed
distribution's declared license expression and retained license-file paths.

These records are inputs to the required notice audit; they are not a claim
that every obligation has been discharged. `THIRD-PARTY-NOTICES.md` must be
expanded with the approved runtime and complete shipped dependency closure
before the candidate can move from `candidate` to `approved`.

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

The current Application Support runtime contract expects a uv-created virtual
environment and a different three-field manifest. Adopting this candidate will
require a separately reviewed locator/runtime-contract change; the staging
evidence alone does not make the app execute this layout.

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
