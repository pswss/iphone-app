#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

view="OneulWatch/WatchTodayView.swift"
grid="Oneul/Features/Today/DayGridView.swift"
menu="Oneul/Features/Today/MenuBarTimelineView.swift"
today="Oneul/Features/Today/TodayView.swift"
home_widget="OneulWidget/OneulWidgetBundle.swift"
watch_widget="OneulWatchWidget/OneulWatchWidgetBundle.swift"
for required in \
    "TimelineView(.everyMinute)" \
    "p.isDisplayable(at: timeline.date)" \
    "p.events.glanceStatus(at: now)" \
    "Open Oneul on iPhone to refresh" \
    'p.dayLabel.isEmpty ? (en ? "Today" : "오늘") : p.dayLabel'; do
    rg -Fq "$required" "$view" || { echo "FAIL: missing $required"; exit 1; }
done

for target in "$grid" "$menu" "$today"; do
    rg -Fq "TimelineView(.everyMinute)" "$target" || { echo "FAIL: missing minute timeline in $target"; exit 1; }
done
rg -Fq "nowLine(width: width, at: timeline.date)" "$grid" || { echo "FAIL: grid current line ignores timeline date"; exit 1; }
rg -Fq "DayPlan.upcoming(events: events, now: now)" "$menu" || { echo "FAIL: menu status ignores timeline date"; exit 1; }
rg -Fq "NotificationCenter.default.publisher(for: .NSCalendarDayChanged)" "$today" || { echo "FAIL: Today does not refresh day-bound caches at midnight"; exit 1; }
if rg -q '\.(current|next)\(\)' "$today"; then
    echo "FAIL: Today returned to implicit static time"
    exit 1
fi
for target in "$home_widget" "$watch_widget"; do
    rg -Fq "snap?.timelineDates(from: now)" "$target" || { echo "FAIL: missing midnight snapshot expiry in $target"; exit 1; }
done

if rg -q 'p\.(currentTitle|nextTitle|currentEnd|nextStart)' "$view"; then
    echo "FAIL: Watch view returned to sync-time current/next fields"
    exit 1
fi

out="$(mktemp -d)/remaining_time_harness"
xcrun swiftc -parse-as-library \
    Shared/AppConfig.swift Shared/ScheduleAttributes.swift Shared/WatchPayload.swift harness/RemainingTimeHarness.swift \
    -o "$out"
"$out"
echo "PASS: open-view time and stale-snapshot contract"
