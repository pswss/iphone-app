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
        // 현재/다음 일정·진행 바가 갱신돼야 하는 시점 = 각 일정의 시작·끝. (최대 30개)
        var marks: [Date] = [now]
        for s in snap?.segments ?? [] {
            if s.start > now { marks.append(s.start) }
            if s.end > now { marks.append(s.end) }
        }
        marks = Array(Set(marks)).sorted().prefix(30).map { $0 }
        let entries = marks.map { HomeEntry(date: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct OneulHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OneulHomeWidget", provider: HomeProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.black.opacity(0.85) }
        }
        .configurationDisplayName("오늘 타임라인")
        .description("오늘 일정과 진행 상황을 한눈에 봅니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HomeWidgetView: View {
    var entry: HomeEntry
    @Environment(\.widgetFamily) private var family

    private var snap: HomeSnapshot? { entry.snapshot }
    private var small: Bool { family == .systemSmall }

    var body: some View {
        if let snap, !snap.segments.isEmpty {
            VStack(alignment: .leading, spacing: small ? 6 : 8) {
                HStack {
                    Text(snap.dayLabel)
                        .font(.caption2).bold().foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    countdown(snap)
                }
                WidgetTimelineBar(state: contentState(snap), height: small ? 12 : 16)
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

    /// HomeSnapshot → WidgetTimelineBar가 쓰는 ContentState (바 뷰 재사용).
    private func contentState(_ s: HomeSnapshot) -> ScheduleActivityAttributes.ContentState {
        .init(dayStart: s.dayStart, dayEnd: s.dayEnd, segments: s.segments,
              currentTitle: s.currentTitle, currentEnd: s.currentEnd,
              nextTitle: s.nextTitle, nextStart: s.nextStart, isEnglish: s.isEnglish)
    }

    private func statusLine(_ s: HomeSnapshot) -> String {
        if let cur = s.currentTitle { return L("현재", "Now", s.isEnglish) + " · " + cur }
        if s.nextTitle != nil { return L("대기 중", "Waiting", s.isEnglish) }
        return L("오늘 일정 종료", "All done", s.isEnglish)
    }

    private func nextLine(_ s: HomeSnapshot) -> String? {
        guard let title = s.nextTitle, let start = s.nextStart else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: s.isEnglish ? "en_US" : "ko_KR")
        f.dateFormat = "a h:mm"
        return L("다음", "Next", s.isEnglish) + " · \(title) \(f.string(from: start))"
    }

    @ViewBuilder
    private func countdown(_ s: HomeSnapshot) -> some View {
        if s.currentTitle != nil {
            Text(L("진행 중", "Now", s.isEnglish)).font(.caption2).bold().foregroundStyle(.white)
        } else if let start = s.nextStart, start > .now {
            Text(remainingLabel(to: start, english: s.isEnglish))
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
        .configurationDisplayName("오늘 일정 (잠금화면)")
        .description("잠금화면·StandBy에 현재/다음 일정을 표시합니다.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct LockAccessoryView: View {
    var entry: HomeEntry
    @Environment(\.widgetFamily) private var family
    private var snap: HomeSnapshot? { entry.snapshot }
    private var en: Bool { snap?.isEnglish ?? false }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label(inlineText, systemImage: "calendar")

        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "calendar")
            } currentValueLabel: {
                Text("\(Int(progress * 100))")
            }
            .gaugeStyle(.accessoryCircularCapacity)

        default:   // accessoryRectangular
            VStack(alignment: .leading, spacing: 1) {
                Text(snap?.dayLabel ?? L("오늘", "Today", en))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(statusText).font(.caption).bold().lineLimit(1)
                if let n = nextText { Text(n).font(.caption2).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 하루 일정 진행률(0…1) — 무지개 바 바늘과 동일한 packed 기준.
    private var progress: Double {
        guard let snap else { return 0 }
        let single = snap.segments.filter { !$0.isMultiDay }
        return PackedLayout(intervals: single.map { (start: $0.start, end: $0.end) }).fraction(at: Date())
    }

    private var inlineText: String {
        guard let snap, !snap.segments.isEmpty else { return L("일정 없음", "No events", en) }
        if let cur = snap.currentTitle { return L("현재", "Now", en) + " · " + cur }
        if let title = snap.nextTitle, let start = snap.nextStart {
            return L("다음", "Next", en) + " · \(title) " + remainingLabel(to: start, english: en)
        }
        return L("오늘 일정 종료", "All done", en)
    }

    private var statusText: String {
        guard let snap, !snap.segments.isEmpty else { return L("오늘 일정 없음", "No events", en) }
        if let cur = snap.currentTitle { return L("현재", "Now", en) + " · " + cur }
        if snap.nextTitle != nil { return L("대기 중", "Waiting", en) }
        return L("오늘 일정 종료", "All done", en)
    }

    private var nextText: String? {
        guard let title = snap?.nextTitle, let start = snap?.nextStart else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: en ? "en_US" : "ko_KR")
        f.dateFormat = "a h:mm"
        return L("다음", "Next", en) + " · \(title) \(f.string(from: start))"
    }
}
