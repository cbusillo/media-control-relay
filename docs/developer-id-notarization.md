# Developer ID Notarization

This runbook produces the notarized direct-distribution artifact used for a
signed local alpha. It keeps credentials outside the repository, builds from an
exact reviewed commit, preserves the accepted designated requirement for macOS
permission continuity, and retains a rollback app until local cutover is
complete. GitHub issue #46 owns the local-alpha notarization evidence and
closure decision.

## Preconditions

- Work from a clean task or default-branch checkout at the exact approved
  commit.
- Use the repository's supported Xcode version and the intended Developer ID
  Application identity.
- Install `jq` and confirm it is available on `PATH`. The other command-line
  tools used below, including `/usr/libexec/PlistBuddy`, ship with macOS or
  Xcode.
- Before the cutover rehearsal, grant the shell host permission to automate
  System Events. Do this before measuring the frontmost application so a
  first-run Automation prompt cannot invalidate that check.
- Keep the direct-distribution entitlements at
  `Config/MediaControlRelay.entitlements`.
- Store notarization credentials in Keychain under the profile name
  `MediaControlRelay`. Enter credential values only into Apple's prompt:

  ```bash
  xcrun notarytool store-credentials "MediaControlRelay"
  ```

- Keep archives, notarization responses, and rollback bundles outside the
  repository. Never commit private keys, issuer IDs, submission IDs, raw
  notarization logs, or local artifact paths.

## Prepare the Exact Commit

Combine the applicable shell blocks from this section through **Install and
Rehearse Rollback**, in order, into one private script and execute it once from
the repository root with `/bin/bash`. Include the optional offline block only
when performing that proof. Do not paste the blocks into separate shells or run
them in an interactive shell: later blocks depend on variables and failure
handling established here.

Set `ROLLBACK_EXECUTABLE_SHA256` from the accepted predecessor's recorded
release or qualification evidence. Do not derive the expected value from the
currently installed app during this run.

```bash
set -euo pipefail

EXPECTED_COMMIT="<full-reviewed-commit>"
PROFILE="MediaControlRelay"
IDENTITY="Developer ID Application: <organization> (<team-id>)"
EXPECTED_BUNDLE_ID="com.shinycomputers.media-control-relay"
EXPECTED_VERSION="0.1.0"
EXPECTED_BUILD="5"
ROLLBACK_EXECUTABLE_SHA256="<accepted-predecessor-executable-sha256>"
ARTIFACT_ROOT="${HOME}/.code/artifacts/media-control-relay/${EXPECTED_COMMIT:0:7}-notarization"
ARCHIVE="${ARTIFACT_ROOT}/MediaControlRelay.xcarchive"
APP="${ARCHIVE}/Products/Applications/Media Control Relay.app"
ROLLBACK_APP="${ARTIFACT_ROOT}/rollback/Media Control Relay.app"
SUBMISSION_ZIP="${ARTIFACT_ROOT}/Media-Control-Relay-submission.zip"
FINAL_ZIP="${ARTIFACT_ROOT}/Media-Control-Relay-notarized.zip"

test "$(git rev-parse HEAD)" = "${EXPECTED_COMMIT}"
test -z "$(git status --porcelain)"
mkdir -p "${ARTIFACT_ROOT}/rollback"

HAS_ROLLBACK=false
if [ -d "/Applications/Media Control Relay.app" ]; then
  rm -rf "${ROLLBACK_APP}"
  ditto "/Applications/Media Control Relay.app" "${ROLLBACK_APP}"
  codesign --verify --deep --strict --verbose=2 "${ROLLBACK_APP}"
  ACTUAL_ROLLBACK_SHA256="$(
    shasum -a 256 \
      "${ROLLBACK_APP}/Contents/MacOS/Media Control Relay" |
      awk '{print $1}'
  )"
  test "${ACTUAL_ROLLBACK_SHA256}" = "${ROLLBACK_EXECUTABLE_SHA256}"
  HAS_ROLLBACK=true
fi
```

