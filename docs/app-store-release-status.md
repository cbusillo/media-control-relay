# Automatic App Store release tracking

The **App Store Release Status** GitHub Actions workflow checks Apple's public
Mac listing without an agent, desktop app or Apple account. Its schedule and
triggers live in `.github/workflows/app-store-release-status.yml`; the runner
uses Python's standard library and the job's repository-scoped GitHub token.

The highest stable numeric GitHub release supplies the marketing version to
watch. GitHub is the Developer ID channel, so publication there does not prove
App Store submission or start a review deadline. The checker keeps one delivery
issue pending until Apple lists that version. It retires obsolete open records
when a newer release replaces the target or the release is withdrawn. It never
opens records for every historical release.

Apple evidence must identify the configured app ID and Mac software kind. A
valid empty or older listing is pending; failed or mismatched lookup evidence is
unknown. Changed observations get a comment; unchanged runs stay quiet. Neither
pending nor unknown makes code validation fail. Configuration or GitHub errors
still fail the monitoring workflow.

When Apple lists the target, its issue closes as completed. A newer public
version retires the target without claiming it went live. Closed records stay
closed and are never monitored again, including records manually retired as not
planned. Ownership requires both this checker's marker and the GitHub Actions
actor; a different workflow deliberately using the same marker would share
that identity. Human-authored issues and PRs are excluded.

The checker cannot submit, approve or change an App Store build. Public marketing
versions cannot prove exact uploaded build identity or an installed storefront
update, so broader qualification issues stay separate.

`Config/AppStoreRelease.json` owns the app ID and storefront. Local tests use
synthetic fixtures without network or credentials:

```sh
uv run --no-project python -m unittest discover -s Tests/ReleaseStatusTests -p 'test_*.py'
```

A read-only lookup is available with
`uv run --no-project python scripts/app-store-release-status.py --lookup-only`.

This borrows Context Panel's
[durable release tracking](https://github.com/cbusillo/context-panel/blob/main/docs/release.md#durable-handoff-and-public-drift)
pattern without its multi-platform upload machinery, using Apple's documented
[ID-based lookup](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/LookupExamples.html).
