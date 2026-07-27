#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

view="OneulWatch/WatchTodayView.swift"
for required in \
    "TimelineView(.everyMinute)" \
    "p.events.glanceStatus(at: now)" \
    ".navigationTitle(dayTitle)" \
    'p.dayLabel.isEmpty ? (en ? "Today" : "오늘") : p.dayLabel'; do
    rg -Fq "$required" "$view" || { echo "FAIL: missing $required"; exit 1; }
done

if rg -q 'p\.(currentTitle|nextTitle|currentEnd|nextStart)' "$view"; then
    echo "FAIL: Watch view returned to sync-time current/next fields"
    exit 1
fi

out="$(mktemp -d)/remaining_time_harness"
xcrun swiftc -parse-as-library \
    Shared/AppConfig.swift Shared/ScheduleAttributes.swift harness/RemainingTimeHarness.swift \
    -o "$out"
"$out"
echo "PASS: Watch status and day-label contract"