The rollback copy is mandatory for an update qualification because it preserves
the exact previously accepted installation. A genuinely clean installation may
set `HAS_ROLLBACK=false`; it must not borrow a designated requirement or claim a
rollback rehearsal.

## Archive and Sign

Create an unsigned archive, then sign the archived product explicitly:

```bash
xcodebuild \
  -project MediaControlRelay.xcodeproj \
  -scheme MediaControlRelay \
  -configuration Release \
  -archivePath "${ARCHIVE}" \
  CODE_SIGNING_ALLOWED=NO \
  archive

if [ "${HAS_ROLLBACK}" = true ]; then
  DESIGNATED_REQUIREMENT="$(
    codesign -d -r- "${ROLLBACK_APP}" 2>&1 |
      sed -n 's/^designated => //p'
  )"
  test -n "${DESIGNATED_REQUIREMENT}"
  [[ "${DESIGNATED_REQUIREMENT}" == *"anchor apple generic"* ]]
  [[ "${DESIGNATED_REQUIREMENT}" == *"identifier \"${EXPECTED_BUNDLE_ID}\""* ]]
  [[ "${DESIGNATED_REQUIREMENT}" == *"certificate leaf[subject.OU]"* ]]
  [[ "${DESIGNATED_REQUIREMENT}" != *"cdhash"* ]]
fi

if [ "${HAS_ROLLBACK}" = true ]; then
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements Config/MediaControlRelay.entitlements \
    --requirements "=designated => ${DESIGNATED_REQUIREMENT}" \
    --sign "${IDENTITY}" \
    "${APP}"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements Config/MediaControlRelay.entitlements \
    --sign "${IDENTITY}" \
    "${APP}"
fi

if [ "${HAS_ROLLBACK}" = true ]; then
  codesign --verify \
    --strict \
    --test-requirement "=${DESIGNATED_REQUIREMENT}" \
    "${APP}"
fi
```

Preserving the prior designated requirement avoids turning a local-alpha update
into a new macOS privacy identity. A clean installation without an accepted
predecessor should use the normal Developer ID requirement generated by
`codesign` instead of borrowing an unrelated app requirement.

Verify identity, runtime, entitlements, architecture, version, and Gatekeeper
before submission:

```bash
codesign --verify --deep --strict --verbose=2 "${APP}"

ENTITLEMENTS_JSON="$(
  codesign -d --entitlements - --xml "${APP}" 2>/dev/null |
    plutil -convert json -o - -
)"
test "$(jq -r 'length' <<< "${ENTITLEMENTS_JSON}")" -eq 0

SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "${APP}" 2>&1)"
grep -Fq "Authority=${IDENTITY}" <<< "${SIGNATURE_DETAILS}"
grep -Eq 'flags=.*runtime' <<< "${SIGNATURE_DETAILS}"

lipo "${APP}/Contents/MacOS/Media Control Relay" \
  -verify_arch x86_64
lipo "${APP}/Contents/MacOS/Media Control Relay" \
  -verify_arch arm64
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "${APP}/Contents/Info.plist")" = "${EXPECTED_BUNDLE_ID}"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "${APP}/Contents/Info.plist")" = "${EXPECTED_VERSION}"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "${APP}/Contents/Info.plist")" = "${EXPECTED_BUILD}"

spctl --assess --type execute --verbose=4 "${APP}" || true
```

The pre-notarization Gatekeeper result is advisory. Depending on local policy
and quarantine state, it may accept the app as Developer ID or reject it as
Unnotarized Developer ID. Only the post-stapling quarantine check is the
notarization acceptance gate.

## Submit and Staple

Create the submission archive and wait for Apple's terminal result:

