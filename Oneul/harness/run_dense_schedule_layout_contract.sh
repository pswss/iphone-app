#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

day="Oneul/Features/Today/DayGridView.swift"
week="Oneul/Features/Today/TodayView.swift"
language="Oneul/Design/AppChrome.swift"

require() {
    rg -Fq "$2" "$1" || { echo "FAIL: missing $2 in $1"; exit 1; }
}

require "$day" 'private let minimumEventTarget: CGFloat = 44'
require "$day" 'private let maxVisibleColumns = 3'
require "$day" 'let visibleColumns = max(1, min(maxVisibleColumns,'
require "$day" 'ForEach(layout.overflows) { overflowBlock($0, gridW: gridW) }'
require "$day" 'return Menu {'
require "$day" 'lang.tr("%d개 일정 더 보기")'
require "$day" 'if $0.start != $1.start { return $0.start < $1.start }'
require "$language" '"%d개 일정 더 보기": "Show %d more events"'

preview="$(awk '/private func previewBlock/{found = 1} found {print} found && /\/\/ MARK: 일정 블록/ {exit}' "$day")"
[[ "$preview" == *'.font(.caption2)'* && "$preview" != *'.font(.system(size: 10))'* ]] || {
    echo "FAIL: preview time is not Dynamic Type aware"
    exit 1
}

day_all_day="$(awk '/private var allDayRow/{found = 1} found {print} found && /\/\/ MARK: 시간선/ {exit}' "$day")"
[[ "$day_all_day" == *'.frame(minHeight: minimumEventTarget)'* ]] || {
    echo "FAIL: day all-day controls have no 44pt target"
    exit 1
}

require "$week" 'private let minColW: CGFloat = 52'
require "$week" 'private var barTargetH: CGFloat {'
require "$week" 'private var barRowStride: CGFloat { barTargetH + barVGap }'
require "$week" '.frame(maxWidth: .infinity, minHeight: barTargetH, maxHeight: barTargetH)'
nav="$(awk '/private var macDayNav/{found = 1} found {print} found && /\/\/\/ 한 주/ {exit}' "$week")"
[[ "$(printf '%s' "$nav" | rg -Fc '.frame(width: 44, height: 44)')" -eq 2 && "$nav" == *'.frame(minHeight: 44)'* ]] || {
    echo "FAIL: week navigation controls have no 44pt targets"
    exit 1
}

echo "PASS: bounded dense events, 44pt all-day targets, and scalable preview time"
