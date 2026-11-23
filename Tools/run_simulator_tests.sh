#!/bin/bash
# Build the simulator host without a development team, ad-hoc sign it so Keychain works,
# then run one test bundle. A skipped Keychain test fails the process.
# application-identifier must be -.com.truckorig; a bare bundle id is rejected by launchd.
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
LOG="$RESULT.log"
mkdir -p "$(dirname "$RESULT")"
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

CODESIGN_HELP="$(codesign --help 2>&1 || true)"
sign_item() {
  local item="$1"
  local entitlements="${2:-}"
  if [[ -n "$entitlements" ]]; then
    if [[ "$CODESIGN_HELP" == *generate-entitlement-der* ]]; then
      codesign --force --sign - --timestamp=none --generate-entitlement-der \
        --entitlements "$entitlements" "$item"
    else
      codesign --force --sign - --timestamp=none --entitlements "$entitlements" "$item"
    fi
  else
    codesign --force --sign - --timestamp=none "$item"
  fi
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
  case "$(basename "$appex")" in
    TruckoRigWidget.appex) sign_item "$appex" "$ROOT/TruckoRigWidget/TruckoRigWidget.entitlements" ;;
    TruckoRigShare.appex) sign_item "$appex" "$ROOT/TruckoRigShare/TruckoRigShare.entitlements" ;;
    *) sign_item "$appex" ;;
  esac
done < <(find "$APP" -type d -name '*.appex')

sign_item "$APP" "$HOST_ENTITLEMENTS"

while IFS= read -r xctest; do
  [[ -z "$xctest" ]] && continue
  sign_item "$xctest"
done < <(find "$DERIVED/Build/Products" -type d -path '*Debug-iphonesimulator/*.xctest')

echo "Signed host entitlements:"
codesign -d --entitlements :- "$APP" > "$DERIVED/host-entitlements.plist"
cat "$DERIVED/host-entitlements.plist"
grep -q "keychain-access-groups" "$DERIVED/host-entitlements.plist"

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
