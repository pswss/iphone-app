import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
import WidgetKit

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
    @State private var gridInteracting = false         // 일정 드래그/리사이즈 중 → 좌우 날짜 스와이프 잠금
    @State private var showSearch = false             // 일정 검색 시트(맥)
    #if os(iOS)
    @State private var showMealSheet = false          // 급식(학생) — 탭에서 헤더 아이콘으로 이동
    @State private var showSettingsSheet = false      // 설정 — 탭에서 헤더 아이콘으로 이동
    #endif
    private let lang = AppLanguage.shared
    @AppStorage("userType") private var userType = "general"
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    #endif

    private var plan: DayPlan { dayPlan(for: selectedDay) }

    #if os(iOS)
    private var wide: Bool { hSize == .regular }
    #else
    private var wide: Bool { true }   // macOS: 항상 넓은(regular) 레이아웃
    #endif
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
        bandCache = computeBandItems()   // 전체 일정 순회는 여기(데이터 변경 시)서만 — 스크롤 중 매 프레임 계산 금지
    }

    var body: some View {
        ZStack {
            AppBackground()
            // 아이패드도 검증된 단일 컬럼(narrowContent)을 중앙 정렬로 — 2단 레이아웃의 동작 불량 해결
            #if os(macOS)
            narrowContent   // 맥: 주 그리드가 창 전체 폭을 알뜰히 사용
            #else
            narrowContent.frame(maxWidth: wide ? 760 : .infinity)
            #endif
        }
        .overlay(alignment: .top) { clipboardChip }          // 복사/잘라내기 활성 표시 + 취소(빈 곳 추가 하이재킹 방지)
        .animation(.snappy(duration: 0.25), value: EventClipboard.shared.item == nil)
        #if os(iOS)
        .overlay(alignment: .bottomTrailing) { addButton }   // 맥은 툴바 '+ 새 일정' 사용
        #endif
        .sheet(isPresented: $showingAdd, onDismiss: syncLiveActivity) {
            EventEditorView(event: nil, day: selectedDay, prefillStart: addStart)
            #if os(iOS)
                .presentationDetents([.medium, .large])   // 절반 높이 → 위 그리드의 미리보기 블록이 보임
            #else
                .frame(minWidth: 480, minHeight: 600)
            #endif
        }
        .sheet(item: $editing, onDismiss: syncLiveActivity) { event in
            EventEditorView(event: event, day: selectedDay)
            #if os(macOS)
                .frame(minWidth: 480, minHeight: 600)
            #endif
        }
        .onAppear {
            seedIfRequested(); rebuildIndex(); syncLiveActivity()
            if sharedScrollHour == nil { sharedScrollHour = max(0, Calendar.current.component(.hour, from: Date()) - 1) }
        }
        .onChange(of: events) { _, _ in rebuildIndex(); syncLiveActivity() }
        .onChange(of: scenePhase) { _, phase in
            // 어제 켜둔 앱이 아침에 포그라운드로 복귀하는 경로 — onAppear가 다시 안 불려
            // LA가 영영 재시작되지 않던 문제. 활성화 때마다 오늘 기준으로 재동기화.
            if phase == .active { syncLiveActivity(); bandCache = computeBandItems() }   // 날짜 넘어간 경우 D-Day 재계산
        }
        .onReceive(NotificationCenter.default.publisher(for: .oneulNewEvent)) { _ in addStart = nil; showingAdd = true }
        .onReceive(NotificationCenter.default.publisher(for: .oneulToday)) { _ in selectedDay = .now }
        .onReceive(NotificationCenter.default.publisher(for: .oneulShiftDay)) { note in
            if let n = note.object as? Int,
               let d = Calendar.current.date(byAdding: .day, value: n, to: selectedDay) { selectedDay = d }
        }
        .onReceive(NotificationCenter.default.publisher(for: .oneulShowDay)) { note in
            if let d = note.object as? Date { selectedDay = d }   // 알림 탭 → 해당 일정 날짜로
        }
        .onReceive(NotificationCenter.default.publisher(for: .oneulSyncLA)) { _ in syncLiveActivity() }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .oneulSearch)) { _ in showSearch = true }   // ⌘F
        #endif
        #if os(macOS)
        .sheet(isPresented: $showSearch) {
            EventSearchSheet(events: events) { day in selectedDay = day }
                .frame(minWidth: 440, minHeight: 500)
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showMealSheet) { MealView() }
        .sheet(isPresented: $showSettingsSheet) { SettingsView() }
        #endif
    }

    private func grid(_ p: DayPlan, _ d: Date,
                      scrollHour: Binding<Int?>,
                      onScrollDelta: ((CGFloat) -> Void)? = nil) -> some View {
        DayGridView(plan: p, day: d,
                    onEdit: { editing = $0 },
                    onAdd: { addStart = $0; showingAdd = true },
                    onScrollDelta: onScrollDelta,
                    previewStart: previewFor(d),
                    scrollHour: scrollHour,
                    onInteractingChange: { gridInteracting = $0 })
    }

    /// 그 날에 생일·기념일(데이마커)이 있는지 — 캘린더 날짜 빨강 표시용.
    private func hasDayMarker(_ d: Date) -> Bool {
        (eventsByDay[Calendar.current.startOfDay(for: d)] ?? []).contains { $0.isDayMarker() }
    }

    /// 새 일정 추가 시트가 떠 있고 그 시작 시각이 이 날짜면 미리보기 블록 표시.
    private func previewFor(_ d: Date) -> Date? {
        guard showingAdd, let s = addStart,
              Calendar.current.isDate(s, inSameDayAs: d) else { return nil }
        return s
    }

    /// DayPager가 보이는 페이지를 다시 그려야 하는 신호 — 그리드에 "값으로" 들어가는 것들(일정=indexVersion,
    /// 미리보기=showingAdd/addStart, 선택일=active 재계산용)만 모음. 스크롤(timelineProgress)은 여기 없으니
    /// 스크롤 중엔 재생성 안 함(떨림 방지). 날짜가 바뀌면(슬라이드·클릭 등 모든 경로) 한 번 재생성돼 새 페이지가
    /// active=true로 다시 그려지고 onScrollDelta가 살아남 → 접힘 모션이 계속 동작.
    private var gridToken: Int {
        var h = Hasher()
        h.combine(indexVersion)
        h.combine(showingAdd)
        h.combine(addStart)
        h.combine(Calendar.current.startOfDay(for: selectedDay))
        return h.finalize()
    }

    // 복사/잘라내기 상태 칩 — 클립보드가 차 있는 동안만 상단에 떠서 붙여넣기 모드임을 알리고 취소 제공
    @ViewBuilder private var clipboardChip: some View {
        if EventClipboard.shared.item != nil {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").font(.caption)
                Text(lang.tr("일정 복사됨 · 빈 곳을 눌러 붙여넣기")).font(.caption).bold()
                Button {
                    EventClipboard.shared.clear(); Haptics.impact(.light)
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.callout).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassEffect(.regular, in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
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
        .accessibilityLabel(lang.tr("새 일정"))
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

            #if os(iOS)
            DayPager(selectedDay: $selectedDay, refreshID: gridToken, swipeDisabled: gridInteracting) { day in   // UIPageViewController 3페이지 재사용
                gridPage(day)
            }
            #else
            macDayNav
            MacWeekGrid(weekStart: weekStart(of: selectedDay),
                        dayPlan: { dayPlan(for: $0) },
                        onEdit: { editing = $0 },
                        onAdd: { addStart = $0; showingAdd = true },
                        previewStart: { previewFor($0) },   // 추가 시트 열려 있는 동안 점선 미리보기(iOS와 동일)
                        isSpecial: { hasDayMarker($0) },
                        scrollHour: $sharedScrollHour)   // macOS: 한 주(월~일) 7열을 한눈에
                .padding(.horizontal, 12)
                // .id(gridToken) 금지 — 데이터 변경마다 뷰 아이덴티티가 바뀌면 드래그/리사이즈 커밋 때
                // 스크롤이 초기 위치로 점프하고 선택이 풀림. 맥은 상태 기반 갱신으로 충분(미리보기도 안 씀).
            #endif
        }
        .padding(.top, 8)
        .onPreferenceChange(RowHeightKey.self) { new in
            let merged = rowH.merging(new) { _, n in n }
            if merged != rowH { rowH = merged }   // 같은 값이면 안 씀 — 접힘 스크롤 중 불필요한 재렌더 방지
        }
    }

    #if os(macOS)
    // macOS 주 이동 컨트롤 — ‹ / 오늘 / › + Left/Right 화살표 단축키(주 그리드라 한 주씩 이동).
    private var macDayNav: some View {
        HStack(spacing: 12) {
            Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Spacer()
            Button(lang.tr("오늘")) { selectedDay = .now }
                .font(.subheadline).bold()
            Spacer()
            Button { shiftWeek(1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    /// 한 주(±7일)씩 이동 — 주 그리드 전체가 다음/이전 주로 넘어감.
    private func shiftWeek(_ n: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: n * 7, to: selectedDay) {
            selectedDay = d
        }
    }

    /// 그 날이 속한 주의 시작 — 시스템 '주 시작 요일' 설정(firstWeekday)을 따름.
    private func weekStart(of day: Date) -> Date {
        let c = Calendar.current
        return c.dateInterval(of: .weekOfYear, for: day)?.start ?? c.startOfDay(for: day)
    }
    #endif

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
            chromeRow(index: 1, order: 2) { unifiedBand }   // 주요 알림(시험 D-Day·방학) — 독립 위젯 행
            #if os(iOS)
            chromeRow(index: 2, order: 1) { CalendarBar(selectedDay: $selectedDay,
                                                     isSpecial: { hasDayMarker($0) }) }   // 맥은 주 그리드가 대신함 → 주간 스트립 불필요
            #endif
            #if os(iOS)
            chromeRow(index: 3, order: 0) { timelineCard(plan, live: Calendar.current.isDateInToday(selectedDay)) }   // 맥은 주 그리드가 타임라인 → 하루짜리 타임라인 카드 불필요
            #endif
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
                        // 1/120 단위로 양자화 + 같은 값이면 안 씀 — 접힘 구간 밖(0/1 포화)에선 스크롤이
                        // 뷰 갱신을 전혀 유발하지 않게(120Hz 아이패드 스크롤 끊김 방지).
                        let p = min(1, max(0, (y - 22) / 253))
                        let q = (p * 120).rounded() / 120
                        if abs(q - timelineProgress) > 0.0001 { timelineProgress = q }
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
                #if os(iOS)
                if isStudent {   // 검색은 하단 탭(role .search)으로 이동 — 헤더엔 급식만
                    capsuleIcon("fork.knife") { showMealSheet = true }
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                #else
                capsuleIcon("magnifyingglass") { showSearch = true }
                    .glassEffect(.regular.interactive(), in: Capsule())
                #endif
            }
            if let holiday = Holidays.name(for: selectedDay) {
                Text(holiday)
                    .font(.caption).bold()
                    .foregroundStyle(.red)
            }
            promotionBanner
        }
        .padding(.top, 4)
    }

    // MARK: 새 학년 안내 — 3월인데 시간표가 작년 학년도면 재설정 유도(자동 진급은 반 배정을 알 수 없어 위험)
    @AppStorage("promoSnoozeYear") private var promoSnoozeYear = 0
    private var currentSchoolYear: Int {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return (c.month ?? 1) >= 3 ? (c.year ?? 0) : (c.year ?? 1) - 1
    }
    private var needsPromotion: Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: "ttSetup") else { return false }
        let saved = d.integer(forKey: "ttYear")
        guard saved > 0 else { return false }                       // 기록 없으면(구버전 설정) 오탐 방지
        return saved < currentSchoolYear && promoSnoozeYear < currentSchoolYear
    }

    @ViewBuilder private var promotionBanner: some View {
        if isStudent && needsPromotion {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill").font(.caption)
                Text(lang.tr("새 학년이 시작됐어요 — 설정에서 학년·반을 다시 설정해 주세요"))
                    .font(.caption).bold()
                Spacer(minLength: 4)
                Button {
                    promoSnoozeYear = currentSchoolYear   // 이번 학년도 동안 숨김
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.appAccent.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            #if os(iOS)
            .onTapGesture { showSettingsSheet = true }
            #endif
            .padding(.top, 6)
        }
    }

    // 연결 캡슐 안의 아이콘 버튼
    private func capsuleIcon(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    // MARK: D-Day (다가오는 시험/수능)
    private var dDays: [(title: String, days: Int)] {
        let today = Calendar.current.startOfDay(for: Date())
        var nearest: [String: Date] = [:]
        for e in events {
            // '수행평가'는 상시 과제라 D-Day 칩에서 제외(수능·기말이 밀려나는 문제)
            guard !e.title.contains("수행") else { continue }
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

    // 시험 D-Day + 방학·주요 일정을 하나의 밴드로 — 위젯 전폭, 한 장씩 페이지 슬라이드
    private struct BandItem: Identifiable {
        let id: String
        let badge: String        // "D-58" / "D-DAY" / "진행 중"
        let urgent: Bool         // 7일 이내 → 빨강
        let title: String
        let trailing: String     // 날짜
    }

    /// 밴드 항목 캐시 — 전체 일정을 순회하므로 데이터 변경(rebuildIndex)·재활성화 때만 재계산.
    /// (예전엔 계산 프로퍼티라 접힘 스크롤 매 프레임 전체 일정을 훑어 아이패드에서 끊겼음)
    @State private var bandCache: [BandItem] = []

    private func computeBandItems() -> [BandItem] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        var seen = Set<String>()
        var out: [(days: Int, item: BandItem)] = []

        func add(days: Int, badge: String, title: String, date: Date) {
            guard seen.insert(title).inserted else { return }
            out.append((days, BandItem(id: title, badge: badge, urgent: days >= 0 && days <= 7,
                                       title: title,
                                       trailing: date.formatted(.dateTime.month().day().locale(lang.locale)))))
        }
        for d in dDays {   // 시험 D-Day
            if let date = cal.date(byAdding: .day, value: d.days, to: today) {
                add(days: d.days, badge: d.days <= 0 ? "D-DAY" : "D-\(d.days)", title: d.title, date: date)
            }
        }
        let horizon = cal.date(byAdding: .day, value: 365, to: now) ?? now
        for e in events where (e.pinned || e.isMultiDay()) && e.end >= now && e.start <= horizon {
            let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: e.start)).day ?? 0
            let badge = (e.isMultiDay() && e.start <= now) ? lang.tr("진행 중") : (days <= 0 ? "D-DAY" : "D-\(days)")
            add(days: max(days, 0), badge: badge, title: e.title, date: e.start)
        }
        return out.sorted { $0.days < $1.days }.map(\.item)
    }

    @ViewBuilder
    private var unifiedBand: some View {
        let items = bandCache
        if !items.isEmpty {
            Group {
                #if os(iOS)
                TabView {
                    ForEach(items) { bandCard($0) }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))   // 한 장씩 스와이프(점 없이 깔끔하게)
                #else
                ScrollView(.horizontal, showsIndicators: false) {   // 맥: 칩 나열(평소대로) — 한눈에 전부
                    HStack(spacing: 8) {
                        ForEach(items) { macBandChip($0) }
                    }
                }
                #endif
            }
            .frame(height: 46)
        }
    }

    #if os(macOS)
    // 맥 칩 — 제목 + D-Day 배지 나란히(예전 D-Day 바 스타일)
    private func macBandChip(_ it: BandItem) -> some View {
        HStack(spacing: 7) {
            Text(it.title).font(.subheadline).bold().lineLimit(1)
            Text(it.badge)
                .font(.caption2).bold().monospacedDigit()
                .foregroundStyle(Color.appOnAccent)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(it.urgent ? Color.red : Color.appAccent, in: Capsule())
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassCard(cornerRadius: 14)
    }
    #endif

    private func bandCard(_ it: BandItem) -> some View {
        HStack(spacing: 8) {
            Text(it.badge)
                .font(.caption).bold().monospacedDigit()
                .foregroundStyle(Color.appOnAccent)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(it.urgent ? Color.red : Color.appAccent, in: Capsule())
            Text(it.title).font(.subheadline).bold().lineLimit(1)
            Spacer(minLength: 6)
            Text(it.trailing).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .glassCard(cornerRadius: 16)
    }

    // MARK: 타임라인 카드
    private func timelineCard(_ p: DayPlan, live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {   // 제목·바·상태를 촘촘히 붙임
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
                Capsule().fill(.gray.opacity(0.22))                  // 빈 날도 같은 높이의 바 → 슬라이드 시 카드 크기 통일
                    .frame(height: wide ? 26 : 19)
                Text(lang.tr("일정 없음"))
                    .font(.subheadline).bold()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TimelineBar(plan: p, height: wide ? 26 : 19, live: live)   // 원래보다 살짝만 두껍게
                Text(currentLine(p))
                    .font(.subheadline).bold()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .glassCard(cornerRadius: 22)
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
        let shown = DayPlan.upcoming(events: events)   // 위젯·워치용(다가오는 날 폴백)
        #if os(iOS)
        // Live Activity는 항상 유지 — 일정이 없어도 '오늘 일정 없음' 상태로 상시 표시.
        let todayPlan = DayPlan(events: events, day: .now)
        LiveActivityController.shared.refresh(plan: todayPlan, dayLabel: dayLabel(for: .now))
        #endif
        NotificationManager.shared.reschedule(for: events)   // 전체 일정(가까운 알림 + 시험 전날)
        #if canImport(WatchConnectivity)
        let wp = (shown?.plan ?? DayPlan(events: events, day: .now))
        WatchSync.shared.send(wp.watchPayload(dayLabel: dayLabel(for: shown?.day ?? .now)))
        #endif

        // 홈 화면 위젯 갱신(App Group 공유) — 오늘이 비면 다가오는 날, 그것도 없으면 빈 스냅샷.
        let homePlan = shown?.plan ?? DayPlan(events: events, day: .now)
        SharedStore.writeToday(homePlan.homeSnapshot(dayLabel: dayLabel(for: shown?.day ?? .now)))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func dayLabel(for day: Date) -> String {
        let f = DateFormatter()
        let en = AppLanguage.shared.isEnglish
        f.locale = Locale(identifier: en ? "en_US" : "ko_KR")
        f.dateFormat = en ? "EEEE, MMM d" : "M월 d일 EEEE"
        return f.string(from: day)
    }
}

// MARK: - 날짜 페이저 (UIPageViewController) — 좌우 슬라이드로 하루씩, 3페이지만 재사용(애플 캘린더식, 렉/튐 없음)
#if os(iOS)
struct DayPager<Content: View>: UIViewControllerRepresentable {
    @Binding var selectedDay: Date
    var refreshID: Int = 0                       // 일정 변경 시 값이 바뀌어 updateUIViewController를 강제 → 보이는 페이지 갱신
    var swipeDisabled: Bool = false              // 일정 드래그/리사이즈 중엔 좌우 페이지 스와이프 잠금
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
        // 일정 드래그/리사이즈 중엔 내부 스크롤뷰(좌우 페이지 스와이프) 잠금 — 세로 드래그와 충돌 방지
        pvc.view.subviews.compactMap { $0 as? UIScrollView }.forEach { $0.isScrollEnabled = !swipeDisabled }
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
            withAnimation(.snappy(duration: 0.3)) { parent.selectedDay = h.day }   // 탭 이동과 동일한 자연 전환
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
#endif

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


#if os(macOS)
/// 맥 주 그리드 — 한 주(월~일) 7일을 가로로 나란히. 첫 열만 시각축, 세로 스크롤 공유.
struct MacWeekGrid: View {
    let weekStart: Date
    let dayPlan: (Date) -> DayPlan
    var onEdit: (ScheduleEvent) -> Void
    var onAdd: (Date) -> Void
    var previewStart: (Date) -> Date? = { _ in nil }   // 새 일정 점선 미리보기(요일별)
    var isSpecial: (Date) -> Bool = { _ in false }     // 생일·기념일 — 헤더 날짜 빨강
    @Binding var scrollHour: Int?

    private let cal = Calendar.current
    private let lang = AppLanguage.shared
    private var days: [Date] { (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) } }
    @State private var didInitialScroll = false
    private var anchorHour: Int { max(0, min(23, cal.component(.hour, from: Date()) - 1)) }   // 첫 진입 위치(현재 시각 한 시간 위)

    // 열 최소폭 규격 — 좁아지면 150pt 고정에 월요일부터 잘려 나가고, 넓으면 열이 늘어나 창을 꽉 채움
    private let minColW: CGFloat = 150
    private let gutterW: CGFloat = 52          // 시각축 전용 거터(열과 분리 → 7열 폭 완전 균등)
    private let hourH: CGFloat = 70            // DayGridView hourHeight와 동일

    @State private var colW: CGFloat = 150
    private var totalW: CGFloat { gutterW + colW * 7 }

    var body: some View {
        GeometryReader { geo in
            let eff = max(minColW, (geo.size.width - gutterW) / 7)   // 전체화면에선 늘려서 여백 없이
            let total = gutterW + eff * 7
            fixedGrid
                .frame(width: total)
                // 넓으면 꽉 참(중앙), 좁으면 오른쪽(일요일) 고정 → 월요일부터 서서히 사라짐
                .frame(width: geo.size.width, height: geo.size.height,
                       alignment: geo.size.width >= total ? .center : .trailing)
                .clipped()
                .onAppear { colW = eff }
                .onChange(of: eff) { _, v in colW = v }
        }
    }

    private var fixedGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {                              // 요일 헤더는 고정(스크롤 안 함)
                Color.clear.frame(width: gutterW, height: 1)
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    dayHeader(d).frame(width: colW)
                }
            }
            .padding(.bottom, 4)
            allDayBand   // 요일 아래 고정 밴드 — 여러 날 걸친 종일 일정을 연속 바로(스크롤해도 보임)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {          // 7열을 감싸는 단일 스크롤 → 모든 요일이 함께 세로 이동
                    HStack(spacing: 0) {
                        hourGutter                            // 시각 라벨 열(별도) → 7열 폭 균등
                        ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                            DayGridView(plan: dayPlan(d), day: d,
                                        onEdit: onEdit, onAdd: onAdd,
                                        previewStart: previewStart(d),
                                        scrollHour: $scrollHour,
                                        showHourLabels: false,
                                        scrollsInternally: false)   // 내부 스크롤 끔 → 바깥 단일 스크롤이 통합 제어
                                .frame(width: colW)
                                .overlay(alignment: .leading) {
                                    if i > 0 {   // 열 구분선 — 가로줄과 같은 헤어라인
                                        Rectangle().fill(.primary.opacity(0.14)).frame(width: 0.5)
                                    }
                                }
                        }
                    }
                }
                .onAppear {
                    guard !didInitialScroll else { return }
                    didInitialScroll = true
                    proxy.scrollTo(anchorHour, anchor: .top)   // 모든 열의 같은 시각 행은 같은 Y라 어느 열이든 결과 동일
                }
            }
        }
    }

    /// 시각 라벨 전용 거터 — DayGridView hourRow와 같은 규격(70pt/행).
    private var hourGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(hourLabel(h))
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: gutterW - 8, alignment: .leading)
                    .frame(height: hourH, alignment: .top)
                    .offset(y: -7)   // DayGridView 라벨과 동일 정렬
            }
        }
        .frame(width: gutterW, alignment: .leading)
        .padding(.leading, 8)
        .frame(width: gutterW)
    }

    private func hourLabel(_ h: Int) -> String {
        let h12 = h % 12 == 0 ? 12 : h % 12
        if lang.isEnglish { return "\(h12) \(h < 12 || h == 24 ? "AM" : "PM")" }
        return "\(h < 12 || h == 24 ? "오전" : "오후") \(h12)시"
    }

    private func dayHeader(_ d: Date) -> some View {
        let today = cal.isDateInToday(d)
        let special = isSpecial(d) || Holidays.name(for: d) != nil   // 생일·기념일·공휴일 빨강(오늘 강조 우선)
        return VStack(spacing: 1) {
            Text(d, format: .dateTime.weekday(.short).locale(lang.locale))
                .font(.caption2).foregroundStyle(today ? Color.appAccentText : .secondary)
            Text(d, format: .dateTime.day())
                .font(.callout).bold()
                .foregroundStyle(today ? Color.appAccentText : (special ? .red : .primary))
        }
    }

    // MARK: 종일 밴드(연속 스팬 바)
    private let barH: CGFloat = 22
    private let barVGap: CGFloat = 4

    /// 이번 주에 걸치는 종일/멀티데이 일정을 연속 바로 배치(겹치면 아래 행으로 패킹).
    private var allDayBars: [PackedBar] {
        var uniq: [UUID: ScheduleEvent] = [:]
        for d in days { for e in dayPlan(d).multiDayEvents { uniq[e.id] = e } }
        let events = uniq.values.sorted { $0.start < $1.start }
        guard !events.isEmpty, days.count == 7 else { return [] }

        let weekEnd = cal.date(byAdding: .day, value: 7, to: days[0]) ?? days[0]
        var rowEnds: [Int] = []        // 각 행이 채운 마지막 열
        var packed: [PackedBar] = []
        for e in events {
            let cols = (0..<7).filter { e.occurs(on: days[$0]) }
            guard let s = cols.first, let en = cols.last else { continue }
            var row = 0
            while row < rowEnds.count && rowEnds[row] >= s { row += 1 }   // s 이전에 끝난 행 찾기
            if row == rowEnds.count { rowEnds.append(en) } else { rowEnds[row] = en }
            packed.append(PackedBar(
                id: e.id, event: e, startCol: s, endCol: en, row: row,
                openLeft: s == 0 && cal.startOfDay(for: e.start) < days[0],   // 지난 주부터 이어짐
                openRight: en == 6 && e.end > weekEnd))                        // 다음 주로 이어짐
        }
        return packed
    }

    @ViewBuilder private var allDayBand: some View {
        let bars = allDayBars
        if !bars.isEmpty {
            let rows = (bars.map { $0.row }.max() ?? 0) + 1
            ZStack(alignment: .topLeading) {
                ForEach(bars) { bar in
                    let x0 = gutterW + colW * CGFloat(bar.startCol)
                    let x1 = gutterW + colW * CGFloat(bar.endCol + 1)
                    allDayPill(bar)
                        .frame(width: max(x1 - x0 - 6, 24), height: barH)
                        .offset(x: x0 + 3, y: CGFloat(bar.row) * (barH + barVGap))
                }
            }
            .frame(width: totalW, height: CGFloat(rows) * (barH + barVGap) - barVGap, alignment: .topLeading)
            .padding(.top, 2).padding(.bottom, 8)
        }
    }

    // 표시는 이전 종일 스타일 그대로(흰 글래스 + 아이콘 + '종일') — 며칠 이어지는 연속 바로만 확장.
    private func allDayPill(_ bar: PackedBar) -> some View {
        let shape = UnevenRoundedRectangle(   // 주 경계를 넘어 이어지는 쪽은 각지게
            topLeadingRadius: bar.openLeft ? 3 : 12, bottomLeadingRadius: bar.openLeft ? 3 : 12,
            bottomTrailingRadius: bar.openRight ? 3 : 12, topTrailingRadius: bar.openRight ? 3 : 12,
            style: .continuous)
        return Button { onEdit(bar.event) } label: {
            HStack(spacing: 8) {
                if bar.openLeft { Image(systemName: "chevron.compact.left").font(.caption2).foregroundStyle(.secondary) }
                Image(systemName: bar.event.bannerIcon).font(.caption2)
                Text(bar.event.title.isEmpty ? lang.tr("제목 없음") : bar.event.title).font(.caption).bold().lineLimit(1)
                Spacer(minLength: 4)
                Text(lang.tr("종일")).font(.caption2).foregroundStyle(.secondary)
                if bar.openRight { Image(systemName: "chevron.compact.right").font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.primary.opacity(0.06), in: shape)
            .overlay(shape.strokeBorder(.primary.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    /// 종일 밴드에 배치된 한 개의 연속 바.
    struct PackedBar: Identifiable {
        let id: UUID
        let event: ScheduleEvent
        let startCol: Int
        let endCol: Int
        let row: Int
        let openLeft: Bool
        let openRight: Bool
    }
}
#endif

// MARK: - 일정 검색 시트 — 제목·장소 매칭, 결과 탭 → 그 날짜로 이동
private struct EventSearchSheet: View {
    let events: [ScheduleEvent]
    var onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private let lang = AppLanguage.shared

    private var results: [ScheduleEvent] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(events
            .filter { $0.title.localizedStandardContains(q) || $0.location.localizedStandardContains(q) }
            .sorted { abs($0.start.timeIntervalSinceNow) < abs($1.start.timeIntervalSinceNow) }   // 지금과 가까운 순
            .prefix(80))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(lang.tr("제목이나 장소로 일정을 찾아요"))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if results.isEmpty {
                    Text(lang.tr("검색 결과가 없어요"))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    List(results) { e in
                        Button { onPick(e.start); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title.isEmpty ? lang.tr("제목 없음") : e.title)
                                    .font(.body).bold().lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(e.start, format: .dateTime.year().month().day().weekday(.abbreviated)
                                        .hour().minute().locale(lang.locale))
                                    if !e.location.isEmpty { Text("· " + e.location).lineLimit(1) }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(lang.tr("일정 검색"))
            .navBarInline()
            .searchable(text: $query, prompt: lang.tr("제목이나 장소"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.tr("닫기")) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(for: ScheduleEvent.self, inMemory: true)
}
