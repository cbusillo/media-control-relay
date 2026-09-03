# Apple Companion Local Testing

This workflow installs the optional Apple Companion helper for local owner
testing only. It does not modify an application bundle, does not add Python to
the App Store product, and does not store pairing credentials outside Keychain.
After installation, the local Release app can discover Apple targets and pair
through the app UI without any bundled product payload.

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

Run `update` again after the helper digest changes so the active install stays
aligned with the checked-in helper source and lockfile. A `not-installed`
status means the local runtime is missing, and a `damaged` status means the
checked-in shape, digest, permissions, or resolved executable no longer match
the trusted layout.

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

When the app first stores Apple credentials, a Keychain prompt may appear in
Debug or Release depending on the signing and sandbox state of the build you
are running. That prompt is expected and should be answered in the local user
session, not worked around by hard-coding credentials or paths.

If saving the completed pairing fails, the app stays in an explicit credential
recovery state rather than claiming the Apple TV is ready. **Try Again** retries
the retained credential write without repeating pairing. **Start Over** returns
to the unconfigured setup state and tears down the pairing session, including
its retained reply. A later app launch resumes only from a successfully stored
credential.
