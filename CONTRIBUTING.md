# Contributing

Thanks for your interest in Media Control Relay. It is a small, focused app, so
please open an issue to discuss a change before starting on anything larger
than a fix.

## Scope

Media Control Relay routes Mac keyboard volume and mute to compatible TVs and
leaves every other audio route to macOS. Changes outside that scope, such as
TV power, navigation, other vendors or control-surface layouts, are unlikely to
be accepted; see [product scope](docs/product-scope.md).

## Setup

Requirements and commands are in the [README](README.md#development). The
complete local gate is:

```sh
scripts/check.sh
```

Pull requests must pass it. Real-device tests are optional and are never
required in CI.

## Rules

- Keep `MediaControlCore` free of AppKit, IOKit, Network and real hardware so
  it stays testable.
- Keep device-specific protocol code behind the target adapter boundary.
- Never commit or log hosts, addresses, device identifiers, credentials, raw
  device responses or private network details. Use synthetic values in tests
  and evidence.
- Do not add pairing code, firmware-derived keys or third-party protocol source
  unless the [provenance audit](docs/provenance-audit.md) allows it.
- UI must work with keyboard navigation, VoiceOver, light and dark mode,
  reduced motion and increased contrast.
- Do not show a working or connected state that the app has not confirmed.

## Pull Requests

- Branch from `main` and open a pull request; `main` is protected.
- Explain why the change is needed, then what changed and how you tested it.
- Add or update tests when needed to prove changed behavior; docs-only changes
  do not need tests that assert wording.
- Update documentation when behavior changes.

## Compatibility Reports

Reports that a TV model works or fails are welcome. See
[compatibility](docs/compatibility.md#reporting-a-new-model).

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
