# Automatic App Store release tracking

The **App Store Release Status** GitHub Actions workflow runs every six hours,
when a GitHub release is published, after a push to main, and on manual dispatch.
It needs no agent, desktop app, Apple account, or App Store Connect credentials.
It reads Apple and writes only its own GitHub tracking issues. It cannot submit,
approve, promote, install, or change an App Store build.

Each stable numeric GitHub release is an intent to deliver that marketing version
to the Mac App Store. The checker creates one issue per GitHub release, reuses it
on retries, and comments only when its observation changes. Drafts, prereleases,
PRs and issues created by people or other automation are excluded. Closing a
record as not planned deliberately retires it; the checker will not recreate it.

The public lookup must identify the configured Apple app ID and Mac software
kind. A valid empty lookup is pending, as expected before the first publication;
failed, malformed or mismatched evidence is unknown. Pending delivery becomes
overdue after the configured allowance from the tracking issue's creation.
Overdue or unknown delivery fails the workflow and records one changed
observation. Neither state identifies whether review is pending or rejected.

When Apple lists the target marketing version, the checker closes its own issue
as completed. A newer public version closes an older record as superseded, not
as proof that the older version was published. Completed records continue to be
checked, so later drift is still visible in comments and workflow failures.
Public version evidence cannot identify the exact uploaded build or prove an
installed storefront update. Broader qualification such as #16 stays separate;
the checker never closes an arbitrary planning issue.

`Config/AppStoreRelease.json` owns the public app ID, storefront and lag allowance.
Release versions come from GitHub, not a second version list in configuration.
The only write credential is the job's existing repository-scoped GitHub token.

Local fixture tests (no network or credentials):

```sh
uv run --no-project python -m unittest discover -s Tests/ReleaseStatusTests -p 'test_*.py'
```

A read-only public lookup is available with
`uv run --no-project python scripts/app-store-release-status.py --lookup-only`.
CI uses the runner's Python 3 standard library; no Python packages are required.

This follows Context Panel's
[durable handoff and public drift](https://github.com/cbusillo/context-panel/blob/main/docs/release.md#durable-handoff-and-public-drift)
pattern, without its multi-platform upload and submission machinery. The public
endpoint is Apple's documented
[ID-based lookup](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/LookupExamples.html).
