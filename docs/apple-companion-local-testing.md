# Apple Companion Local Testing

This workflow installs the optional Apple Companion helper for local owner
testing only. It does not modify an application bundle, does not add Python to
the App Store product, and does not store pairing credentials outside Keychain.

## Install

From the repository root:

```sh
scripts/apple-companion-helper.sh install
```

The installer uses the checked-in `.python-version`, `pyproject.toml`, and
`uv.lock`. It downloads a uv-managed Python runtime into the private helper
root, creates a relocatable virtual environment, installs the locked dependency
set, and atomically selects a content-addressed version.

The default root is:

```text
~/Library/Application Support/com.shinycomputers.media-control-relay/AppleCompanionHelper
```

The root, version directories, copied source, launcher, and virtual environment
are owner-only. The app launches the installed wrapper directly; it does not
invoke `uv`, a system Python, or a shell command containing a host, identifier,
PIN, or credential.

## Inspect Or Update

```sh
scripts/apple-companion-helper.sh status
scripts/apple-companion-helper.sh update
scripts/apple-companion-helper.sh prune
```

`status` is offline and reports `not-installed`, `damaged`, or the active
content digest. `update` installs the current checked-in inputs and atomically
switches `current`. `prune` removes inactive versions only; it never removes the
selected version.

## Remove

```sh
scripts/apple-companion-helper.sh remove
```

Removal deletes only the local runtime root. It deliberately preserves Apple
Companion Keychain data; target removal belongs to the app's setup UI so the
user can distinguish removing a runtime from forgetting a paired target.

## Distribution Boundary

This local runtime is development state, not a distributable product payload.
The App Store target does not link `AppleCompanionSupport`, and validation
rejects Python or helper material in the App Store artifact. Supported
Developer ID helper packaging, transitive provenance, signing, notarization,
and clean-Mac installation are tracked separately in issue #90.

Real Apple TV pairing and control tests are opt-in. Never record the displayed
PIN, device address, stable identifier, credentials, or raw pairing response in
repository files, logs, screenshots, or public issue comments.
