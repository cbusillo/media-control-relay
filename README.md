# TV Volume Bridge

TV Volume Bridge is a native macOS utility for routing volume and mute controls
over the local network to compatible Samsung TVs when the configured TV output
is active. Other audio routes continue to use normal macOS volume behavior.

> [!IMPORTANT]
> This repository is an early development preview. The app cannot connect to or
> control a TV yet, and there is no downloadable release.

## Product Direction

The finished app is intended to be a quiet menu-bar utility with a focused
setup flow:

1. Select or enter a compatible TV.
2. Pair or import credentials through a provenance-safe path.
3. Grant the required macOS permissions.
4. Match the TV to its display and audio output.
5. Test Volume Up, Volume Down, and Mute.

The app will ship through Developer ID distribution first. A sandboxed Mac App
Store build remains a product goal, gated by a real Input Monitoring probe and
App Review evidence.

## Current Foundation

This initial slice includes:

- pure Swift routing and state-resolution models;
- activation matching for audio output and display names;
- bounded repeat, debounce, deduplication, and queue policy;
- passive listen-only volume-key observation with permission recovery UI;
- privacy-safe diagnostics redaction;
- a native SwiftUI menu-bar and setup/settings shell;
- separate Developer ID and App Store entitlement files;
- provenance, architecture, privacy, and validation documentation;
- hermetic Swift tests and public secret checks.

It deliberately excludes protocol and pairing source until the provenance gates
in [the audit](docs/provenance-audit.md) are satisfied.

## Development

Requirements:

- macOS 15 or later
- Xcode 16 or later
- Swift 6
- Actionlint, ripgrep, ShellCheck, and XcodeGen 2.40 or later

Install the command-line validation tools with Homebrew:

```sh
brew install actionlint ripgrep shellcheck xcodegen
```

Run the complete local gate:

```sh
scripts/check.sh
```

Or run the package tests directly:

```sh
swift test
```

Generate the Xcode project:

```sh
scripts/generate-project.sh
```

## Documentation

- [Architecture](docs/architecture.md)
- [Input Monitoring probe](docs/input-monitoring.md)
- [Protocol provenance audit](docs/provenance-audit.md)
- [Privacy](docs/privacy.md)
- [Product plan](https://github.com/cbusillo/tv-volume-bridge-for-samsung/issues/1)

## Compatibility And Affiliation

Compatibility claims will be limited to models validated on real hardware.
Samsung is a trademark of Samsung Electronics Co., Ltd. TV Volume Bridge is an
independent project and is not affiliated with or endorsed by Samsung.

## License

Original project code is available under the [MIT License](LICENSE). Any future
third-party-derived protocol source must retain its required notices and pass
the documented provenance gate before it is added.
