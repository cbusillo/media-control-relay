# App Store Distribution Qualification

## Scope

This record covers the local Mac App Store archive and export path, App Store
Connect app-record creation, privacy-answer reconciliation, and the first binary
ingestion and internal TestFlight qualification for Media Control Relay. It does
not claim App Review acceptance or storefront availability.

The procedure may contact the Apple Developer service and create or download
signing assets when `-allowProvisioningUpdates` is present. It never commits or
publishes team identifiers, certificate names or hashes, profile names or UUIDs,
account addresses, API key details, or raw signing logs.

## Repository Policy

The `MediaControlRelay` scheme archives with the `AppStore` configuration.
`Config/AppStoreExportOptions.plist` is intentionally local-export-only:

- distribution method is `app-store-connect`;
- destination is `export`, never `upload`;
- signing style is automatic;
- Xcode cannot change the marketing or build number; and
- no team or provisioning-profile identifier is stored in the repository.

Direct Debug and Release builds use the empty
`Config/MediaControlRelay.entitlements` file. Only the `AppStore` configuration
may override that setting, and it must use
`Config/MediaControlRelayAppStore.entitlements` with exactly App Sandbox,
outbound network-client, and inbound network-server access. The server access
permits the bound UDP socket that receives SSDP discovery replies.

`scripts/check-app-store-export.sh` rejects drift in the archive configuration,
entitlement-file wiring, exact entitlement contents, and local-only export and
validation options.

The complete macOS icon ladder and compiled `AppIcon.icns` are generated from
original vector geometry by running `swift scripts/generate-app-icon.swift`.
`scripts/check-app-icon.sh` verifies every source and built icon representation,
including the required 512-point @2x image.

`Config/AppStoreValidationOptions.plist` uses the separate `validation` method.
Its upload destination permits App Store Connect communication. With Xcode 27,
the validation method queried account state and stopped before binary delivery.
Automatic build-number management is disabled, and no account identifiers are
stored in the repository.

## Reproducible Procedure

The operator supplies the development team through a private shell variable and
keeps the archive, export, and logs under ignored `scratch/` storage.

```sh
scripts/generate-project.sh

xcodebuild archive \
  -project MediaControlRelay.xcodeproj \
  -scheme MediaControlRelay \
  -configuration AppStore \
  -destination 'generic/platform=macOS' \
  -archivePath scratch/app-store-export/MediaControlRelay.xcarchive \
  -derivedDataPath scratch/app-store-export/DerivedData \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$MCR_TEAM_ID"

xcodebuild -exportArchive \
  -archivePath scratch/app-store-export/MediaControlRelay.xcarchive \
  -exportPath scratch/app-store-export/export \
  -exportOptionsPlist Config/AppStoreExportOptions.plist \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath scratch/app-store-export/MediaControlRelay.xcarchive \
  -exportPath scratch/app-store-export/validation \
  -exportOptionsPlist Config/AppStoreValidationOptions.plist \
  -allowProvisioningUpdates
```

Do not add `-allowProvisioningDeviceRegistration`; this path has no device to
register. Do not change `Config/AppStoreExportOptions.plist` to use an `upload`
destination without a separate decision covering the App Store Connect app
record, version/build number, privacy answers, and TestFlight/App Review intent.
The validation policy is the narrow exception: its upload destination is pinned
to the `validation` method.

## August 28, 2026 Evidence

Xcode 27.0 build `27A5194q` archived merged commit `829d05e` with the `AppStore`
configuration and exported one installer package. Automatic provisioning
obtained the signing assets required for export without a restart.

Privacy-safe inspection confirmed:

- the installer package signature is valid and uses the Mac App Store installer
  identity class;
- the exported app passes strict deep code-sign verification and uses the Apple
  Distribution identity class with hardened runtime;
- effective entitlements contain only application/team identifiers plus App
  Sandbox and outbound network-client access;
- `get-task-allow` is absent;
- an App Store provisioning profile is embedded and its application identifier
  matches the Media Control Relay bundle identifier;
- `PrivacyInfo.xcprivacy` is present and byte-identical to the repository file;
- the menu-bar agent, Utilities category, and non-exempt-encryption declarations
  are preserved; and
- no upload was attempted during this local export run.

The intermediate archive is development-signed and profile-less; Xcode applies
the distribution identity and App Store profile during export. That distinction
is expected and prevents the archive alone from being treated as the qualified
distribution artifact.

## Remaining Qualification

Issue #16 remains open for:

- an App Review feasibility decision for the sandboxed listen-only event tap;
  and
- post-storefront update behavior when a storefront build becomes available.

Raw archives, packages, profiles, and logs remain local and uncommitted.

## App Store Connect Record and Privacy

On August 28, 2026, the validation method authenticated through the configured
Xcode account and queried App Store Connect for the Media Control Relay bundle
identifier. The service returned a successful collection response with zero app
records, and Xcode stopped with the `missingApp` classification before binary
delivery.

This proves:

- the configured Xcode account can read App Store Connect state;
- no App Store Connect app record was visible to the configured account for the
  bundle identifier at the time of this probe; and
