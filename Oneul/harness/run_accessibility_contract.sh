#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

day_grid="Oneul/Features/Today/DayGridView.swift"
editor="Oneul/Features/Editor/EventEditorView.swift"
calendar="Oneul/Features/Today/CalendarBar.swift"
language="Oneul/Design/AppChrome.swift"
today="Oneul/Features/Today/TodayView.swift"
ai="Oneul/Features/AI/AIScheduleView.swift"
glass="Oneul/Design/Glass.swift"

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

reply="$(awk '/private struct AIReplyCard/{found = 1} found {print} found && /private struct AIResultEditView/ {exit}' "$ai")"
[[ "$reply" == *'.glassCard(cornerRadius: 22)'* ]] || {
    echo "FAIL: AI reply bypasses the shared accessibility material"
    exit 1
}
for bespoke in '.ultraThinMaterial' 'LinearGradient' 'RadialGradient' '.shadow(' 'repeatForever'; do
    [[ "$reply" != *"$bespoke"* ]] || { echo "FAIL: bespoke AI reply effect returned: $bespoke"; exit 1; }
done
require "$glass" '@Environment(\.accessibilityReduceTransparency) private var reduceTransparency'
require "$glass" '@Environment(\.colorSchemeContrast) private var contrast'
require "$glass" 'if reduceTransparency || contrast == .increased'
require "$glass" 'Color.appSystemBackground'

input="$(awk '/private var inputCard/{found = 1} found {print} found && /private var photoButton/ {exit}' "$ai")"
[[ "$input" == *'#if os(iOS)'* && "$input" == *'.textFieldStyle(.plain)'* ]] || {
    echo "FAIL: AI input styling is not platform-scoped"
    exit 1
}
[[ "$input" != *'맥 기본 파란 포커스 링 제거'* ]] || {
    echo "FAIL: Mac AI focus ring is still intentionally removed"
    exit 1
}
results="$(awk '/private var resultsSection/{found = 1} found {print} found && /private func timeText/ {exit}' "$ai")"
[[ "$results" == *'results.remove(at: idx)'* && "$results" == *'lang.tr("결과에서 제외")'* && "$results" == *'.frame(width: 44, height: 44)'* ]] || {
    echo "FAIL: AI result items cannot be individually excluded"
    exit 1
}

echo "PASS: accessible actions, focus, scalable labels, and shared AI material"
