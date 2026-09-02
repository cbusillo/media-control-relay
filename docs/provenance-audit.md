# Protocol Provenance Audit

Last verified: September 2, 2026.

This is an engineering provenance assessment, not legal advice. Its purpose is
to keep code with incompatible or unclear origins out of the public repository
until an explicit decision is made.

## Upstream Findings

<!-- markdownlint-disable MD013 -->
<!-- prettier-ignore-start -->

| Component | Upstream | Verified revision | Declared license | Decision |
| --- | --- | --- | --- | --- |
| Legacy H/J command framing, Socket.IO messages, AES-ECB command envelope | `McKael/samtv` | `2cc152f9a697bb7d1ea841f5cc1bb45d417c7688` | MIT | May be implemented later with attribution and retained MIT notice |
| Companion protocol slice for optional Apple controls | `postlund/pyatv` | `v0.18.0`, commit `d88abc960e188d3cd2498d19117e75d7711d8600`; release wheel sha256 `3df6af5679eea809ff17954cf9f5d33c7e5ed5a8d1c90fa14090a0425ce5cd8a` | MIT | Pinned optional Developer ID helper dependency permitted; App Store build remains functional without it |
| Go WebSocket dependency used by the prototype | `gorilla/websocket` | `v1.5.3` | BSD-2-Clause | Not imported into the Swift foundation |
| Legacy pairing Go port | `McKael/smartcrypto` | `29ede3511f7fd37b318ebbf9f8d47b838af4bd3a` | Declares MIT | Quarantined because it identifies itself as a port of the AGPL implementation below |
| Original SmartView2 pairing proof of concept | `sectroyer/SmartCrypto` | `ed33e622b9230267052aab160724a6b398c725be` | AGPL-3.0 | Must not be copied into this MIT project |
| Pairing key constants in `McKael/smartcrypto/keys.go` | Origin not established by the reviewed repository | Not applicable | Unclear | Hard block: do not publish or ship |
| Original UPnP MediaRenderer volume transport | UPnP Forum / Open Connectivity Foundation | UPnP Device Architecture 1.0, revision April 24, 2008; RenderingControl:1 Service Template Version 1.01, June 25, 2002 | Specification reference | Independently authored; no third-party source code imported |

<!-- prettier-ignore-end -->
<!-- markdownlint-enable MD013 -->

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

The approved `postlund/pyatv` Companion slice remains an external dependency;
its protocol source must not be copied or reimplemented in this repository.
The reviewed tag exposes navigation, volume up/down, play/pause,
previous/next, and relative skip. It does not provide native mute or
playback-position state, so the product must not claim either capability in the
Companion-only slice. The `JaviSoto/pyatv` fork remains unapproved unless a
future audit separately reviews and permits an exact revision.

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
5. A pinned optional helper may depend on the approved `postlund/pyatv`
   Companion release in Developer ID distribution. The App Store build must
   remain useful without that helper and report Apple controls as unsupported.
6. Apple pairing credentials must remain in Keychain or in-memory helper
   storage. Default pyatv file storage is prohibited.
7. Apple-control claims are limited to navigation, volume up/down,
   play/pause, previous/next, and relative skip until a later audit approves a
   broader protocol path. Native mute and playback-position state are excluded.
8. Modern Tizen support must receive its own provenance review before code is
   added.
9. The project-wide MIT license applies only to original project code and
   compatible contributions. It does not override third-party obligations.

10. The checked-in Apple Companion helper source and lockfile may exercise the
    approved `pyatv==0.18.0` dependency in local tests with `MemoryStorage` only.
    They do not approve distribution of a Python runtime or pyatv's transitive
    dependency closure. No helper executable or Python payload may be staged
    into a release until those exact shipped artifacts, licenses, hashes,
    signing behavior, and notices are recorded here.

11. Public validation resolves the lockfile's test-only Python dependency
    closure from its recorded package indexes. `uv run --locked` verifies the
    lockfile hashes, but this adds a network and package-index trust surface to
    CI; it does not convert those dependencies into distributable product code.

12. The owner may install a local test runtime with
    `scripts/apple-companion-helper.sh`. That runtime is content-addressed,
    owner-only Application Support state built from the checked-in Python
    version and uv lock. It is not staged into an app, release, archive, or
    public evidence. Distribution remains blocked on issue #90's audit of the
    exact embedded runtime, transitive artifacts, licenses, hashes, signing,
    notarization, and notices.

## Required Follow-Up

- Record exact source revisions and test-vector origins in protocol PRs.
- Keep all real hosts, tokens, session values, UUIDs, and pairing responses out
  of fixtures, screenshots, logs, and public issue comments.
- Obtain legal review before reconsidering any pairing implementation that uses
  firmware-derived or application-derived key material.
