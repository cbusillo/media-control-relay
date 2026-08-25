# Media Control Relay

Media Control Relay is a native macOS utility that routes actions from local
control surfaces to supported media devices. The first target family is
compatible Samsung TVs, with optional integrations tracked for Apple TV,
HomePod, and Loupedeck and room for future control surfaces and targets.

> [!IMPORTANT]
> This repository is an early development preview. The app can create an
> explicitly labeled in-process preview target that records routed commands.
> No TV or media device is connected or controlled, normal Mac volume behavior
> is preserved, and there is no downloadable release.

## Product Direction

The finished app is intended to be a quiet menu-bar utility with a focused
setup flow:

1. Select or enter a supported media target.
2. Pair or import credentials through a provenance-safe path.
3. Grant the required macOS permissions.
4. Match the target to its display and audio output when required.
5. Test the actions supported by that target.

The initial release remains focused on reliable volume and mute control for
compatible Samsung TVs. Media Control Relay is not a universal remote or a
general-purpose smart-home hub. It will ship through Developer ID distribution
first; a sandboxed Mac App Store build remains a product goal.

## Current Foundation

This initial slice includes:

- pure Swift control-routing and state-resolution models;
- a deterministic routing reducer with active-route cancellation behavior;
- a removable local preview target with bounded command recording;
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
- [Relay routing](docs/relay-routing.md)
- [Input Monitoring probe](docs/input-monitoring.md)
- [Product identity](docs/product-identity.md)
- [Protocol provenance audit](docs/provenance-audit.md)
- [Privacy](docs/privacy.md)
- [Product plan](https://github.com/cbusillo/media-control-relay/issues/1)

## Compatibility And Affiliation

Compatibility claims will be limited to models validated on real hardware.
Samsung is a trademark of Samsung Electronics Co., Ltd. Media Control Relay is
an independent project and is not affiliated with or endorsed by Samsung.

## License

Original project code is available under the [MIT License](LICENSE). Any future
third-party-derived protocol source must retain its required notices and pass
the documented provenance gate before it is added.
