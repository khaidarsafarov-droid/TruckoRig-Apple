#!/bin/bash
# Build the simulator host without a development team, give it Keychain entitlements,
# then run one test bundle. A skipped Keychain test fails the process.
# The entitlements go into the __entitlements linker section, the way Xcode builds for the
# simulator. They must not go into the ad-hoc signature: macOS AMFI refuses to spawn an
# ad-hoc binary that claims keychain-access-groups ("Launchd job spawn failed", POSIX 162).
# macOS runners ship bash 3.2, so this script avoids empty arrays under `set -u`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UDID=""
DERIVED=""
RESULT=""
ONLY=""
COVERAGE=0
BUILD=1
REQUIRE_KEYCHAIN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid) UDID="$2"; shift 2 ;;
    --derived) DERIVED="$2"; shift 2 ;;
    --result) RESULT="$2"; shift 2 ;;
    --only-testing) ONLY="$2"; shift 2 ;;
    --coverage) COVERAGE=1; shift ;;
    --no-build) BUILD=0; shift ;;
    --require-keychain) REQUIRE_KEYCHAIN=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$UDID" || -z "$DERIVED" || -z "$RESULT" || -z "$ONLY" ]]; then
  echo "Usage: run_simulator_tests.sh --udid ID --derived PATH --result PATH --only-testing NAME" >&2
  exit 2
fi

HOST_ENTITLEMENTS="$ROOT/Tools/SimulatorHost.entitlements"
HOST_ENTITLEMENTS_DER="$DERIVED/SimulatorHost.entitlements.der"
LOG="$RESULT.log"
mkdir -p "$(dirname "$RESULT")" "$DERIVED"
rm -rf "$RESULT"

if [[ "$BUILD" == 1 ]]; then
  set -- xcodebuild build-for-testing \
    -project "$ROOT/TruckoRig.xcodeproj" \
    -scheme TruckoRig \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" \
    -skipPackagePluginValidation
  if [[ "$COVERAGE" == 1 ]]; then
    set -- "$@" -enableCodeCoverage YES
  fi
  set -- "$@" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-
  # Signing is off, so Xcode skips its simulated entitlements; link them in ourselves.
  set -- "$@" LD_ENTITLEMENTS_SECTION="$HOST_ENTITLEMENTS"
  if [[ -x /usr/bin/derq ]]; then
    /usr/bin/derq query -f xml -i "$HOST_ENTITLEMENTS" -o "$HOST_ENTITLEMENTS_DER" --raw
    set -- "$@" LD_ENTITLEMENTS_SECTION_DER="$HOST_ENTITLEMENTS_DER"
  fi
  "$@"
fi

APP=""
while IFS= read -r candidate; do
  APP="$candidate"
  break
done < <(find "$DERIVED/Build/Products" -type d -path '*Debug-iphonesimulator/TruckoRig.app')
XCTESTRUN=""
while IFS= read -r candidate; do
  XCTESTRUN="$candidate"
  break
done < <(find "$DERIVED/Build/Products" -name '*.xctestrun')
if [[ -z "$APP" || -z "$XCTESTRUN" ]]; then
  echo "build-for-testing did not produce TruckoRig.app" >&2
  exit 1
fi

sign_item() {
  # Plain ad-hoc signature with no entitlements, like Xcode's simulator signing.
  codesign --force --sign - --timestamp=none "$1"
}

while IFS= read -r framework; do
  [[ -z "$framework" ]] && continue
  # Re-signing XCTest/Testing with a bare ad-hoc identity breaks the test host launch.
  case "$(basename "$framework")" in
    Testing.framework|XCTest*.framework|XCT*.framework) continue ;;
  esac
  sign_item "$framework"
done < <(find "$APP" -depth -type d -name '*.framework')

while IFS= read -r appex; do
  [[ -z "$appex" ]] && continue
  sign_item "$appex"
done < <(find "$APP" -type d -name '*.appex')

sign_item "$APP"

while IFS= read -r xctest; do
  [[ -z "$xctest" ]] && continue
  sign_item "$xctest"
done < <(find "$DERIVED/Build/Products" -type d -path '*Debug-iphonesimulator/*.xctest')

HOST_BINARY="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"
echo "Host __entitlements section:"
rm -f "$DERIVED/host-entitlements.plist"
xcrun segedit "$HOST_BINARY" -extract __TEXT __entitlements "$DERIVED/host-entitlements.plist"
cat "$DERIVED/host-entitlements.plist"
if ! grep -q "keychain-access-groups" "$DERIVED/host-entitlements.plist"; then
  echo "::error::The test host has no keychain-access-groups in __entitlements" >&2
  exit 1
fi
echo "Host signature entitlements (no restricted keys allowed):"
codesign -d --entitlements - "$APP" > "$DERIVED/host-signature-entitlements.txt" 2>&1 || true
cat "$DERIVED/host-signature-entitlements.txt"
if grep -Eq "keychain-access-groups|application-identifier" "$DERIVED/host-signature-entitlements.txt"; then
  echo "::error::Restricted entitlements in the ad-hoc signature stop launchd from spawning the host" >&2
  exit 1
fi

boot_simulator() {
  # boot exits non-zero when the device is already booted.
  xcrun simctl boot "$1" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$1" -b
}

run_tests() {
  rm -rf "$RESULT"
  set -- xcodebuild test-without-building \
    -xctestrun "$XCTESTRUN" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -only-testing:"$ONLY" \
    -parallel-testing-enabled NO \
    -resultBundlePath "$RESULT"
  if [[ "$COVERAGE" == 1 ]]; then
    set -- "$@" -enableCodeCoverage YES
  fi
  "$@" 2>&1 | tee "$LOG"
}

boot_simulator "$UDID"
if ! run_tests; then
  echo "Tests failed; booting the simulator again and retrying once." >&2
  boot_simulator "$UDID"
  run_tests
fi

if [[ "$REQUIRE_KEYCHAIN" == 1 ]]; then
  python3 - "$LOG" <<'PY'
import re
import sys
log = open(sys.argv[1], encoding="utf-8", errors="replace").read()
required = [
    "testPassphraseIs32BytesStableAndStaysOnThisDevice",
    "testTokenRoundTripsInTheKeychainAndIsNotLeftBehind",
]
failed = False
if "Keychain refused the simulator host" in log:
    print("::error::Keychain test failed instead of running")
    failed = True
for name in required:
    passed = re.search(re.escape(name) + r"\]' passed", log)
    skipped = re.search(re.escape(name) + r"\]' skipped", log)
    if skipped or not passed:
        print("::error::Required Keychain test did not pass: " + name)
        failed = True
    else:
        print("Keychain test executed: " + name)
if failed:
    sys.exit(1)
PY
fi

if [[ "$COVERAGE" == 1 ]]; then
  JSON="$(mktemp)"
  xcrun xccov view --report --json "$RESULT" > "$JSON"
  python3 "$ROOT/Tools/coverage_summary.py" "$JSON"
fi
