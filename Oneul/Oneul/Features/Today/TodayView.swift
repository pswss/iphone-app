import SwiftUI
import SwiftData
import UIKit

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScheduleEvent.start) private var events: [ScheduleEvent]

    @State private var selectedDay: Date = .now
    @State private var editing: ScheduleEvent?
    @State private var showingAdd = false
    @State private var addStart: Date?
    @State private var eventsByDay: [Date: [ScheduleEvent]] = [:]
    @State private var indexVersion = 0                // eventsByDay 재구성 때마다 증가 → DayPager가 최신 인덱스로 갱신
    @State private var timelineProgress: CGFloat = 0   // 상단 접힘 진행률 0~1 (그리드 스크롤 위치 기반)
    @State private var rowH: [Int: CGFloat] = [:]      // 접히는 위젯 4개 자연 높이(index→height)
    @State private var sharedScrollHour: Int?          // 모든 날 grid가 공유하는 세로 스크롤 위치(슬라이드해도 유지)
    private let lang = AppLanguage.shared
    @AppStorage("userType") private var userType = "general"
    @Environment(\.horizontalSizeClass) private var hSize

    private var plan: DayPlan { dayPlan(for: selectedDay) }

    private var wide: Bool { hSize == .regular }
    private var isStudent: Bool { userType == "student" }

    /// 날짜별로 미리 묶어둔 인덱스에서 그 날짜 일정만 꺼내 DayPlan 생성 (전체 수천 개 필터 회피).
    private func dayPlan(for day: Date) -> DayPlan {
        DayPlan(events: eventsByDay[Calendar.current.startOfDay(for: day)] ?? [], day: day)
    }
    /// events 변경 시 한 번만 날짜별 인덱스 재구성. (멀티데이는 걸친 모든 날에 등록)
    private func rebuildIndex() {
        var dict: [Date: [ScheduleEvent]] = [:]
        let cal = Calendar.current
        for e in events {
            var d = cal.startOfDay(for: e.start)
            let last = cal.startOfDay(for: e.end)
            var guardN = 0
            while d <= last && guardN < 370 {
                dict[d, default: []].append(e)
                guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = n; guardN += 1
            }
        }
        eventsByDay = dict
        indexVersion &+= 1
    }

    var body: some View {
        ZStack {
            AppBackground()
            // 아이패드도 검증된 단일 컬럼(narrowContent)을 중앙 정렬로 — 2단 레이아웃의 동작 불량 해결
            narrowContent.frame(maxWidth: wide ? 760 : .infinity)
        }
        .overlay(alignment: .bottomTrailing) { addButton }
        .sheet(isPresented: $showingAdd, onDismiss: syncLiveActivity) {
            EventEditorView(event: nil, day: selectedDay, prefillStart: addStart)
                .presentationDetents([.medium, .large])   // 절반 높이 → 위 그리드의 미리보기 블록이 보임
        }
        .sheet(item: $editing, onDismiss: syncLiveActivity) { event in
            EventEditorView(event: event, day: selectedDay)
        }
        .onAppear {
            seedIfRequested(); rebuildIndex(); syncLiveActivity()
            if sharedScrollHour == nil { sharedScrollHour = max(0, Calendar.current.component(.hour, from: Date()) - 1) }
        }
        .onChange(of: events) { _, _ in rebuildIndex(); syncLiveActivity() }
    }

    private func grid(_ p: DayPlan, _ d: Date,
                      scrollHour: Binding<Int?>,
                      onScrollDelta: ((CGFloat) -> Void)? = nil) -> some View {
        DayGridView(plan: p, day: d,
                    onEdit: { editing = $0 },
                    onAdd: { addStart = $0; showingAdd = true },
                    onScrollDelta: onScrollDelta,
                    previewStart: previewFor(d),
                    scrollHour: scrollHour)
    }

    /// 새 일정 추가 시트가 떠 있고 그 시작 시각이 이 날짜면 미리보기 블록 표시.
    private func previewFor(_ d: Date) -> Date? {
        guard showingAdd, let s = addStart,
              Calendar.current.isDate(s, inSameDayAs: d) else { return nil }
        return s
    }

    /// DayPager가 보이는 페이지를 다시 그려야 하는 신호 — 그리드에 "값으로" 들어가는 것들(일정=indexVersion,
    /// 미리보기=showingAdd/addStart)만 모음. 스크롤(timelineProgress)은 여기 없으니 스크롤 중엔 재생성 안 함 → 떨림 방지.
    private var gridToken: Int {
        var h = Hasher()
        h.combine(indexVersion)
        h.combine(showingAdd)
        h.combine(addStart)
        return h.finalize()
    }

    // 우하단 리퀴드 글래스 + 버튼 (새 일정)
    private var addButton: some View {
        Button {
            addStart = nil
            showingAdd = true
            Haptics.impact(.light)
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.appAccentText)
                .frame(width: 58, height: 58)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .padding(.trailing, 22)
        .padding(.bottom, 22)
    }

    // MARK: 아이폰(세로) — 손가락 좌우 스와이프로 날짜 이동(애플 캘린더식)
    private var narrowContent: some View {
        VStack(spacing: 0) {
            // 맨 위에선 숨고(progress 0), 접힐수록 나타나는 월·연 제목
            compactMonthTitle
                .frame(height: compactTitleH * timelineProgress)
                .opacity(Double(timelineProgress))
                .clipped()

            collapsingChrome   // 헤더·D-Day·캘린더·타임라인이 아래→위 순으로 하나씩 계단식 접힘

            DayPager(selectedDay: $selectedDay, refreshID: gridToken) { day in   // UIPageViewController 3페이지 재사용
                gridPage(day)
            }
        }
        .padding(.top, 8)
        .onPreferenceChange(RowHeightKey.self) { rowH.merge($0) { _, n in n } }
    }

    private let compactTitleH: CGFloat = 34

    // 접힌 상태에서 남는 제목(월·연) — 헤더 날짜와 같은 기기 로케일
    private var compactMonthTitle: some View {
        Text(selectedDay, format: .dateTime.year().month(.wide))
            .font(.headline).bold()
            .frame(maxWidth: .infinity)
    }

    // 접히는 상단 묶음 — 각 위젯이 자기 차례(order)에 맞춰 개별로 접힌다(계단식, 아래→위).
    private var collapsingChrome: some View {
        VStack(spacing: 0) {
            chromeRow(index: 0, order: 3) { header }
            chromeRow(index: 1, order: 2) { dDayBar }
            chromeRow(index: 2, order: 1) { CalendarBar(selectedDay: $selectedDay) }
            chromeRow(index: 3, order: 0) { timelineCard(plan, live: Calendar.current.isDateInToday(selectedDay)) }
        }
        .padding(.horizontal, 16)
    }

    // 위젯 한 줄 — 자연 높이를 재서(RowHeightKey) 로컬 진행률(lp)만큼 접고 위로 살짝 미끄러뜨림.
    // 펼친 상태(lp 0)에선 클립 안 함 → 카드 그림자 안 잘림.
    private func chromeRow<V: View>(index: Int, order: Int, @ViewBuilder _ content: () -> V) -> some View {
        let lp = rowProgress(order: order)
        let h = rowH[index] ?? 0
        return content()
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { g in
                Color.clear.preference(key: RowHeightKey.self, value: [index: g.size.height])
            })
            .frame(height: h > 0 ? max(0, h * (1 - lp)) : nil, alignment: .top)
            .opacity(Double(1 - lp))
            .offset(y: h > 0 ? -h * lp * 0.3 : 0)
            .clippedIf(lp > 0.001)
            .padding(.bottom, 12 * (1 - lp))   // 위젯 간 간격도 같이 접힘
    }

    // 계단식: 전체 진행률에서 위젯 차례(order)만큼 늦게 시작 (stagger 0.08, 위젯 4개).
    private func rowProgress(order: Int) -> CGFloat {
        let s: CGFloat = 0.08
        let w = max(0.0001, 1 - 3 * s)
        return min(1, max(0, (timelineProgress - CGFloat(order) * s) / w))
    }

    // 페이지 = 그리드만 (타임라인은 고정)
    private func gridPage(_ d: Date) -> some View {
        let p = dayPlan(for: d)
        let active = Calendar.current.isDate(d, inSameDayAs: selectedDay)
        return grid(p, d,
                    scrollHour: active ? $sharedScrollHour : .constant(sharedScrollHour),   // 보이는 페이지만 공유값에 쓰기(옆 페이지가 자정으로 덮는 것 방지)
                    onScrollDelta: active ? { y in
                        // y = 그리드 절대 스크롤량(최상단=0). 데드존 22 지나야 접히기 시작, 253pt에 걸쳐 완전히 접힘.
                        timelineProgress = min(1, max(0, (y - 22) / 253))
                    } : nil)
        .padding(.horizontal, 16)
    }

    // MARK: 헤더
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDay, format: .dateTime.day().weekday(.wide))
                    .font(.largeTitle).bold()
                Spacer()
            }
            if let holiday = Holidays.name(for: selectedDay) {
                Text(holiday)
                    .font(.caption).bold()
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
    }

    // MARK: D-Day (다가오는 시험/수능)
    private var dDays: [(title: String, days: Int)] {
        let today = Calendar.current.startOfDay(for: Date())
        var nearest: [String: Date] = [:]
        for e in events {
            let isExam = e.examKind != .none
                || ["수능", "고사", "평가", "시험", "학력"].contains { e.title.contains($0) }
            guard isExam else { continue }
            let d = Calendar.current.startOfDay(for: e.start)
            guard d >= today else { continue }
            if let cur = nearest[e.title] { if d < cur { nearest[e.title] = d } } else { nearest[e.title] = d }
        }
        return nearest.map { (title: $0.key, days: Calendar.current.dateComponents([.day], from: today, to: $0.value).day ?? 0) }
            .sorted { $0.days < $1.days }
            .prefix(3).map { $0 }
    }

    @ViewBuilder
    private var dDayBar: some View {
        let items = dDays
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.title) { item in
                        HStack(spacing: 6) {
                            Text(item.title).font(.caption2).bold().lineLimit(1)
                            Text(item.days == 0 ? "D-DAY" : "D-\(item.days)")
                                .font(.caption2).bold().foregroundStyle(Color.appOnAccent)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(item.days <= 7 ? Color.red : Color.appAccent, in: Capsule())
                        }
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                    }
                }
            }
        }
    }

    // MARK: 타임라인 카드
    private func timelineCard(_ p: DayPlan, live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(live ? lang.tr("오늘 타임라인")
                          : selectedDay.formatted(.dateTime.month().day().locale(lang.locale)) + " " + lang.tr("타임라인"))
                    .font(.subheadline).bold()
                Spacer()
                if let next = p.next() {
                    Text("\(lang.tr("다음 ·")) \(next.title) \(next.start.formatted(.dateTime.hour().minute().locale(lang.locale)))")
                        .font(.caption2).bold()
                        .foregroundStyle(Color.appOnAccent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.appAccent, in: Capsule())
                }
            }

            if p.isEmpty {
                Text(lang.tr("일정 없음"))
                    .font(.subheadline).bold()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TimelineBar(plan: p, height: wide ? 26 : 16, live: live)
                Text(currentLine(p))
                    .font(.subheadline).bold()
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 24)
    }

    private func currentLine(_ p: DayPlan) -> String {
        if let cur = p.current() { return "\(lang.tr("현재 일정 ·")) \(cur.title)" }
        if p.next() != nil { return lang.tr("대기 중 · 다음 일정까지") }
        return lang.tr("오늘 일정 종료")
    }

    // MARK: 동작
    private func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData"), events.isEmpty else { return }
        let now = Date()
        let samples: [(Int, Int, String, String)] = [
            (-210, -150, "아침 준비", "집"),
            (-150,  -90, "팀 회의", "3층 회의실"),
            (-110,  -50, "점심", "성수동"),
            ( -40,   40, "프로젝트 작업", "집중 모드"),
            (  70,  140, "저녁 약속", "이태원"),
            ( 160,  220, "독서", "라운지")
        ]
        for s in samples {
            let start = now.addingTimeInterval(TimeInterval(s.0 * 60))
            let end = now.addingTimeInterval(TimeInterval(s.1 * 60))
            guard Calendar.current.isDateInToday(start) else { continue }
            context.insert(ScheduleEvent(title: s.2, start: start, end: end, location: s.3))
        }
        // 멀티데이 데모: 어제 14:00 ~ 내일 16:00 (오늘에도 떠야 정상)
        let cal = Calendar.current
        if let base = cal.date(bySettingHour: 14, minute: 0, second: 0, of: now),
           let mdStart = cal.date(byAdding: .day, value: -1, to: base),
           let endBase = cal.date(bySettingHour: 16, minute: 0, second: 0, of: now),
           let mdEnd = cal.date(byAdding: .day, value: 1, to: endBase) {
            context.insert(ScheduleEvent(title: "워크숍 (어제~내일)", start: mdStart, end: mdEnd, location: "연수원"))
        }
        try? context.save()
    }

    private func syncLiveActivity() {
        // 오늘이 비어도 가장 가까운(다가오는) 일정 있는 날을 띄움 → 일정이 미래여도 Live Activity가 보임.
        let shown = DayPlan.upcoming(events: events)
        if let shown {
            LiveActivityController.shared.refresh(plan: shown.plan, dayLabel: dayLabel(for: shown.day))
        } else {
            Task { await LiveActivityController.shared.end() }
        }
        NotificationManager.shared.reschedule(for: events)   // 전체 일정(가까운 알림 + 시험 전날)
        #if canImport(WatchConnectivity)
        let wp = (shown?.plan ?? DayPlan(events: events, day: .now))
        WatchSync.shared.send(wp.watchPayload(dayLabel: dayLabel(for: shown?.day ?? .now)))
        #endif
    }

    private func dayLabel(for day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f.string(from: day)
    }
}

