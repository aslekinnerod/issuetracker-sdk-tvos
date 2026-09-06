#!/usr/bin/env bash
#
# Prints the UDID of an available tvOS simulator on stdout, and a human
# readable description of the device it picked on stderr.
#
# Why this exists: pinning an xcodebuild destination by device name is a
# time bomb. CI used `-destination 'platform=tvOS Simulator,name=Apple TV'`,
# and modern Xcode only creates "Apple TV 4K (Nth generation)" — so that
# destination matches nothing and takes out 100% of the automated
# verification in this repo the day the runner image rolls, with no repo
# change to blame.
#
# Set TVOS_RUNTIME (e.g. TVOS_RUNTIME=17.5) to require a specific runtime;
# the script then fails if that runtime is not installed rather than
# quietly testing on a newer one. Unset, it picks the newest installed
# runtime and prints which one, so the log always states what was tested.
#
# Runs locally as well as in CI:
#   xcodebuild test -destination "id=$(scripts/tv-simulator-udid.sh)" ...
set -euo pipefail

devices_json=$(xcrun simctl list devices available --json)

if [ -n "${TVOS_RUNTIME:-}" ]; then
  wanted="SimRuntime.tvOS-${TVOS_RUNTIME//./-}"
else
  wanted=""
fi

selected=$(
  printf '%s' "$devices_json" | jq -r --arg wanted "$wanted" '
    [ .devices
      | to_entries[]
      | select(.key | test("SimRuntime\\.tvOS-"))
      | select($wanted == "" or (.key | endswith($wanted)))
      | .key as $runtime
      | .value[]
      | select(.isAvailable)
      | { runtime: $runtime, udid: .udid, name: .name }
    ]
    # Newest runtime first. Runtime keys sort lexically, which is correct
    # for every tvOS version this SDK supports (17 and up).
    | sort_by(.runtime) | reverse
    | .[0] // empty
    | "\(.udid)\t\(.name)\t\(.runtime)"
  '
)

if [ -z "$selected" ]; then
  if [ -n "$wanted" ]; then
    echo "No available tvOS simulator for runtime ${TVOS_RUNTIME}." >&2
  else
    echo "No available tvOS simulator on this machine." >&2
  fi
  echo "Installed runtimes:" >&2
  xcrun simctl list runtimes >&2
  echo "Install one with: xcodebuild -downloadPlatform tvOS" >&2
  exit 1
fi

udid=${selected%%$'\t'*}
rest=${selected#*$'\t'}
name=${rest%%$'\t'*}
runtime=${rest#*$'\t'}

echo "tvOS simulator: ${name} [${runtime}] ${udid}" >&2
printf '%s\n' "$udid"
