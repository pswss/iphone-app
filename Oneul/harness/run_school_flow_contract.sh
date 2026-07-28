#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

school="Oneul/Features/School/SchoolSetupView.swift"
elective="Oneul/Features/School/ElectiveSetupView.swift"
neis="Oneul/Features/School/NEIS.swift"

require() {
    rg -Fq "$2" "$1" || { echo "FAIL: missing $2 in $1"; exit 1; }
}

if rg -Fq 'try? await NEISClient.shared.fetchClasses' "$school" "$neis"; then
    echo "FAIL: class lookup still collapses failure into empty data"
    exit 1
fi

require "$school" '@State private var classesLoading = true'
require "$school" '@State private var classLoadFailed = false'
require "$school" 'Button(lang.tr("다시 시도")) { Task { await loadClasses() } }'
require "$school" 'lang.tr("반 정보가 없어 번호를 직접 선택해 주세요.")'
require "$school" '.disabled(classesLoading || classLoadFailed)'
require "$neis" 'return GradeTimetable(failed: true)'
require "$neis" 'let canClassifyElectives = !classes.isEmpty'
require "$neis" 'let rawElective = canClassifyElectives'

review="$(awk '/@ViewBuilder private var reviewPhase/{found = 1} found {print} found && /private var reviewWeekdays/ {exit}' "$elective")"
[[ "$review" == *'선택과목 %d개 · 다시 고르기'* && "$review" == *'reviewing = false'* ]] || {
    echo "FAIL: elective review has no selection-preserving Back control"
    exit 1
}
[[ "$review" != *'await load()'* && "$review" != *'checked ='* ]] || {
    echo "FAIL: elective review Back resets the selected set"
    exit 1
}

echo "PASS: truthful class loading and reversible elective review"