// MARK: - 날짜 페이저 (UIPageViewController) — 좌우 슬라이드로 하루씩, 3페이지만 재사용(애플 캘린더식, 렉/튐 없음)
struct DayPager<Content: View>: UIViewControllerRepresentable {
    @Binding var selectedDay: Date
    var refreshID: Int = 0                       // 일정 변경 시 값이 바뀌어 updateUIViewController를 강제 → 보이는 페이지 갱신
    @ViewBuilder var content: (Date) -> Content

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear
        pvc.setViewControllers([context.coordinator.host(selectedDay)], direction: .forward, animated: false)
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        let coord = context.coordinator
        let cal = Calendar.current
        guard let cur = pvc.viewControllers?.first as? Host else { return }

        // 같은 날 — 가드 해제(정착) + 데이터(refreshID)가 실제 바뀌었을 때만 그리드 재생성.
        // 매 body 갱신마다(스크롤 등) 재생성하면 스크롤 중인 ScrollView가 매번 새로 만들어져 떨림/렉 발생.
        if cal.isDate(cur.day, inSameDayAs: selectedDay) {
            coord.isAnimating = false
            if coord.lastRefreshID != refreshID {
                coord.lastRefreshID = refreshID
                cur.rootView = AnyView(content(cur.day))
            }
            return
        }
        guard !coord.isAnimating else { return }   // 슬라이드 중 재진입 차단(엉뚱한 날 착지 방지)

