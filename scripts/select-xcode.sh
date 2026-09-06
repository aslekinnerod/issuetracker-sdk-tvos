#!/usr/bin/env bash
#
# Selects the Xcode version pinned in XCODE_VERSION (set in
# .github/workflows/ci.yml) and fails loudly — listing what IS installed —
# when that version is not on the machine.
#
# Why: this SDK is distributed as source over SwiftPM, so a consumer's
# Xcode compiles it, not ours. Building on `macos-latest` with the image's
# default Xcode means the Swift compiler and tvOS SDK move without a commit
# in this repo: a new image can break a build with no change on our side,
# or start accepting code that older Xcode rejects, so "passes in CI" stops
# implying "compiles for our users".
#
# Bumping the pin is a deliberate one-line edit to XCODE_VERSION. When the
# runner image drops that version the job fails with the list of installed
# ones, which is the edit you need.
#
# CI helper: on a developer machine this will try to switch your global
# Xcode, so run it only if that is what you want.
set -euo pipefail

version=${XCODE_VERSION:?XCODE_VERSION is not set}
app="/Applications/Xcode_${version}.app"

if [ ! -d "$app" ]; then
  echo "::error::Xcode ${version} is not installed on this machine." >&2
  echo "Installed Xcode versions:" >&2
  ls -d /Applications/Xcode*.app >&2 || true
  echo "Update XCODE_VERSION in .github/workflows/ci.yml to one of the above." >&2
  exit 1
fi

if [ "$(xcode-select -p)" != "${app}/Contents/Developer" ]; then
  sudo xcode-select --switch "$app"
fi

xcodebuild -version
swift --version
