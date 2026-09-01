# Protocol Provenance Audit

Last verified: August 26, 2026.

This is an engineering provenance assessment, not legal advice. Its purpose is
to keep code with incompatible or unclear origins out of the public repository
until an explicit decision is made.

## Upstream Findings

| Component | Upstream | Verified revision | Declared license | Decision |
| --- | --- | --- | --- | --- |
| Legacy H/J command framing, Socket.IO messages, AES-ECB command envelope | `McKael/samtv` | `2cc152f9a697bb7d1ea841f5cc1bb45d417c7688` | MIT | May be implemented later with attribution and retained MIT notice |
| Go WebSocket dependency used by the prototype | `gorilla/websocket` | `v1.5.3` | BSD-2-Clause | Not imported into the Swift foundation |
| Legacy pairing Go port | `McKael/smartcrypto` | `29ede3511f7fd37b318ebbf9f8d47b838af4bd3a` | Declares MIT | Quarantined because it identifies itself as a port of the AGPL implementation below |
| Original SmartView2 pairing proof of concept | `sectroyer/SmartCrypto` | `ed33e622b9230267052aab160724a6b398c725be` | AGPL-3.0 | Must not be copied into this MIT project |
| Pairing key constants in `McKael/smartcrypto/keys.go` | Origin not established by the reviewed repository | Not applicable | Unclear | Hard block: do not publish or ship |
| Original UPnP MediaRenderer volume transport | UPnP Forum / Open Connectivity Foundation | UPnP Device Architecture 1.0, revision April 24, 2008; RenderingControl:1 Service Template Version 1.01, June 25, 2002 | Specification reference | Independently authored; no third-party source code imported |

## Prototype Assessment

The proven internal prototype does not implement pairing. It reads a host,
session key, session ID, and device UUID produced by an external pairing tool.
Its command framing and encrypted remote-key envelope substantially parallel the
MIT-licensed `McKael/samtv` implementation.

The prototype is evidence that the product can work, not a source tree to copy
wholesale. Host-pinned installers, private configuration paths, LaunchAgent
files, the Go helper process, and the Loupedeck profile mutator remain outside
this repository.

The pure-core media-target contract added in issue #18 is original Swift code.
It introduces no Samsung framing, SOAP, XML, SSDP, or network transport code,
and no third-party-derived protocol source was used to define the contract,
rail model, or reconciliation behavior.

The UPnP MediaRenderer transport is original Swift code written from the
published specifications above. It implements endpoint safety, bounded XML,
device-description and RenderingControl SCPD parsing, service-declared volume
range/step validation, and the four RenderingControl volume/mute actions
without copying third-party source or device-specific control code.

`THIRD-PARTY-NOTICES.md` is required only if a compatible external source
implementation is copied or adapted. Reading published protocol specifications
does not by itself introduce third-party source code into the repository.

The custom URL actuator is original, vendor-neutral app-shell code. It contains
no bundled Loupedeck plugin payload, vendor SDK, profile installer, automatic
profile mutation, device identifier, host-pinned path, or private configuration.
An optional user-created Loupedeck mapping may invoke the three documented
custom URLs, but that mapping is external to this repository and is not required
by the App Store app.

## Decisions

1. The foundation contains no Samsung protocol or pairing implementation.
2. Native H/J pairing is not part of the first release unless its implementation
   can be independently established without AGPL-derived source or unresolved
   embedded key material.
3. A legacy first release may import credentials the user already possesses.
4. A future legacy command adapter may use the documented wire behavior and
   MIT-licensed `McKael/samtv` as a reference only if the required copyright and
   license notice land with that source.
5. Modern Tizen support must receive its own provenance review before code is
   added.
6. The project-wide MIT license applies only to original project code and
   compatible contributions. It does not override third-party obligations.

## Required Follow-Up

- Add `THIRD-PARTY-NOTICES.md` with the first attributed protocol source.
- Record exact source revisions and test-vector origins in protocol PRs.
- Keep all real hosts, tokens, session values, UUIDs, and pairing responses out
  of fixtures, screenshots, logs, and public issue comments.
- Obtain legal review before reconsidering any pairing implementation that uses
  firmware-derived or application-derived key material.