- this validation run did not upload a build or consume build number `1`.

Later on August 28, the operator approved the globally visible app name, a
permanent non-reusable SKU, and English (U.S.) as the primary locale. The macOS
app record was created through the App Store Connect website because Apple does
not support creating app records through the API. API read-back then returned
exactly one record for the bundle identifier and confirmed that the approved
name, SKU, and locale were stored. Repository evidence intentionally omits the
SKU and App Store Connect object identifier.

The App Privacy questionnaire was reconciled with `PrivacyInfo.xcprivacy` and
saved as **Data Not Collected**. This matches the app's local-only architecture,
absence of analytics, advertising, accounts, cloud relay, and third-party
packages, and empty collected-data declaration.

App Store Connect reported that its explicit user-access setting could not be
saved, but confirmed that all account users currently have access to the app.
This matches the approved full-access intent and requires no follow-up unless
access is deliberately restricted later. The public privacy-policy URL now
points to the repository's version-controlled `docs/privacy.md` policy.

## August 28, 2026 First Upload

The first server-side validation of the August 28 package stopped before upload.
Apple rejected the Xcode 27 beta toolchain and reported that the app lacked the
required 512-point @2x icon representation. Build number `1` remained unused.

PR #59 added the complete generated `AppIcon.icns` and source/built-artifact
checks. Xcode 26.6 build `17F113` then archived merged commit `43a7581` and
exported a fresh installer package. Privacy-safe local inspection reconfirmed:

- valid installer and app signatures;
- version `0.1.0`, build `1`;
- the expected App Sandbox and outbound network-client entitlements with no
  `get-task-allow`;
- a valid matching App Store provisioning profile;
- a byte-identical privacy manifest; and
- a byte-identical icon containing all ten macOS representations through the
  required 1024-pixel image.

Apple's validation-only endpoint accepted that package. The subsequent
explicitly authorized upload completed without errors. A subsequent read-only App
Store Connect API query returned one matching unexpired macOS build with version
`0.1.0`, build `1`, and processing state `VALID`.

The build is ingested for TestFlight qualification only. It has not been
submitted for App Review or released to the storefront.

## August 29, 2026 Internal Distribution

Build `1` is assigned to the internal **Owner Validation** group. The group is
limited to the Account Holder, has access only to the explicitly assigned build,
and does not automatically receive future builds. Feedback collection is
enabled.

App Store Connect API read-back confirmed one internal group, one tester, and
one associated build. The build remains valid and unexpired, and its internal
beta state is `IN_BETA_TESTING`. The TestFlight website shows the tester as
invited.

No external-testing group or public link exists, and no App Review submission or
storefront release was initiated. At that point, the next qualification step was
accepting the invitation and installing build `1` through TestFlight on the
target Mac; both completed before the setup-window qualification below.

## August 29, 2026 Setup Window Qualification

The first launch of TestFlight build `1` exposed a release-blocking setup-window
defect. Its unbounded intrinsic content size produced a 560-by-6,650-point
window, making the setup flow taller than the display.

PR #62 made the setup content scrollable, changed the window to use its content
minimum, and advanced the build number to `2`. Build `2` passed local export and
Apple validation, processed as `VALID`, and was explicitly added to the same
one-tester **Owner Validation** group. The TestFlight update installed with a
valid signature and receipt.

Build `2` then exposed the stateful remainder of the defect: macOS restored the
oversized scene frame saved by build `1`, reopening the setup window at
560-by-2,066 points despite the new scroll view. Build `2` therefore failed the
setup-window qualification and was not used for permission qualification.

PR #64 bounded the setup content to a native resizable range with a 560-by-520
ideal content size, a 460-by-360 minimum, and a 720-by-600 maximum, then advanced
the build number to `3`. Local validation confirmed that the stale oversized
state could no longer exceed the bounded range, launching at 560 by 520 points
in the debug build while forced resizing remained bounded and scrollable.

Merged build `3` passed the complete repository checks, local App Store package
inspection, and Apple's validation endpoint. App Store Connect reported the
uploaded build as valid and unexpired. It was explicitly added to **Owner
Validation** without enabling automatic future-build access, external testing,
or a public link.

The TestFlight update from build `2` to build `3` completed successfully. The
installed app reports version `0.1.0`, build `3`, includes its TestFlight receipt,
and passes strict deep signature verification. On the target Mac, the actual
TestFlight build restored the prior window state at 560 by 632 points, safely
inside the visible screen, instead of build `2`'s 560-by-2,066-point result.
Forced enlargement remained capped at 720 by 632 points including window chrome.

This qualifies setup-window fit and the build `2` to build `3` TestFlight update
path. First-run Input Monitoring, Local Network behavior, and the App Review
feasibility decision remain open under issue #16, along with clean reinstall
behavior if it remains necessary after the successful update path. The
clean-install permission and physical-input gaps were addressed by the August
30 run below.

## August 29, 2026 Build 4 Local Network Preparation

