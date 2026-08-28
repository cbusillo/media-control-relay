# App Store Distribution Qualification

## Scope

This record covers the local Mac App Store archive and export path for Media
Control Relay. It does not claim App Store Connect ingestion, TestFlight launch,
App Review acceptance, storefront availability, or update behavior.

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
```

Do not add `-allowProvisioningDeviceRegistration`; this path has no device to
register. Do not change the export destination to `upload` without a separate
decision covering the App Store Connect app record, version/build number,
privacy answers, and TestFlight/App Review intent.

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
- no upload was attempted.

The intermediate archive is development-signed and profile-less; Xcode applies
the distribution identity and App Store profile during export. That distinction
is expected and prevents the archive alone from being treated as the qualified
distribution artifact.

## Remaining Qualification

Issue #16 remains open for:

- App Store Connect privacy-answer reconciliation;
- validation or upload against an intentional app record and build number;
- TestFlight installation, first-run Input Monitoring, and update behavior; and
- an App Review feasibility decision for the sandboxed listen-only event tap.

Raw archives, packages, profiles, and logs remain local and uncommitted.
