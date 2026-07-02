import SwiftUI
import WidgetKit

@main
struct OneulWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        OneulComplication()
    }
}

// MARK: - 데이터 (App Group 공유 스냅샷)

struct WatchEntry: TimelineEntry {
    let date: Date
    let snapshot: HomeSnapshot?
}

/// 워치 앱이 App Group에 써둔 오늘 스냅샷을 읽어 일정 경계마다 갱신.
struct WatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: Date(), snapshot: SharedStore.readToday())
    }
    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntry(date: Date(), snapshot: SharedStore.readToday()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let snap = SharedStore.readToday()
        let now = Date()
        var marks: [Date] = [now]
        for s in snap?.segments ?? [] {
            if s.start > now { marks.append(s.start) }
            if s.end > now { marks.append(s.end) }
        }
        marks = Array(Set(marks)).sorted().prefix(30).map { $0 }
        completion(Timeline(entries: marks.map { WatchEntry(date: $0, snapshot: snap) }, policy: .atEnd))
    }
}

// MARK: - 컴플리케이션

struct OneulComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OneulComplication", provider: WatchComplicationProvider()) { entry in
            WatchComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("오늘 일정")
        .description("워치 페이스에 현재/다음 일정과 진행 상황.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct WatchComplicationView: View {
    var entry: WatchEntry
    @Environment(\.widgetFamily) private var family
    private var snap: HomeSnapshot? { entry.snapshot }
    private var en: Bool { snap?.isEnglish ?? false }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)

        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "calendar")
            }
            .gaugeStyle(.accessoryCircularCapacity)

        default:   // accessoryRectangular
            VStack(alignment: .leading, spacing: 1) {
                Text(snap?.dayLabel ?? tr("오늘", "Today"))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(statusText).font(.headline).lineLimit(1)
                if let n = nextText { Text(n).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 하루 일정 진행률(0…1) — 무지개 바와 동일한 packed 기준.
    private var progress: Double {
        guard let snap else { return 0 }
        let single = snap.segments.filter { !$0.isMultiDay }
        return PackedLayout(intervals: single.map { (start: $0.start, end: $0.end) }).fraction(at: Date())
    }

    private var inlineText: String {
        guard let snap, !snap.segments.isEmpty else { return tr("일정 없음", "No events") }
        if let cur = snap.currentTitle { return tr("현재", "Now") + " · " + cur }
        if let title = snap.nextTitle, let start = snap.nextStart {
            return tr("다음", "Next") + " · \(title) " + remaining(to: start)
        }
        return tr("오늘 종료", "All done")
    }

    private var statusText: String {
        guard let snap, !snap.segments.isEmpty else { return tr("일정 없음", "No events") }
        if let cur = snap.currentTitle { return cur }
        if let title = snap.nextTitle { return title }
        return tr("오늘 종료", "All done")
    }

    private var nextText: String? {
        if let snap, snap.currentTitle != nil, let title = snap.nextTitle, let start = snap.nextStart {
            return tr("다음", "Next") + " · \(title) " + timeString(start)
        }
        if let start = snap?.nextStart { return remaining(to: start) + tr(" 후", " left") }
        return nil
    }

    private func tr(_ ko: String, _ en2: String) -> String { en ? en2 : ko }

    private func remaining(to target: Date) -> String {
        let s = target.timeIntervalSince(Date())
        if s <= 0 { return tr("곧", "soon") }
        let m = Int(s) / 60
        if m < 60 { return en ? "\(m)m" : "\(m)분" }
        return en ? "\(Int(s) / 3600)h" : "\(Int(s) / 3600)시간"
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: en ? "en_US" : "ko_KR")
        f.dateFormat = "a h:mm"
        return f.string(from: date)
    }
}
