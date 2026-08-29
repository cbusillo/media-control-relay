# App Store Distribution Qualification

## Scope

This record covers the local Mac App Store archive and export path, App Store
Connect app-record creation, privacy-answer reconciliation, and the first binary
ingestion for Media Control Relay. It does not claim TestFlight launch, App
Review acceptance, storefront availability, or update behavior.

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

`scripts/check-app-store-export.sh` rejects drift from that policy.

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

- TestFlight invitation acceptance, installation, first-run Input Monitoring,
  and update behavior; and
- an App Review feasibility decision for the sandboxed listen-only event tap.

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
storefront release was initiated. The next qualification step requires accepting
the invitation and installing build `1` through TestFlight on the target Mac.
