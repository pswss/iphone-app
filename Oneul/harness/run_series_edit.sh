#!/bin/bash
# 반복 시리즈 편집 톰스톤 하네스 실행 (SwiftData 매크로 플러그인 필요 → Xcode-beta 툴체인)
set -e
cd "$(dirname "$0")/.."
DEV=/Applications/Xcode-beta.app/Contents/Developer
OUT=$(mktemp -d)/series_edit_harness
DEVELOPER_DIR=/Applications/Xcode-beta.app xcrun swiftc -parse-as-library \
  -sdk "$DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
  -target arm64-apple-macos26.0 \
  -load-plugin-library "$DEV/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftDataMacros.dylib" \
  Oneul/Models/ScheduleEvent.swift harness/SeriesEditHarness.swift -o "$OUT"
TZ=Asia/Seoul "$OUT"
