import SwiftUI
import WidgetKit
import ActivityKit

/// 남은 시간 거친 표기: 1시간 이상 → "n시간", 1시간 미만 → "n분", 1분 미만 → "< 1분".
/// (초 단위는 표시하지 않음. 값은 Activity 갱신 시점 기준.)
func remainingLabel(to target: Date) -> String {
    let secs = target.timeIntervalSince(Date())
    if secs <= 0 { return "곧" }
    let mins = Int(secs) / 60
    if mins < 1 { return "< 1분" }
    if mins < 60 { return "\(mins)분" }
    return "\(Int(secs) / 3600)시간"
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
        s.currentTitle ?? s.nextTitle ?? "오늘 일정"
    }

    private func nextLine(_ s: ScheduleActivityAttributes.ContentState) -> String? {
        guard let title = s.nextTitle, let start = s.nextStart else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "a h:mm"
        return "다음 · \(title) \(f.string(from: start))"
    }

    @ViewBuilder
    private func countdownText(_ s: ScheduleActivityAttributes.ContentState) -> some View {
        if s.currentTitle != nil {
            Text("진행 중")                                   // 진행 중이면 남은 시간 대신 '진행 중'
        } else if let start = s.nextStart, start > .now {
            Text(remainingLabel(to: start))                 // 다음 일정까지 거친 표기(초 없음)
        } else {
            Text("오늘 끝")
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
                Label("오늘 일정", systemImage: "calendar")
                    .font(.caption).bold().foregroundStyle(.white)
                Spacer()
                countdown
            }
            WidgetTimelineBar(state: state)
            Text("현재 일정 · \(state.currentTitle ?? "진행 중인 일정 없음")")
                .font(.subheadline).bold().foregroundStyle(.white)
            if let title = state.nextTitle, let start = state.nextStart {
                Text("다음 · \(title) \(timeString(start))")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if state.currentTitle != nil {
            Text("진행 중")
                .font(.caption).bold().foregroundStyle(.white)
        } else if let start = state.nextStart, start > .now {
            Text("다음까지 \(remainingLabel(to: start))")
                .font(.caption).bold().foregroundStyle(.white)
        } else {
            Text("오늘 끝").font(.caption).bold().foregroundStyle(.white.opacity(0.7))
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "a h:mm"
        return f.string(from: date)
    }
}
