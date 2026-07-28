#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ai="Oneul/Features/AI/AIScheduleView.swift"
app="Oneul/OneulApp.swift"
root="Oneul/RootView.swift"

mac_branch="$(awk '
    /^[[:space:]]*#if os\(iOS\)$/ && !seen { seen = 1; next }
    seen && /^[[:space:]]*#else$/ { mac = 1; next }
    mac && /^[[:space:]]*#endif$/ { exit }
    mac { print }
' "$ai")"
menu_ai="$(awk '/\/\/ AI = 메뉴바/{found = 1} found {print} found && /\.menuBarExtraStyle\(\.window\)/ {exit}' "$app")"
toolbar_ai="$(awk '/Button \{ showAIPopover = true \}/{found = 1} found {print} found && /if userType/ {exit}' "$root")"
timeline="$(awk '/MenuBarTimelineView\(\)/{found = 1} found {print} found && /\.menuBarPopIn/ {exit}' "$app")"

[[ "$mac_branch" == *"ViewThatFits(in: .vertical)"* && "$mac_branch" == *"ScrollView {"* ]] || {
    echo "FAIL: Mac AI content is not adaptively scrollable"
    exit 1
}
rg -Fq '.frame(maxHeight: 600, alignment: .top)' "$ai" || {
    echo "FAIL: Mac AI popover has no height bound"
    exit 1
}
[[ "$menu_ai" != *'.fixedSize(horizontal: false, vertical: true)'* && "$toolbar_ai" != *'.fixedSize(horizontal: false, vertical: true)'* ]] || {
    echo "FAIL: an AI host still defeats its height bound"
    exit 1
}
[[ "$timeline" == *'.fixedSize(horizontal: false, vertical: true)'* ]] || {
    echo "FAIL: the unrelated menu-bar timeline sizing changed"
    exit 1
}
if rg -q 'aiMeridiemTipShown|showMeridiemTip|더 정확하게 쓰는 팁' "$ai"; then
    echo "FAIL: automatic first-entry AI hint returned"
    exit 1
fi

echo "PASS: compact Mac AI content and bounded scroll fallback"
