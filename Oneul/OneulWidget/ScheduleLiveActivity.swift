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
                .activityBackgroundTint(Color.black.opacity(0.33))
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        Label(currentOrNextTitle(context.state, at: timeline.date), systemImage: "calendar")
                            .font(.caption).bold()
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .padding(.leading, 8)            // 둥근 코너에 안 잘리게
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        countdownText(context.state, at: timeline.date)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.trailing, 8)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        VStack(spacing: 6) {
                            WidgetTimelineBar(segments: context.state.segments, height: 12)
                            if let line = nextLine(context.state, at: timeline.date) {
                                Text(line).font(.caption2).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 8)             // 좌우 코너 여백
                    }
                }
            } compactLeading: {
                Image(systemName: "calendar")
                    .foregroundStyle(.white)
            } compactTrailing: {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    countdownText(context.state, at: timeline.date)
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            } minimal: {
                Circle()
                    .fill(EventPalette.color(0))
                    .frame(width: 10, height: 10)
            }
            .widgetURL(URL(string: "oneul://today"))
        }
    }

    // MARK: 헬퍼
    private func currentOrNextTitle(_ s: ScheduleActivityAttributes.ContentState, at now: Date) -> String {
        let status = s.glanceStatus(at: now)
        return status.current?.title ?? status.next?.title ?? L("오늘 일정", "Today", s.isEnglish)
    }

    private func nextLine(_ s: ScheduleActivityAttributes.ContentState, at now: Date) -> String? {
        guard let next = s.glanceStatus(at: now).next else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: s.isEnglish ? "en_US" : "ko_KR"); f.dateFormat = "a h:mm"
        return L("다음", "Next", s.isEnglish) + " · \(next.title) \(f.string(from: next.start))"
    }

    // 진행 중이면 끝까지, 대기 중이면 다음 일정까지 — 거친 표기(초 없음, Activity 갱신 시점 기준).
    @ViewBuilder
    private func countdownText(_ s: ScheduleActivityAttributes.ContentState, at now: Date) -> some View {
        let status = s.glanceStatus(at: now)
        if let current = status.current {
            Text(remainingLabel(to: current.end, english: s.isEnglish, now: now))
        } else if let next = status.next {
            Text(remainingLabel(to: next.start, english: s.isEnglish, now: now))
        } else if s.segments.isEmpty {
            Text(L("일정 없음", "Free", s.isEnglish))
        } else {
            Text(L("오늘 끝", "Done", s.isEnglish))
        }
    }
}

/// 잠금화면에 뜨는 카드 본문.
struct LockScreenView: View {
    let attributes: ScheduleActivityAttributes
    let state: ScheduleActivityAttributes.ContentState
    private var en: Bool { state.isEnglish }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            content(at: timeline.date)
        }
    }

    private func content(at now: Date) -> some View {
        let status = state.glanceStatus(at: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("오늘 일정", "Today", en), systemImage: "calendar")
                    .font(.caption).bold().foregroundStyle(.white)
                Spacer()
                countdown(status, at: now)
            }
            WidgetTimelineBar(segments: state.segments, height: 18)   // 목업 확정값 — 바 두껍게, 진행 바 제거
            Text(L("현재", "Now", en) + " · " + (status.current?.title ?? L("진행 중인 일정 없음", "No active event", en)))
                .font(.subheadline).bold().foregroundStyle(.white)
            if let next = status.next {
                Text(L("다음", "Next", en) + " · \(next.title) \(timeString(next.start))")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func countdown(_ status: GlanceStatus, at now: Date) -> some View {
        if let current = status.current {
            Text(L("남은 ", "ends in ", en) + remainingLabel(to: current.end, english: en, now: now))
                .font(.caption).bold().foregroundStyle(.white)
        } else if let next = status.next {
            Text(L("다음까지 ", "in ", en) + remainingLabel(to: next.start, english: en, now: now))
                .font(.caption).bold().foregroundStyle(.white)
        } else if state.segments.isEmpty {
            Text(L("일정 없음", "Free", en)).font(.caption).bold().foregroundStyle(.white.opacity(0.7))
        } else {
            Text(L("오늘 끝", "Done", en)).font(.caption).bold().foregroundStyle(.white.opacity(0.7))
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: en ? "en_US" : "ko_KR"); f.dateFormat = "a h:mm"
        return f.string(from: date)
    }
}
