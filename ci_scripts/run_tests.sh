#!/usr/bin/env bash
set -euo pipefail

APP_SCHEME="${APP_SCHEME:-Podcastr}"
PROJECT_PATH="${PROJECT_PATH:-Podcastr.xcodeproj}"

# Resolve the simulator at runtime instead of hardcoding a device name.
# History: the hardcoded name has broken CI twice (iPhone 16 deleted from the
# runner, then iPhone 17 never existed on it). Preference order:
#   1. explicit $TEST_DESTINATION (caller override, unchanged contract)
#   2. a simulator whose name ends in " ci" (the runner's purpose-built sim)
#   3. any available iPhone simulator
if [ -z "${TEST_DESTINATION:-}" ]; then
  available="$(xcrun simctl list devices available)"
  udid="$(printf '%s\n' "$available" | sed -n 's/.* ci (\([0-9A-F-]\{36\}\)) .*/\1/p' | head -1)"
  if [ -z "$udid" ]; then
    udid="$(printf '%s\n' "$available" | sed -n 's/^ *iPhone[^(]*(\([0-9A-F-]\{36\}\)) .*/\1/p' | head -1)"
  fi
  if [ -z "$udid" ]; then
    echo "error: no available iPhone simulator on this runner" >&2
    xcrun simctl list devices available >&2
    exit 70
  fi
  TEST_DESTINATION="platform=iOS Simulator,id=$udid"
fi
echo "Using test destination: $TEST_DESTINATION"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$APP_SCHEME" \
  -destination "$TEST_DESTINATION" \
  -skipPackagePluginValidation \
  test
