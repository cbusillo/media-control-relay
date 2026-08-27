# Security Policy

## Supported Versions

Media Control Relay is an early development preview without a downloadable
release. Security fixes target the current `main` branch. A versioned support
window will be documented before the first public release.

## Reporting a Vulnerability

Report suspected vulnerabilities privately through GitHub's
[Report a vulnerability](https://github.com/cbusillo/media-control-relay/security/advisories/new)
form. Do not open a public issue, discussion, or pull request for an
uncoordinated vulnerability report.

Include, when possible:

- the affected commit or version and macOS version;
- the security impact and realistic attack path;
- minimal reproduction steps or a proof of concept;
- whether user interaction, local-network access, or physical access is
  required; and
- any mitigation or disclosure constraints you already know about.

Do not submit credentials, pairing material, session identifiers, device UUIDs,
private host or network details, raw device responses, or other personal data.
Use synthetic or redacted evidence. If sensitive evidence is essential, first
ask through the private report how to transfer it safely.

This is a single-maintainer project. Reports are handled on a best-effort basis;
the maintainer aims to acknowledge a complete report within seven business days
and will coordinate remediation and disclosure timing based on severity and
available evidence. These targets are not a contractual service-level
agreement.

## Security Scope

Relevant reports include vulnerabilities involving:

- unauthorized media-control actions or route selection;
- credential storage, secret exposure, or privacy-sensitive logging;
- unsafe handling of local-network discovery or device responses;
- macOS permissions, entitlements, sandboxing, or update/distribution paths;
  and
- dependency or GitHub Actions supply-chain compromise.

Reports about third-party device firmware or services should be sent to the
affected vendor unless Media Control Relay creates or materially worsens the
security impact. Unsupported pairing protocols or firmware-derived keys are not
part of the accepted implementation scope.