TestFlight build `3` qualified Input Monitoring after an app-scoped permission
reset and a fresh macOS consent flow. The app reported volume-key access ready
and detected one physical Volume Up, Volume Down, and Mute press.

Its first Local Network scan showed no macOS consent prompt and ended with a
generic discovery failure. A separately identified, signed sandbox probe built
from the same source reproduced that result with only the network-client
entitlement. Adding the network-server entitlement to an otherwise equivalent
probe reached the genuine macOS Local Network prompt, proving that the SSDP
socket advanced past the sandboxed bind boundary. Consent was not granted to
that isolated probe, so this evidence does not claim post-grant discovery.

Build `4` adds the network-server entitlement only to the `AppStore`
configuration, advances the build number, and extends repository validation to
pin the exact entitlement files, configuration override, and contents. PR #66
merged that change as commit `3add125`; the upload and runtime result are
recorded below.

## August 29, 2026 Build 4 Upload and Local Network Result

Post-merge Validation and CodeQL passed on commit `3add125`. The
operator-selected Xcode 26.6 build `17F113` archived that exact merged commit
and exported one installer package. Privacy-safe local inspection confirmed:

- valid installer and app signatures under the Mac App Store installer and
  Apple Distribution identity classes with hardened runtime;
- version `0.1.0`, build `4`;
- effective entitlements containing only the application and team identifiers,
  App Sandbox, outbound network-client, and inbound network-server access, with
  `get-task-allow` absent;
- an embedded, unexpired App Store profile whose application identifier matches
  the bundle identifier; and
- byte-identical `AppIcon.icns` and `PrivacyInfo.xcprivacy` resources.

Apple's validation-only endpoint accepted the package, and the explicitly
authorized upload completed without errors. Read-only API read-back returned one
matching valid, unexpired macOS build `4` in `IN_BETA_TESTING`. Build `4` belongs
to exactly one beta group: the one-tester internal **Owner Validation** group,
which does not receive future builds automatically. No external group, public
link, App Review submission, or storefront release exists.

TestFlight displayed build `4` as an update to the installed build `3`; after
installation it displayed build `4` as ready to open. The installed
`/Applications` bundle reports `0.1.0 (4)`, carries its TestFlight receipt,
passes strict deep signature verification, and has App Sandbox,
network-client, and network-server access plus TestFlight's
`beta-reports-active`, with `get-task-allow` absent. Apple re-signs the installed
build, so the embedded-profile evidence applies to the exported package rather
than the TestFlight-installed bundle.

In the installed build, General reports volume-key access ready, inherited from
the build `3` grant. No physical key press was exercised under build `4`, and
its session counter remained zero. A Media Target scan returned a generic
renderer result instead of the prior discovery failure, and no target was
selected. No fresh macOS Local Network prompt appeared during that scan, so the
existing consent state was not re-established. The result qualifies that the
network-server entitlement lets the sandboxed SSDP socket produce real
discovery results in an App Store-signed TestFlight build with the inherited
permission state.

This result does not claim fresh-install Input Monitoring or Local Network
consent behavior, post-selection volume control, discovery completeness, or App
Review acceptance. Issue #16 remains open for clean-install first-run consent,
physical volume-key capture under build `4`, and the App Review feasibility
decision for the sandboxed listen-only event tap. The clean-install and physical
capture gaps were addressed by the August 30 run below.

## August 30, 2026 Clean-Mac First-Run Qualification

A separate Apple silicon Mac running macOS 27.0 build `26A5421a` began without
Media Control Relay installed. The application bundle, sandbox container,
preferences, receipt, running process, and Spotlight registration were absent.
App-scoped Input Monitoring and Local Network resets reported no existing
permission records. TestFlight was already installed.

TestFlight installed build `4` into `/Applications`. The installed app reported
version `0.1.0 (4)`, carried its TestFlight receipt, and passed strict deep
signature verification before first launch. Its first launch created the
sandbox container and opened the setup window.

The operator completed the fresh Input Monitoring request, enabled Media Control
Relay in Privacy & Security, and relaunched the app. General then reported
volume-key access ready. One physical Volume Up, Volume Down, and Mute press
produced exactly 3 detected presses with Mute last.

The first **Find Media Renderers** action produced a genuine macOS Local Network
prompt. After the operator allowed access, discovery completed without the
generic failure state, reaching results or an empty list. No target was
selected. This qualifies clean-install first-run Input Monitoring, physical
build-`4` media-key capture, and fresh Local Network consent in the App
Store-signed TestFlight artifact.

This run does not claim discovery completeness, post-selection volume control,
beta-tester feedback, App Review acceptance, or storefront update behavior.

The clean-Mac result satisfies the milestone's installation and first-run
permission criterion regardless of operator identity. Milestone 0.4 now seeks a
separate usability signal through focused TestFlight **What to Test** guidance
and an enabled feedback channel rather than requiring another person to repeat
the same installation proof. Issue #16 remains open for that beta-feedback
request, the App Review feasibility decision, and post-storefront update
behavior when available. No external testing, public link, App Review
submission, or storefront release was initiated.
