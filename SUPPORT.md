# Support

Media Control Relay is maintained by one person on a best-effort basis.

## Before Asking

1. Read [Troubleshooting](docs/troubleshooting.md) for the status the app
   shows.
2. Check [Compatibility](docs/compatibility.md). Only listed models are
   supported.

## Asking For Help

Open an issue at
<https://github.com/cbusillo/media-control-relay/issues> and include:

- the app version from Settings (**Build**);
- your macOS version and Mac model;
- the TV model and the TV input you use;
- what you pressed, what you expected and what happened; and
- the output of **Copy Diagnostics** from Settings.

Diagnostics contain only coarse status fields and counts. Do not add IP
addresses, device identifiers, network names or screenshots that show them.
The `target_kind` field identifies the configured target, including a recording
preview; it does not describe the app's release status.

## Security Issues

Do not report vulnerabilities in a public issue. Follow the
[security policy](SECURITY.md).

## What Is Out Of Scope

Media Control Relay routes keyboard volume and mute only. Requests for TV power,
input switching, navigation, other vendors or Apple TV control are outside its
scope; see [product scope](docs/product-scope.md).