```bash
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${SUBMISSION_ZIP}"

set +e
xcrun notarytool submit "${SUBMISSION_ZIP}" \
  --keychain-profile "${PROFILE}" \
  --wait \
  --timeout 1h \
  --output-format json \
  > "${ARTIFACT_ROOT}/notary-submit.json"
SUBMIT_EXIT=$?
set -e

test -s "${ARTIFACT_ROOT}/notary-submit.json"
SUBMISSION_ID="$(jq -er '.id' "${ARTIFACT_ROOT}/notary-submit.json")"
SUBMISSION_STATUS="$(jq -er '.status' "${ARTIFACT_ROOT}/notary-submit.json")"

if [ "${SUBMISSION_STATUS}" != "Accepted" ]; then
  xcrun notarytool info "${SUBMISSION_ID}" \
    --keychain-profile "${PROFILE}" \
    --output-format json \
    > "${ARTIFACT_ROOT}/notary-info.json" || true
  xcrun notarytool log "${SUBMISSION_ID}" \
    --keychain-profile "${PROFILE}" \
    --output-format json \
    > "${ARTIFACT_ROOT}/notary-log.json" || true
  exit 1
fi

test "${SUBMIT_EXIT}" -eq 0

xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"
spctl --assess --type execute --verbose=4 "${APP}"
```

After stapling, Gatekeeper must report `source=Notarized Developer ID`.

Package the stapled app, not the original submission ZIP, as the final artifact:

```bash
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${FINAL_ZIP}"

NOTARIZED_EXECUTABLE_SHA256="$(
  shasum -a 256 "${APP}/Contents/MacOS/Media Control Relay" | awk '{print $1}'
)"
FINAL_ZIP_SHA256="$(shasum -a 256 "${FINAL_ZIP}" | awk '{print $1}')"

printf 'notarized_executable_sha256=%s\n' "${NOTARIZED_EXECUTABLE_SHA256}"
printf 'notarized_zip_sha256=%s\n' "${FINAL_ZIP_SHA256}"

```

## Quarantine Verification

Validate a fresh extraction with a quarantine attribute so the check exercises
the download-style Gatekeeper path:

```bash
QUARANTINE_ROOT="${ARTIFACT_ROOT}/quarantine-test"
rm -rf "${QUARANTINE_ROOT}"
mkdir -p "${QUARANTINE_ROOT}"
ditto -x -k "${FINAL_ZIP}" "${QUARANTINE_ROOT}"

EXTRACTED_APP="${QUARANTINE_ROOT}/Media Control Relay.app"
QUARANTINE_TIME="$(printf '%x' "$(date +%s)")"
xattr -w -r com.apple.quarantine \
  "0083;${QUARANTINE_TIME};MediaControlRelay;" \
  "${EXTRACTED_APP}"

xcrun stapler validate "${EXTRACTED_APP}"
codesign --verify --deep --strict --verbose=2 "${EXTRACTED_APP}"
spctl --assess --type execute --verbose=4 "${EXTRACTED_APP}"
```

For explicit offline proof, run the following only during a dedicated
verification window. Disconnect wired adapters and VPNs before the default-route
assertion. If taking the machine offline is not practical, record that this
check was not run and do not claim offline Gatekeeper evidence.

```bash
WIFI_DEVICE="$(
  networksetup -listallhardwareports |
    awk '/Hardware Port: (Wi-Fi|AirPort)/ {
      getline
      sub(/^Device: /, "")
      print
      exit
    }'
)"
WIFI_WAS_ON=false

restore_wifi() {
  if [ "${WIFI_WAS_ON}" = true ]; then
    networksetup -setairportpower "${WIFI_DEVICE}" on
  fi
}
trap restore_wifi EXIT

if [ -n "${WIFI_DEVICE}" ] &&
  networksetup -getairportpower "${WIFI_DEVICE}" | grep -q ': On$'; then
  WIFI_WAS_ON=true
  networksetup -setairportpower "${WIFI_DEVICE}" off
fi

if route -n get default >/dev/null 2>&1; then
  echo "A default route remains; disconnect wired or VPN networking." >&2
  exit 1
fi

spctl --assess --type execute --verbose=4 "${EXTRACTED_APP}"
restore_wifi
trap - EXIT
```

## Install and Rehearse Rollback

Stop the running app before each replacement. Install the notarized app, launch
it, restore the rollback app once, and finally reinstall the notarized app:

