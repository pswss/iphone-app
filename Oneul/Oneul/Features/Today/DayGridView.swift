import SwiftUI
import SwiftData

/// 애플 캘린더식 시간 그리드 일간뷰 (앱 스타일 유지). 일정 블록 드래그로 시간 이동.
struct DayGridView: View {
    let plan: DayPlan
    let day: Date
    @Binding var editing: ScheduleEvent?

    @Environment(\.modelContext) private var context
    private let lang = AppLanguage.shared
    private let cal = Calendar.current
    private let hourHeight: CGFloat = 56
    private let leftInset: CGFloat = 46

    @State private var dragID: UUID?
    @State private var dragDY: CGFloat = 0

    // MARK: 시간 범위
    private var midnight: Date { cal.startOfDay(for: day) }
    private var firstHour: Int {
        let starts = plan.singleDayEvents.map { cal.component(.hour, from: max($0.start, midnight)) }
        return max(0, min(starts.min() ?? 8, 8))
    }
    private var lastHour: Int {
        let ends = plan.singleDayEvents.map { e -> Int in
            let end = min(e.end, cal.date(byAdding: .day, value: 1, to: midnight) ?? e.end)
            let h = cal.component(.hour, from: end)
            return cal.component(.minute, from: end) > 0 ? h + 1 : h
        }
        return min(24, max(ends.max() ?? 19, firstHour + 4, 19))
    }
    private var gridHeight: CGFloat { CGFloat(lastHour - firstHour) * hourHeight }
    private var gridTop: Date { cal.date(bySettingHour: firstHour, minute: 0, second: 0, of: day) ?? midnight }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.tr("일정")).font(.subheadline).bold().padding(.leading, 4)

            if !plan.multiDayEvents.isEmpty { allDayRow }

            if plan.singleDayEvents.isEmpty && plan.multiDayEvents.isEmpty {
                Text(lang.tr("일정 없음"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4).padding(.top, 2)
            } else {
                GeometryReader { geo in
                    let gridW = geo.size.width - leftInset - 6
                    ScrollView(showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            hourLines(width: geo.size.width)
                            if cal.isDateInToday(day) { nowLine(width: geo.size.width) }
                            ForEach(laidOut, id: \.event.id) { item in
                                eventBlock(item, gridW: gridW)
                            }
                        }
                        .frame(height: gridHeight + 8)
                    }
                }
                .frame(height: min(gridHeight, 520))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 종일(멀티데이) 행
    private var allDayRow: some View {
        VStack(spacing: 6) {
            ForEach(plan.multiDayEvents) { e in
                Button { editing = e } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.expand.vertical").font(.caption2)
                        Text(e.title.isEmpty ? lang.tr("제목 없음") : e.title)
                            .font(.caption).bold()
                        Spacer()
                        Text("종일").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 시간선
    private func hourLines(width: CGFloat) -> some View {
        ForEach(firstHour...lastHour, id: \.self) { h in
            let y = CGFloat(h - firstHour) * hourHeight
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
                Text(hourLabel(h))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .leading)
                    .offset(y: -7)
            }
            .frame(width: width, alignment: .leading)
            .offset(y: y)
        }
    }

    private func nowLine(width: CGFloat) -> some View {
        let y = yOffset(for: Date())
        return ZStack(alignment: .leading) {
            Circle().fill(.white).frame(width: 7, height: 7).offset(x: leftInset - 3)
            Rectangle().fill(.white).frame(height: 2)
                .shadow(color: .white.opacity(0.8), radius: 3)
                .padding(.leading, leftInset)
        }
        .frame(width: width)
        .offset(y: y - 1)
    }

    // MARK: 일정 블록
    private func eventBlock(_ item: Laid, gridW: CGFloat) -> some View {
        let e = item.event
        let top = yOffset(for: clamp(e.start))
        let bottom = yOffset(for: clamp(e.end))
        let h = max(24, bottom - top)
        let colW = (gridW - CGFloat(item.cols - 1) * 4) / CGFloat(item.cols)
        let dy = (dragID == e.id) ? dragDY : 0
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.13))
            RoundedRectangle(cornerRadius: 3).fill(EventPalette.color(plan.colorIndex(of: e)))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title.isEmpty ? lang.tr("제목 없음") : e.title)
                    .font(.caption).bold().lineLimit(1)
                if h > 34 {
                    Text(timeText(e.start) + " – " + timeText(e.end))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 5)
        }
        .frame(width: colW, height: h)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(dragID == e.id ? 0.5 : 0.14)))
        .shadow(color: .black.opacity(dragID == e.id ? 0.4 : 0), radius: 12, y: 6)
        .scaleEffect(dragID == e.id ? 1.03 : 1)
        .overlay(alignment: .topTrailing) {
            if dragID == e.id {
                Text(timeText(clamp(e.start).addingTimeInterval(dragMinutes(dy) * 60)))
                    .font(.caption2).bold().foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white, in: Capsule())
                    .offset(x: 6, y: -14)
            }
        }
        .offset(x: leftInset + CGFloat(item.col) * (colW + 4), y: top + dy)
        .gesture(dragGesture(e))
        .onTapGesture { if dragID == nil { editing = e } }
        .animation(.snappy(duration: 0.18), value: dragID)
    }

    private func dragGesture(_ e: ScheduleEvent) -> some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    dragID = e.id
                    dragDY = drag.translation.height
                }
            }
            .onEnded { _ in
                commitDrag(e)
                dragID = nil; dragDY = 0
            }
    }

    private func commitDrag(_ e: ScheduleEvent) {
        let mins = dragMinutes(dragDY)
        guard mins != 0 else { return }
        let dur = e.end.timeIntervalSince(e.start)
        e.start = e.start.addingTimeInterval(mins * 60)
        e.end = e.start.addingTimeInterval(dur)
        try? context.save()
    }

    /// 드래그 픽셀 → 분 (5분 스냅).
    private func dragMinutes(_ dy: CGFloat) -> Double {
        let raw = Double(dy) / Double(hourHeight) * 60
        return (raw / 5).rounded() * 5
    }

    // MARK: 레이아웃 (겹침 → 열 분할)
    private struct Laid { let event: ScheduleEvent; let col: Int; let cols: Int }
    private var laidOut: [Laid] {
        let evs = plan.singleDayEvents.sorted { $0.start < $1.start }
        var result: [Laid] = []
        var i = 0
        while i < evs.count {
            var cluster = [evs[i]]
            var clusterEnd = evs[i].end
            var j = i + 1
            while j < evs.count, evs[j].start < clusterEnd {
                cluster.append(evs[j]); clusterEnd = max(clusterEnd, evs[j].end); j += 1
            }
            var columns: [[ScheduleEvent]] = []
            for e in cluster {
                if let idx = columns.firstIndex(where: { ($0.last?.end ?? .distantPast) <= e.start }) {
                    columns[idx].append(e)
                } else { columns.append([e]) }
            }
            for (ci, col) in columns.enumerated() {
                for e in col { result.append(Laid(event: e, col: ci, cols: columns.count)) }
            }
            i = j
        }
        return result
    }

    // MARK: 헬퍼
    private func clamp(_ d: Date) -> Date {
        let lo = gridTop
        let hi = cal.date(bySettingHour: lastHour, minute: 0, second: 0, of: day) ?? d
        return min(max(d, lo), hi)
    }
    private func yOffset(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(gridTop) / 60) * (hourHeight / 60)
    }
    private func hourLabel(_ h: Int) -> String {
        if h == 0 || h == 24 { return lang.isEnglish ? "12 AM" : "오전 12" }
        if h == 12 { return lang.isEnglish ? "12 PM" : "정오" }
        if lang.isEnglish { return h < 12 ? "\(h) AM" : "\(h-12) PM" }
        return h < 12 ? "오전 \(h)" : (h == 12 ? "정오" : "오후 \(h-12)")
    }
    private func timeText(_ d: Date) -> String {
        d.formatted(.dateTime.hour().minute().locale(lang.locale))
    }
}