        // 다른 날 — 스냅샷 기반 수동 슬라이드: 목표로 즉시 전환(확실히 착지)한 뒤 옛 화면 스냅샷을
        // 진행 방향으로 밀어내 슬라이드처럼 보이게 한다. UIPageViewController .scroll의 멀티데이 애니메이션
        // 불발/콜백 누락 문제를 회피 — 클릭으로 며칠을 건너뛰어도 항상 슬라이드되고 정확히 착지.
        let forward = selectedDay > cur.day
        let container = pvc.view
        let w = container?.bounds.width ?? 0
        let snap = w > 0 ? container?.snapshotView(afterScreenUpdates: false) : nil
        coord.isAnimating = true
        pvc.setViewControllers([coord.host(selectedDay)],
                               direction: forward ? .forward : .reverse, animated: false)
        func finishJump() {
            coord.isAnimating = false
            guard let nowH = pvc.viewControllers?.first as? Host,
                  !cal.isDate(nowH.day, inSameDayAs: coord.parent.selectedDay) else { return }
            pvc.setViewControllers([coord.host(coord.parent.selectedDay)],
                                   direction: coord.parent.selectedDay > nowH.day ? .forward : .reverse, animated: false)
        }
        guard let snap, let container else { finishJump(); return }
        snap.isUserInteractionEnabled = false
        snap.frame = container.bounds
        container.addSubview(snap)
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
            snap.frame = container.bounds.offsetBy(dx: forward ? -w : w, dy: 0)   // 옛 화면을 진행 방향으로 밀어냄
        } completion: { _ in
            snap.removeFromSuperview()
            finishJump()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: DayPager
        var isAnimating = false                  // 프로그램 슬라이드 진행 중(재진입 차단)
        var lastRefreshID: Int?                  // 마지막으로 그린 refreshID — 같으면 그리드 재생성 생략(스크롤 떨림 방지)
        init(_ parent: DayPager) { self.parent = parent }

        func host(_ day: Date) -> Host { Host(day: day, rootView: AnyView(parent.content(day))) }

        func pageViewController(_ p: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let h = vc as? Host, let d = Calendar.current.date(byAdding: .day, value: -1, to: h.day) else { return nil }
            return host(d)
        }
        func pageViewController(_ p: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let h = vc as? Host, let d = Calendar.current.date(byAdding: .day, value: 1, to: h.day) else { return nil }
            return host(d)
        }
        func pageViewController(_ p: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let h = p.viewControllers?.first as? Host,
                  !Calendar.current.isDate(parent.selectedDay, inSameDayAs: h.day) else { return }
            parent.selectedDay = h.day                                // 슬라이드 끝나면 선택일 갱신
        }
    }

    final class Host: UIHostingController<AnyView> {
        let day: Date
        init(day: Date, rootView: AnyView) {
            self.day = day
            super.init(rootView: rootView)
            view.backgroundColor = .clear
        }
        @MainActor required dynamic init?(coder: NSCoder) { fatalError() }
    }
}

private struct RowHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, n in n }
    }
}

private extension View {
    @ViewBuilder func clippedIf(_ condition: Bool) -> some View {
        if condition { self.clipped() } else { self }
    }
}

#Preview {
    TodayView()
        .modelContainer(for: ScheduleEvent.self, inMemory: true)
}
