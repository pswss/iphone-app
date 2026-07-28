#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

day_grid="Oneul/Features/Today/DayGridView.swift"
editor="Oneul/Features/Editor/EventEditorView.swift"
calendar="Oneul/Features/Today/CalendarBar.swift"
language="Oneul/Design/AppChrome.swift"
today="Oneul/Features/Today/TodayView.swift"

require() {
    rg -Fq "$2" "$1" || { echo "FAIL: missing $2 in $1"; exit 1; }
}

for action in 수정 잘라내기 복사 복제 삭제; do
    require "$day_grid" ".accessibilityAction(named: lang.tr(\"$action\"))"
    require "$today" ".accessibilityAction(named: lang.tr(\"$action\"))"
done
require "$day_grid" ".accessibilityAction(named: slotActionLabel(hourStart))"
require "$day_grid" ".accessibilityAction(named: slotActionLabel(halfHour))"
require "$editor" ".accessibilityLabel(lang.weekdayName(wd))"
require "$calendar" "lang.weekdayShort(cal.component(.weekday, from: date))"
require "$language" '"%@에 붙여넣기": "Paste at %@"'

if rg -Fq '["S", "M", "T", "W", "T", "F", "S"]' "$editor" "$calendar"; then
    echo "FAIL: ambiguous English weekday initials returned"
    exit 1
fi
if rg -Fq ".weekday(.narrow)" "$calendar"; then
    echo "FAIL: ambiguous narrow weekday formatting returned"
    exit 1
fi
if rg -Fq "eventDots" "$calendar"; then
    echo "FAIL: month-calendar event dots returned"
    exit 1
fi

echo "PASS: clipboard accessibility actions and weekday labels"
