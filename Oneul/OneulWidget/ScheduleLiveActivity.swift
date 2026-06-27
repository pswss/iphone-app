import SwiftUI
import WidgetKit
import ActivityKit

/// 앱 언어(state.isEnglish)에 따라 한/영. 위젯은 App Group 없이도 ContentState로 언어를 전달받는다.
func L(_ ko: String, _ en: String, _ english: Bool) -> String { english ? en : ko }

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
                        .padding(.leading, 8)            // 둥근 코너에 안 잘리게
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownText(context.state)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        WidgetTimelineBar(state: context.state, height: 12)
                        if let line = nextLine(context.state) {
                            Text(line).font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 8)             // 좌우 코너 여백
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
        s.currentTitle ?? s.nextTitle ?? L("오늘 일정", "Today", s.isEnglish)
    }

    private func nextLine(_ s: ScheduleActivityAttributes.ContentState) -> String? {
        guard let title = s.nextTitle, let start = s.nextStart else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: s.isEnglish ? "en_US" : "ko_KR"); f.dateFormat = "a h:mm"
        return L("다음", "Next", s.isEnglish) + " · \(title) \(f.string(from: start))"
    }

    // 진행 중이면 끝까지, 아니면 다음 일정까지 — 자동으로 흐르는 카운트다운(앱 안 열어도 갱신).
    @ViewBuilder
    private func countdownText(_ s: ScheduleActivityAttributes.ContentState) -> some View {
        if s.currentTitle != nil, let end = s.currentEnd, end > .now {
            liveTimer(to: end)
        } else if let start = s.nextStart, start > .now {
            liveTimer(to: start)
        } else {
            Text(L("오늘 끝", "Done", s.isEnglish))
        }
    }
}

/// 시스템이 1초마다 자동 갱신하는 카운트다운 텍스트(콘텐츠 푸시 없이 흐름).
@ViewBuilder
func liveTimer(to date: Date) -> some View {
    Text(timerInterval: min(Date(), date)...date, countsDown: true).monospacedDigit()
}

/// 잠금화면에 뜨는 카드 본문.
struct LockScreenView: View {
    let attributes: ScheduleActivityAttributes
    let state: ScheduleActivityAttributes.ContentState
    private var en: Bool { state.isEnglish }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("오늘 일정", "Today", en), systemImage: "calendar")
                    .font(.caption).bold().foregroundStyle(.white)
                Spacer()
                countdown
            }
            WidgetTimelineBar(state: state)
            Text(L("현재", "Now", en) + " · " + (state.currentTitle ?? L("진행 중인 일정 없음", "No active event", en)))
                .font(.subheadline).bold().foregroundStyle(.white)
            if let title = state.nextTitle, let start = state.nextStart {
                Text(L("다음", "Next", en) + " · \(title) \(timeString(start))")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if state.currentTitle != nil, let end = state.currentEnd, end > .now {
            countLabel(L("끝까지 ", "ends in ", en), to: end)
        } else if let start = state.nextStart, start > .now {
            countLabel(L("다음까지 ", "in ", en), to: start)
        } else {
            Text(L("오늘 끝", "Done", en)).font(.caption).bold().foregroundStyle(.white.opacity(0.7))
        }
    }

    private func countLabel(_ prefix: String, to date: Date) -> some View {
        HStack(spacing: 2) {
            Text(prefix)
            liveTimer(to: date)
        }
        .font(.caption).bold().foregroundStyle(.white)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: en ? "en_US" : "ko_KR"); f.dateFormat = "a h:mm"
        return f.string(from: date)
    }
}