```bash
INSTALLED_APP="/Applications/Media Control Relay.app"
PRODUCT_PROCESS_PATTERN='^/Applications/Media Control Relay\.app/'
PRODUCT_PROCESS_PATTERN+='Contents/MacOS/Media Control Relay([[:space:]].*)?$'
PROBE_PROCESS_PATTERN='^/Applications/Media Control Relay Sandbox Probe\.app/'
PROBE_PROCESS_PATTERN+='Contents/MacOS/Media Control Relay([[:space:]].*)?$'
FRONTMOST_SCRIPT='tell application "System Events" to get name of first '
FRONTMOST_SCRIPT+='application process whose frontmost is true'
FRONTMOST_BEFORE="$(osascript -e "${FRONTMOST_SCRIPT}")"

assert_probe_stopped() {
  if pgrep -f "${PROBE_PROCESS_PATTERN}" >/dev/null; then
    echo "The retired sandbox probe is running; stop it before continuing." >&2
    return 1
  fi
}

assert_probe_stopped

stop_app() {
  pkill -f "${PRODUCT_PROCESS_PATTERN}" || true
  for _ in 1 2 3 4 5; do
    if ! pgrep -f "${PRODUCT_PROCESS_PATTERN}" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

install_and_launch() {
  local source_app="$1"
  local expected_hash="$2"
  local require_ticket="$3"
  local actual_hash

  codesign --verify --deep --strict --verbose=2 "${source_app}"
  if [ "${require_ticket}" = true ]; then
    xcrun stapler validate "${source_app}"
  fi
  actual_hash="$(
    shasum -a 256 \
      "${source_app}/Contents/MacOS/Media Control Relay" |
      awk '{print $1}'
  )"
  test "${actual_hash}" = "${expected_hash}"

  stop_app
  rm -rf "${INSTALLED_APP}"
  ditto "${source_app}" "${INSTALLED_APP}"
  codesign --verify --deep --strict --verbose=2 "${INSTALLED_APP}"
  spctl --assess --type execute --verbose=4 "${INSTALLED_APP}"
  if [ "${require_ticket}" = true ]; then
    xcrun stapler validate "${INSTALLED_APP}"
  fi
  open "${INSTALLED_APP}"

  for _ in 1 2 3 4 5; do
    if pgrep -f "${PRODUCT_PROCESS_PATTERN}" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

install_and_launch \
  "${APP}" \
  "${NOTARIZED_EXECUTABLE_SHA256}" \
  true

if [ "${HAS_ROLLBACK}" = true ]; then
  install_and_launch \
    "${ROLLBACK_APP}" \
    "${ROLLBACK_EXECUTABLE_SHA256}" \
    false
  install_and_launch \
    "${APP}" \
    "${NOTARIZED_EXECUTABLE_SHA256}" \
    true
fi

FRONTMOST_AFTER="$(osascript -e "${FRONTMOST_SCRIPT}")"
test "${FRONTMOST_BEFORE}" = "${FRONTMOST_AFTER}"
assert_probe_stopped
pgrep -f "${PRODUCT_PROCESS_PATTERN}" >/dev/null
```

At each stage, verify the expected executable hash, strict signature, Gatekeeper
source, running process, and frontmost-application preservation. The stale
suppression probe identified during issue #41 investigation must remain stopped;
it is not a product component. Keep the rollback artifact until local cutover
issue #8 is accepted.

## Failure Handling

- If submission times out, Apple's service continues processing. Read status
  later with the local submission ID and the same Keychain profile.
- If Apple rejects the submission, save `notarytool log` output only in the
  private artifact directory. Summarize issue codes and affected bundle paths;
  do not post the raw response publicly.
- Do not use `--force` to bypass notarytool preflight failures without a reviewed
  root-cause decision.
- Do not rotate, copy, or print credential values as part of troubleshooting.

## Public-Safe Evidence

Issue or pull-request evidence may include the reviewed commit, app version,
build number, architecture, signing class, hardened-runtime state, entitlement
summary, artifact hashes, Accepted status, staple validation, Gatekeeper source,
and rollback result. Exclude credentials, issuer and team identifiers,
submission IDs, raw Apple payloads, device identifiers, and absolute local
paths.
