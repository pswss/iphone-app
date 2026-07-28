#if os(macOS)
import SwiftUI
import SwiftData

/// 맥 메뉴바 타임라인 팝오버 — 오늘(비면 다가오는 날) 일정을 무지개 바 + 현재/다음으로.
struct MenuBarTimelineView: View {
    @Query(sort: \ScheduleEvent.start) private var events: [ScheduleEvent]
    private let lang = AppLanguage.shared

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            content(at: timeline.date)
        }
    }

    @ViewBuilder private func content(at now: Date) -> some View {
        let shown = DayPlan.upcoming(events: events, now: now)
        VStack(alignment: .leading, spacing: 10) {
            if let shown {
                HStack {
                    Text(shown.day, format: .dateTime.month().day().weekday(.wide).locale(lang.locale))
                        .font(.headline)
                    Spacer()
                    countdown(shown.plan, at: now)
                }
                TimelineBar(plan: shown.plan, live: Calendar.current.isDate(shown.day, inSameDayAs: now), now: now)
                statusLines(shown.plan, at: now)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                    Text(lang.tr("다가오는 일정이 없어요")).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
        }
        .padding(14)
    }

    @ViewBuilder private func countdown(_ plan: DayPlan, at now: Date) -> some View {
        if let cur = plan.current(at: now) {
            HStack(spacing: 3) {
                Text(lang.tr("남은")).font(.caption).foregroundStyle(.secondary)
                Text(timerInterval: now...max(now, cur.end), countsDown: true)
                    .font(.caption.bold()).monospacedDigit()
            }
        } else if let nxt = plan.next(at: now) {
            HStack(spacing: 3) {
                Text(lang.tr("다음까지")).font(.caption).foregroundStyle(.secondary)
                Text(timerInterval: now...max(now, nxt.start), countsDown: true)
                    .font(.caption.bold()).monospacedDigit()
            }
        }
    }

    @ViewBuilder private func statusLines(_ plan: DayPlan, at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(lang.tr("현재") + " · " + (plan.current(at: now)?.title ?? lang.tr("진행 중인 일정 없음")))
                .font(.subheadline).bold()
            if let nxt = plan.next(at: now) {
                Text(lang.tr("다음") + " · \(nxt.title) " +
                     nxt.start.formatted(.dateTime.hour().minute().locale(lang.locale)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
#endif
