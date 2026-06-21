import SwiftUI
import WidgetKit
import ActivityKit

/// 위젯은 앱 언어 토글에 접근 못 함(App Group 불가) → 기기 언어로 한/영 분기.
func L(_ ko: String, _ en: String) -> String {
    (Locale.current.language.languageCode?.identifier == "ko") ? ko : en
}

/// 남은 시간 거친 표기: 1시간 이상 → "n시간", 1시간 미만 → "n분", 1분 미만 → "< 1분".
/// (초 단위는 표시하지 않음. 값은 Activity 갱신 시점 기준.)
func remainingLabel(to target: Date) -> String {
    let secs = target.timeIntervalSince(Date())
    if secs <= 0 { return L("곧", "soon") }
    let mins = Int(secs) / 60
    if mins < 1 { return L("< 1분", "< 1m") }
    if mins < 60 { return L("\(mins)분", "\(mins)m") }
    return L("\(Int(secs) / 3600)시간", "\(Int(secs) / 3600)h")
}

struct ScheduleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleActivityAttributes.self) { context in
            // 잠금화면 / 배너
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(14)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(currentOrNextTitle(context.state), systemImage: "calendar")
                        .font(.caption).bold()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownText(context.state)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        WidgetTimelineBar(state: context.state, height: 12)
                        if let line = nextLine(context.state) {
                            Text(line).font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 6)   // 둥근 코너에 바가 잘리지 않게 안쪽으로
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: "calendar")
                    .foregroundStyle(.white)
            } compactTrailing: {
                countdownText(context.state)
                    .font(.caption2)
                    .foregroundStyle(.white)
            } minimal: {
                Circle()
                    .fill(EventPalette.color(0))
                    .frame(width: 10, height: 10)
            }
            .widgetURL(URL(string: "oneul://today"))
        }
    }

    // MARK: 헬퍼
    private func currentOrNextTitle(_ s: ScheduleActivityAttributes.ContentState) -> String {
        s.currentTitle ?? s.nextTitle ?? L("오늘 일정", "Today")
    }

    private func nextLine(_ s: ScheduleActivityAttributes.ContentState) -> String? {
        guard let title = s.nextTitle, let start = s.nextStart else { return nil }
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "a h:mm"
        return L("다음", "Next") + " · \(title) \(f.string(from: start))"
    }

    // 진행 중인 일정이 있으면 카운트다운 대신 "진행 중", 아니면 다음 일정까지 남은 시간.
    @ViewBuilder
    private func countdownText(_ s: ScheduleActivityAttributes.ContentState) -> some View {
        if s.currentTitle != nil {
            Text(L("진행 중", "Now"))
        } else if let start = s.nextStart, start > .now {
            Text(remainingLabel(to: start))
        } else {
            Text(L("오늘 끝", "Done"))
        }
    }
}

/// 잠금화면에 뜨는 카드 본문.
struct LockScreenView: View {
    let attributes: ScheduleActivityAttributes
    let state: ScheduleActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("오늘 일정", "Today"), systemImage: "calendar")
                    .font(.caption).bold().foregroundStyle(.white)
                Spacer()
                countdown
            }
            WidgetTimelineBar(state: state)
            Text(L("현재", "Now") + " · " + (state.currentTitle ?? L("진행 중인 일정 없음", "No active event")))
                .font(.subheadline).bold().foregroundStyle(.white)
            if let title = state.nextTitle, let start = state.nextStart {
                Text(L("다음", "Next") + " · \(title) \(timeString(start))")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // 진행 중이면 "진행 중", 아니면 다음 일정까지 남은 시간.
    @ViewBuilder
    private var countdown: some View {
        if state.currentTitle != nil {
            Text(L("진행 중", "Now"))
                .font(.caption).bold().foregroundStyle(.white)
        } else if let start = state.nextStart, start > .now {
            Text(L("다음까지 ", "in ") + remainingLabel(to: start))
                .font(.caption).bold().foregroundStyle(.white)
        } else {
            Text(L("오늘 끝", "Done")).font(.caption).bold().foregroundStyle(.white.opacity(0.7))
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "a h:mm"
        return f.string(from: date)
    }
}
