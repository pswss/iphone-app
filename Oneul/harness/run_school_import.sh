#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
xcrun swiftc -parse-as-library -sdk "$sdk" -target arm64-apple-macos26.0 \
  -load-plugin-library "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftDataMacros.dylib" \
  Oneul/Models/ScheduleEvent.swift Oneul/Features/School/NEIS.swift harness/SchoolImportHarness.swift \
  -o "$out/school-import"
TZ=Asia/Seoul "$out/school-import"
