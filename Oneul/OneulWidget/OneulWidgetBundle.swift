import SwiftUI
import WidgetKit

@main
struct OneulWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScheduleLiveActivity()
        OneulHomeWidget()
        OneulLockWidget()
    }
}

// MARK: - 홈 화면 위젯 (오늘 타임라인)

struct HomeEntry: TimelineEntry {
    let date: Date
    let snapshot: HomeSnapshot?
}

/// App Group 공유 스냅샷을 읽어 일정 경계(시작·끝)마다 새로고침되는 타임라인을 만든다.
struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: Date(), snapshot: SharedStore.readToday())
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        completion(HomeEntry(date: Date(), snapshot: SharedStore.readToday()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let snap = SharedStore.readToday()
        let now = Date()
        let marks = snap?.timelineDates(from: now) ?? [now]
        let entries = marks.map { HomeEntry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: marks.count > 1 ? .atEnd : .never))
    }
}

/// 위젯 갤러리 문구 — 앱이 마지막으로 쓴 스냅샷의 언어 설정을 따라감(위젯은 앱 UserDefaults 접근 불가).
private func wtr(_ ko: String, _ en: String) -> String {
    (SharedStore.readToday()?.isEnglish ?? false) ? en : ko
}

struct OneulHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OneulHomeWidget", provider: HomeProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black.opacity(0.85) }
        }
        .configurationDisplayName(wtr("오늘 타임라인", "Today's Timeline"))
        .description(wtr("오늘 일정과 진행 상황을 한눈에 봅니다.", "See today's events and progress at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HomeWidgetView: View {
    var entry: HomeEntry
    @Environment(\.widgetFamily) private var family

    private var snap: HomeSnapshot? { entry.snapshot }
    private var small: Bool { family == .systemSmall }
    private var stale: Bool { snap.map { !$0.isDisplayable(at: entry.date) } ?? false }

    var body: some View {
        if stale {
            refreshState
        } else if let snap, !snap.segments.isEmpty {
            VStack(alignment: .leading, spacing: small ? 6 : 8) {
                HStack {
                    Text(snap.dayLabel)
                        .font(.caption2).bold().foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    countdown(snap)
                }
                WidgetTimelineBar(segments: snap.segments, height: small ? 12 : 16)
                Text(statusLine(snap))
                    .font(small ? .caption2 : .caption).bold()
                    .foregroundStyle(.white).lineLimit(1)
                if !small, let line = nextLine(snap) {
                    Text(line).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar").font(.title2).foregroundStyle(.white.opacity(0.6))
                Text(L("오늘 일정 없음", "No events", snap?.isEnglish ?? false))
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var refreshState: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.clockwise").font(.title2).foregroundStyle(.white.opacity(0.6))
            Text(L("Oneul을 열어 새로고침", "Open Oneul to refresh", snap?.isEnglish ?? false))
                .font(.caption).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


    private func statusLine(_ s: HomeSnapshot) -> String {
        let status = s.segments.glanceStatus(at: entry.date)
        if let current = status.current { return L("현재", "Now", s.isEnglish) + " · " + current.title }
        if status.next != nil { return L("대기 중", "Waiting", s.isEnglish) }
        return L("오늘 일정 종료", "All done", s.isEnglish)
    }

    private func nextLine(_ s: HomeSnapshot) -> String? {
        guard let next = s.segments.glanceStatus(at: entry.date).next else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: s.isEnglish ? "en_US" : "ko_KR")
        f.dateFormat = "a h:mm"
        return L("다음", "Next", s.isEnglish) + " · \(next.title) \(f.string(from: next.start))"
    }

    @ViewBuilder
    private func countdown(_ s: HomeSnapshot) -> some View {
        let status = s.segments.glanceStatus(at: entry.date)
        if status.current != nil {
            Text(L("진행 중", "Now", s.isEnglish)).font(.caption2).bold().foregroundStyle(.white)
        } else if let next = status.next {
            Text(remainingLabel(to: next.start, english: s.isEnglish, now: entry.date))
                .font(.caption2).bold().foregroundStyle(.white)
        } else {
            Text(L("끝", "Done", s.isEnglish)).font(.caption2).bold().foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - 잠금화면 / StandBy 위젯 (accessory)

struct OneulLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OneulLockWidget", provider: HomeProvider()) { entry in
            LockAccessoryView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(wtr("오늘 일정 (잠금화면)", "Today (Lock Screen)"))
        .description(wtr("잠금화면·StandBy에 현재/다음 일정을 표시합니다.", "Shows the current/next event on the Lock Screen and StandBy."))
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct LockAccessoryView: View {
    var entry: HomeEntry
    @Environment(\.widgetFamily) private var family
    private var snap: HomeSnapshot? { entry.snapshot }
    private var en: Bool { snap?.isEnglish ?? false }
    private var stale: Bool { snap.map { !$0.isDisplayable(at: entry.date) } ?? false }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(inlineText, systemImage: "calendar")

        case .accessoryCircular:
            if stale {
                Image(systemName: "arrow.clockwise")
                    .accessibilityLabel(L("Oneul을 열어 새로고침", "Open Oneul to refresh", en))
            } else {
                Gauge(value: progress) {
                    Image(systemName: "calendar")
                } currentValueLabel: {
                    Text("\(Int(progress * 100))")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            }

        default:   // accessoryRectangular
            if stale {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("새로고침 필요", "Refresh needed", en)).font(.caption).bold()
                    Text(L("Oneul을 열어주세요", "Open Oneul", en)).font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snap?.dayLabel ?? L("오늘", "Today", en))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text(statusText).font(.caption).bold().lineLimit(1)
                    if let n = nextText { Text(n).font(.caption2).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 하루 일정 진행률(0…1) — 무지개 바 바늘과 동일한 packed 기준.
    private var progress: Double {
        guard let snap else { return 0 }
        let single = snap.segments.filter { !$0.isMultiDay }
        return PackedLayout(intervals: single.map { (start: $0.start, end: $0.end) }).fraction(at: entry.date)
    }

    private var inlineText: String {
        if stale { return L("Oneul 새로고침 필요", "Open Oneul", en) }
        guard let snap, !snap.segments.isEmpty else { return L("일정 없음", "No events", en) }
        let status = snap.segments.glanceStatus(at: entry.date)
        if let current = status.current { return L("현재", "Now", en) + " · " + current.title }
        if let next = status.next {
            return L("다음", "Next", en) + " · \(next.title) "
                + remainingLabel(to: next.start, english: en, now: entry.date)
        }
        return L("오늘 일정 종료", "All done", en)
    }

    private var statusText: String {
        guard let snap, !snap.segments.isEmpty else { return L("오늘 일정 없음", "No events", en) }
        let status = snap.segments.glanceStatus(at: entry.date)
        if let current = status.current { return L("현재", "Now", en) + " · " + current.title }
        if status.next != nil { return L("대기 중", "Waiting", en) }
        return L("오늘 일정 종료", "All done", en)
    }

    private var nextText: String? {
        guard let snap, let next = snap.segments.glanceStatus(at: entry.date).next else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: en ? "en_US" : "ko_KR")
        f.dateFormat = "a h:mm"
        return L("다음", "Next", en) + " · \(next.title) \(f.string(from: next.start))"
    }
}
