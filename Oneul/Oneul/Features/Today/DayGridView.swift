import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 애플 캘린더식 시간 그리드(=시간표) 일간뷰. 앱 스타일 유지.
/// - 빈 곳 탭 → 일정 추가, 일정 탭 → 수정
/// - 꾹 눌러 드래그 → 시간 이동(햅틱), 맥은 가로 드래그로 요일 이동
/// - 일정 없어도 시간 격자 항상 표시, 화면 가득
struct DayGridView: View {
    let plan: DayPlan
    let day: Date
    var onEdit: (ScheduleEvent) -> Void
    var onAdd: (Date) -> Void
    var onScrollDelta: ((CGFloat) -> Void)? = nil    // 앵커 대비 스크롤 진행량 — 타임라인 연속 접기/펼치기
    var previewStart: Date? = nil                    // 탭으로 추가 중인 새 일정 미리보기(1시간)
    @Binding var scrollHour: Int?                    // 모든 날이 공유하는 세로 스크롤 위치(애플 캘린더식)
    var onInteractingChange: ((Bool) -> Void)? = nil // 일정 드래그/리사이즈 중 알림 → 페이저 좌우 스와이프 잠금
    var showHourLabels: Bool = true                  // 주 그리드에서 첫 열만 시각 라벨 표시(나머지는 숨김)
    var scrollsInternally: Bool = true               // false면 내부 ScrollView 없이 전체 높이 렌더 → 외부(주 그리드)가 통합 스크롤

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    private let lang = AppLanguage.shared
    // 라이트모드: 흰 글자는 대비 붕괴, 순검정은 과함 → 이벤트 색을 어둡게 섞은 딥톤(애플 캘린더식)
    private func blockText(_ c: Color) -> Color { scheme == .dark ? .white : c.mix(with: .black, by: 0.55) }
    private func blockSubText(_ c: Color) -> Color { scheme == .dark ? .white.opacity(0.85) : c.mix(with: .black, by: 0.45).opacity(0.8) }
    private func blockBorder(_ c: Color) -> Color { scheme == .dark ? .white : c.mix(with: .black, by: 0.35) }   // 테두리도 색 계열(순검정 과함)
    private let cal = Calendar.current
    private let hourHeight: CGFloat = 70      // 세로로 늘림(일정이 덜 빽빽하게)
    private var leftInset: CGFloat { showHourLabels ? 52 : 6 }
    private let colGap: CGFloat = 2           // 겹치는 일정 간 가로 간격(틈새 축소)

    @State private var dragID: UUID?
    @State private var dragDY: CGFloat = 0
    @State private var dragDX: CGFloat = 0                 // 맥: 가로 드래그 → 요일 이동(주 그리드)
    @State private var lastStep = 0
    @State private var viewportH: CGFloat = 600
    @State private var resizeID: UUID?
    @State private var resizeDY: CGFloat = 0
    @State private var resizeTopID: UUID?            // 위 끝 잡고 늘리기(시작 시간 변경)
    @State private var resizeTopDY: CGFloat = 0
    @State private var selectedID: UUID?
    @State private var autoScrollDY: CGFloat = 0          // 드래그 중 자동 스크롤로 밀린 양(일정이 손가락을 따라오게)
    @State private var autoScrolling = false
    @State private var autoScrollDir = 0                  // -1 위로, +1 아래로
    @State private var autoScrollInterval: Double = 0.7   // 당긴 정도에 따라 빨라짐(작을수록 빠름)
    @State private var scrollProxy: ScrollViewProxy?
    @State private var deleteBubbleID: UUID?              // 꾹 누르고 안 움직이고 떼면 뜨는 삭제 말풍선
    @State private var menuW: CGFloat = 280               // 컨텍스트 메뉴 실측 폭(화면 밖으로 안 나가게 클램프용)
    @State private var saveError: String?

    private let firstHour = 0
    private let lastHour = 24
    private var midnight: Date { cal.startOfDay(for: day) }
    private var gridTop: Date { midnight }
    private var gridHeight: CGFloat { CGFloat(lastHour - firstHour) * hourHeight }
    /// 처음 보여줄 위치(오늘이면 현재 시각 1시간 전, 아니면 첫 일정 또는 오전 7시).
    private var scrollAnchorHour: Int {
        max(0, cal.component(.hour, from: Date()) - 1)   // 모든 날 동일 기준 → 공유 스크롤·접힘 진행률이 페이지마다 안 튐
    }
    private var anchorY: CGFloat { CGFloat(scrollAnchorHour) * hourHeight }

    var body: some View {
        VStack(spacing: 8) {
            // 주 그리드(맥)에서는 종일 일정을 열마다 넣지 않음 — MacWeekGrid의 연속 스팬 밴드가 대신 그려 격자 정렬을 맞춤
            if scrollsInternally, !plan.multiDayEvents.isEmpty { allDayRow }

            if scrollsInternally {
                GeometryReader { geo in
                    let gridW = geo.size.width - leftInset - 2   // 오른쪽은 숨구멍만 — 블록이 화면 끝까지 차게
                    ZStack(alignment: .bottom) {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                gridContent(width: geo.size.width, gridW: gridW)
                                #if os(iOS)
                                .padding(.bottom, 92)   // 우하단 추가 버튼이 늦은 시간 일정을 가리지 않게 스크롤 여유 확보
                                #endif
                            }
                            .scrollPosition(id: $scrollHour, anchor: .top)            // 모든 날이 공유하는 위치 — 레이아웃 타이밍 무관 동기 복원
                            .scrollBounceBehavior(.always)                            // 내용이 짧아도 위/아래 오버스크롤 바운스
                            .scrollDisabled(dragID != nil || resizeID != nil)         // 이동/리사이즈 중에만 스크롤 잠금
                            .onAppear {
                                scrollProxy = proxy
                                if scrollHour == nil { scrollHour = scrollAnchorHour }   // 첫 진입 기준 위치
                                #if DEBUG
                                if ProcessInfo.processInfo.arguments.contains("-demoSeed") {
                                    // 스크린샷용 — 헤드리스에선 scrollPosition 복원이 첫 렌더에 안 먹어 직접 스크롤
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 900_000_000)
                                        proxy.scrollTo(scrollAnchorHour, anchor: .top)
                                    }
                                }
                                #endif
                            }
                            .trackScroll(enabled: onScrollDelta != nil, hourHeight: hourHeight,
                                         onDelta: onScrollDelta, onHour: { _ in })       // 접힘 진행률만 추적; 위치는 scrollPosition가 공유
                        }
                    }
                    .coordinateSpace(name: "grid")
                    .onAppear { viewportH = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in viewportH = h }
                }
            } else {
                // 주 그리드(맥): 내부 스크롤 없이 전체 높이 렌더 → MacWeekGrid의 단일 ScrollView가 7열을 통합 스크롤
                GeometryReader { geo in
                    gridContent(width: geo.size.width, gridW: geo.size.width - leftInset - 2)
                        .coordinateSpace(name: "grid")
                }
                .frame(height: gridHeight)
            }
        }
        .frame(maxHeight: scrollsInternally ? .infinity : nil)   // 통합 스크롤 열은 고정 높이라 확장 금지
        .alert(lang.tr("저장하지 못했어요"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button(lang.tr("확인"), role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    /// 시간 격자 본체(시각 행 + 구분선 + 빈 곳 제스처 + 현재선 + 일정 블록). 스크롤 유무와 무관하게 재사용.
    @ViewBuilder private func gridContent(width: CGFloat, gridW: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(firstHour..<lastHour, id: \.self) { h in
                    hourRow(h, width: width).id(h)
                }
            }
            .scrollTargetLayout()                    // 시간 행 = 스크롤 위치 타깃(공유 복원용)
            #if os(iOS)
            LongPressArea(minimumDuration: 0.4,                           // 빈 곳 꾹 → 그 위치에 새 일정(스크롤과 동시)
                          onBegan: { y in selectedID = nil; addAt(y: y); Haptics.impact(.medium) })
                .frame(width: width, height: gridHeight)
                .onTapGesture { selectedID = nil; deleteBubbleID = nil }   // 한 번 탭 → 선택/말풍선 해제(추가는 롱프레스만)
            #else
            Color.clear                                                   // 맥: 빈 곳 더블클릭 → 새 일정, 한 번 클릭 → 선택 해제
                .frame(width: width, height: gridHeight)
                .contentShape(Rectangle())
                .onTapGesture { selectedID = nil; deleteBubbleID = nil }
                .gesture(SpatialTapGesture(count: 2).onEnded { v in selectedID = nil; addAt(y: v.location.y) })
            #endif
            if cal.isDateInToday(day) { nowLine(width: width) }
            ForEach(laidOut, id: \.event.id) { eventBlock($0, gridW: gridW) }
            if let ps = previewStart { previewBlock(ps, gridW: gridW) }
        }
        .frame(height: gridHeight, alignment: .topLeading)
        #if os(macOS)
        .onDeleteCommand {   // 선택된 일정 Delete 키로 삭제(맥 표준 편집 모델)
            guard let id = selectedID, let e = plan.events.first(where: { $0.id == id }) else { return }
            deleteEvent(e) { selectedID = nil }
        }
        #endif
    }

    // MARK: 종일(멀티데이)
    private var allDayRow: some View {
        VStack(spacing: 6) {
            ForEach(plan.multiDayEvents) { e in
                Button { onEdit(e) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: e.bannerIcon).font(.caption2)
                        Text(e.title.isEmpty ? lang.tr("제목 없음") : e.title).font(.caption).bold()
                        Spacer()
                        Text(lang.tr("종일")).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 시간선
    private func hourRow(_ h: Int, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.primary.opacity(0.14)).frame(height: 1)   // 적응형 — 라이트/다크 모두 보이게
                .padding(.leading, leftInset)                            // 시간 라벨 영역은 비우고 일정 영역만
            if showHourLabels {
                Text(lang.hourLabel(h))
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: leftInset - 8, alignment: .leading)
                    .offset(y: h == firstHour ? 0 : -7)   // 첫 라벨만 상단 안쪽에 두어 잘림 방지
            }
        }
        .frame(width: width, height: hourHeight, alignment: .topLeading)
    }

    private func nowLine(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {   // 애플 캘린더식 빨간 현재선 — 라이트/다크 모두 또렷
            Circle().fill(.red).frame(width: 7, height: 7).offset(x: leftInset - 3)
            Rectangle().fill(.red).frame(height: 2)
                .shadow(color: .red.opacity(0.5), radius: 3).padding(.leading, leftInset)
        }
        .frame(width: width)
        .offset(y: yOffset(for: Date()) - 1)
    }


    // MARK: 새 일정 미리보기 — 탭한 자리에 1시간 점선 블록
    private func previewBlock(_ start: Date, gridW: CGFloat) -> some View {
        let top = yOffset(for: clamp(start))
        let end = start.addingTimeInterval(3600)
        let h = max(26, yOffset(for: clamp(end)) - top)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return VStack(alignment: .leading, spacing: 1) {
            Text(lang.tr("새 일정")).font(.caption).bold().foregroundStyle(blockText(Color.appAccent)).lineLimit(1)
            Text(timeText(start) + " – " + timeText(end))
                .font(.system(size: 10)).foregroundStyle(blockSubText(Color.appAccent)).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .frame(width: gridW, height: h, alignment: .topLeading)
        .background(Color.appAccent.opacity(0.4), in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
        .shadow(color: Color.appAccent.opacity(0.5), radius: 10)
        .offset(x: leftInset, y: top)
        .allowsHitTesting(false)
        .zIndex(40)
    }

    // MARK: 일정 블록 (솔리드 무지개 컬러)
    private func eventBlock(_ item: Laid, gridW: CGFloat) -> some View {
        let e = item.event
        let resizingBottom = resizeID == e.id
        let resizingTop = resizeTopID == e.id
        let resizing = resizingBottom || resizingTop
        let top = yOffset(for: clamp(e.start)) + (resizingTop ? resizeTopDY : 0)         // 위 끝 잡으면 시작이 따라옴
        let h = max(26, yOffset(for: clamp(e.end)) - top + (resizingBottom ? resizeDY : 0))
        let colW = (gridW - CGFloat(item.cols - 1) * colGap) / CGFloat(item.cols)
        let color = plan.color(of: e)
        let dragging = dragID == e.id
        let selected = selectedID == e.id
        let lifted = dragging || resizing            // 잡고 옮기는/늘리는 중
        let glowing = selected && !lifted            // 그냥 하이라이트 = 빛나는 유리 느낌
        let dy = dragging ? dragDY + autoScrollDY : 0          // 자동 스크롤로 밀린 양 포함 → 손가락 따라옴
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        // 실시간 표시 시간(5분 스냅): 이동 중엔 시작·끝 둘 다, 리사이즈 중엔 끝만
        let moveMin = dragging ? dragMinutes(dragDY + autoScrollDY) : 0
        let resizeMin = resizingBottom ? dragMinutes(resizeDY) : 0
        let resizeTopMin = resizingTop ? dragMinutes(resizeTopDY) : 0
        let dispStart = e.start.addingTimeInterval((moveMin + resizeTopMin) * 60)
        let dispEnd = e.end.addingTimeInterval((moveMin + resizeMin) * 60)

        return blockContent(e, h: h, start: dispStart, end: dispEnd, color: color)
            .frame(width: colW, height: h, alignment: .topLeading)
            // 하이라이트: 원래 모습 유지하되 색만 진하게 + 은은한 색 글로우(유리 느낌). 두꺼운 흰 테두리 X
            .background(color.opacity(lifted ? 0.9 : (selected ? 0.72 : 0.5)), in: shape)
            .overlay(shape.strokeBorder(blockBorder(color).opacity(lifted ? 0.55 : (selected ? 0.4 : 0.25)),
                                        lineWidth: lifted ? 1.5 : 1))
            .shadow(color: glowing ? color.opacity(0.7) : .black.opacity(lifted ? 0.4 : 0.12),
                    radius: glowing ? 13 : (lifted ? 10 : 3),
                    y: glowing ? 0 : (lifted ? 6 : 2))
            .overlay(alignment: .topTrailing) { bubble(e, dy: dy, show: dragging) }
            .overlay { if selected { cornerHighlight(shape).allowsHitTesting(false) } }  // 왼쪽 아래 코너 곡선만 흰색
            .overlay { gestureLayer(e, selected: selected, h: h, dayW: leftInset + gridW + 8) }   // 본문=탭/이동, 위·아래 손잡이=리사이즈
            .overlay(alignment: .top) {   // 꾹 눌렀다 떼면 컨텍스트 메뉴 — 화면 밖으로 안 나가게 가로 클램프
                if deleteBubbleID == e.id {
                    let blockCenter = leftInset + CGFloat(item.col) * (colW + colGap) + colW / 2
                    let contentW = leftInset + gridW + 8
                    let half = menuW / 2
                    let desired = min(max(blockCenter, half + 6), contentW - half - 6)
                    eventMenu(e, shift: desired - blockCenter)
                }
            }
            .scaleEffect(1)   // 확대 없음(하이라이트/이동 시 블록 크기 그대로)
            #if os(macOS)
            // 맥 표준: 우클릭 컨텍스트 메뉴(기존 '가로 드래그 후 릴리즈' 커스텀 메뉴는 발견 불가)
            .contextMenu {
                Button(lang.tr("잘라내기")) { cut(e) }
                Button(lang.tr("복사")) { EventClipboard.shared.copy(e) }
                Button(lang.tr("복제")) { duplicate(e) }
                Divider()
                Button(lang.tr("삭제"), role: .destructive) { deleteEvent(e) }
            }
            #endif
            .offset(x: leftInset + CGFloat(item.col) * (colW + colGap) + (dragging ? dragDX : 0), y: top + dy)
            .zIndex(dragging || resizing || deleteBubbleID == e.id ? 100000 : (selected ? 10000 : Double(item.order)))
            .animation(.snappy(duration: 0.2), value: deleteBubbleID)
            .animation(.snappy(duration: 0.16), value: dragID)
            .animation(.snappy(duration: 0.16), value: selectedID)
            // VoiceOver: 블록 전체를 하나의 요소로, 제목·시간 낭독 + 수정/삭제 액션
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(e.title.isEmpty ? lang.tr("제목 없음") : e.title), \(timeText(e.start)) – \(timeText(e.end))")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onEdit(e) }
            .accessibilityAction(named: lang.tr("삭제")) { deleteEvent(e) }
    }

    /// 선택 시 좌하단 코너에만 보이는 순수 흰색 곡선.
    /// 블록과 같은 연속곡률 shape를 strokeBorder(안쪽 stroke)로 그려 블록 내부 불투명 영역에만 떨어지게 하고,
    /// 마스크로 좌하단 1/4만 노출해 코너 곡선처럼 보이게 한다. (회색 합성 방지)
    private func cornerHighlight(_ shape: RoundedRectangle) -> some View {
        shape
            .strokeBorder(.white, lineWidth: 2.5)
            .shadow(color: .white.opacity(0.9), radius: 3)   // 하얗게 빛나는 코너 손잡이
            .mask {
                ZStack {   // 아래 손잡이=좌하단, 위 손잡이=우상단(반대쪽) 코너 곡선만 노출 — 대각선 배치
                    Rectangle().frame(width: 18, height: 18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    Rectangle().frame(width: 18, height: 18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
    }

    /// 제스처 레이어 — 두 영역이 겹치지 않게 분리.
    /// 위쪽 본문: 탭(하이라이트/수정) + 꾹 눌러 이동.
    /// 아래 손잡이(하이라이트일 때만): 끝 시간만 리사이즈. 영역이 분리돼 손잡이를 당겨도 이동이 끼어들지 않음(시작 시간 고정).
    @ViewBuilder
    private func gestureLayer(_ e: ScheduleEvent, selected: Bool, h: CGFloat, dayW: CGFloat) -> some View {
        VStack(spacing: 0) {
            if selected && h > 56 {
                Color.clear.frame(height: 16).contentShape(Rectangle())   // 위 손잡이 — 시작 시간(종일 짧은 일정 제외)
                    .highPriorityGesture(resizeTopGesture(e))
                    .hoverCursorResize()
            }
            bodyZone(e, selected: selected, dayW: dayW)
            if selected {
                Color.clear.frame(height: 16).contentShape(Rectangle())   // 아래 손잡이 — 종료 시간
                    .highPriorityGesture(resizeGesture(e))
                    .hoverCursorResize()
            }
        }
    }

    /// 본문: 탭(선택/수정). 이동(꾹 누르기)은 "선택된 일정"에만 붙는다 →
    /// 비선택 일정 위엔 어떤 드래그 제스처도 없어 세로 스크롤이 100% 통과(애플 캘린더 방식).
    @ViewBuilder
    private func bodyZone(_ e: ScheduleEvent, selected: Bool, dayW: CGFloat) -> some View {
        #if os(iOS)
        LongPressArea(                                              // 꾹 눌러 이동 — 스크롤과 동시 인식(선택 무관)
            minimumDuration: 0.3,
            onBegan: { _ in beginMove(e) },
            onChanged: { dy, topGap, bottomGap in changeMove(e, dy: dy, topGap: topGap, bottomGap: bottomGap) },
            onEnded: { dy in endMove(e, dy: dy) }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard dragID == nil else { return }
            if selected { onEdit(e) }                          // 하이라이트 상태에서 다시 탭 → 수정
            else { selectedID = e.id; Haptics.impact(.light) } // 탭 → 하이라이트(선택)
        }
        #else
        LongPressArea(                                              // 맥: 클릭-드래그 즉시 이동, 가로 성분 = 요일 이동
            minimumDuration: 0.3,
            onBegan: { _ in beginMove(e) },
            onChangedXY: { dx, dy in
                dragDX = dx
                changeMove(e, dy: dy, topGap: 99_999, bottomGap: 99_999)
            },
            onEndedXY: { dx, dy in endMove(e, dy: dy, dx: dx, dayW: dayW) }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard dragID == nil else { return }
            if selected { onEdit(e) }
            else { selectedID = e.id; Haptics.impact(.light) }
        }
        #endif
    }

    @ViewBuilder
    private func blockContent(_ e: ScheduleEvent, h: CGFloat, start: Date, end: Date, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(e.title.isEmpty ? lang.tr("제목 없음") : e.title)
                .font(.caption).bold().foregroundStyle(blockText(color)).lineLimit(1)
            if h > 36 {
                Text(timeText(start) + " – " + timeText(end))   // 이동/리사이즈 중 실시간 갱신
                    .font(.caption2).foregroundStyle(blockSubText(color)).lineLimit(1)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func bubble(_ e: ScheduleEvent, dy: CGFloat, show: Bool) -> some View {
        if show {
            Text(timeText(clamp(e.start).addingTimeInterval(dragMinutes(dy) * 60)))
                .font(.caption2).bold().foregroundStyle(.black)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.white, in: Capsule()).offset(x: 4, y: -14)
        }
    }

    // MARK: 리사이즈(아래 끝 잡고 늘리기) — 세로 드래그로 종료 시간만 변경(시작 고정)
    private func resizeGesture(_ e: ScheduleEvent) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("grid"))
            .onChanged { v in
                guard dragID == nil else { return }                      // 이동 중엔 리사이즈 안 함
                if resizeID != e.id {
                    // 세로가 우세할 때만 리사이즈 — 가로 스와이프(날짜 넘김)는 통과
                    guard abs(v.translation.height) > abs(v.translation.width) else { return }
                    resizeID = e.id; lastStep = 0; Haptics.impact(.soft)
                    onInteractingChange?(true)
                }
                if resizeID == e.id {
                    resizeDY = v.translation.height
                    let step = Int(dragMinutes(resizeDY))
                    if step != lastStep { lastStep = step; Haptics.impact(.light) }
                }
            }
            .onEnded { _ in
                if resizeID == e.id, commitResize(e) { Haptics.impact(.soft) }
                resizeID = nil; resizeDY = 0; lastStep = 0
                onInteractingChange?(false)
            }
    }

    private func commitResize(_ e: ScheduleEvent) -> Bool {
        let newEnd = e.end.addingTimeInterval(dragMinutes(resizeDY) * 60)
        guard newEnd >= e.start.addingTimeInterval(300) else { return false }
        let oldEnd = e.end
        e.end = newEnd
        return persistInteraction { e.end = oldEnd }  // 최소 5분
    }

    // MARK: 리사이즈(위 끝 잡고 늘리기) — 세로 드래그로 시작 시간만 변경(종료 고정)
    private func resizeTopGesture(_ e: ScheduleEvent) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("grid"))
            .onChanged { v in
                guard dragID == nil else { return }
                if resizeTopID != e.id {
                    guard abs(v.translation.height) > abs(v.translation.width) else { return }
                    resizeTopID = e.id; lastStep = 0; Haptics.impact(.soft)
                    onInteractingChange?(true)
                }
                if resizeTopID == e.id {
                    resizeTopDY = v.translation.height
                    let step = Int(dragMinutes(resizeTopDY))
                    if step != lastStep { lastStep = step; Haptics.impact(.light) }
                }
            }
            .onEnded { _ in
                if resizeTopID == e.id, commitResizeTop(e) { Haptics.impact(.soft) }
                resizeTopID = nil; resizeTopDY = 0; lastStep = 0
                onInteractingChange?(false)
            }
    }

    private func commitResizeTop(_ e: ScheduleEvent) -> Bool {
        let newStart = e.start.addingTimeInterval(dragMinutes(resizeTopDY) * 60)
        guard newStart <= e.end.addingTimeInterval(-300) else { return false }
        let oldStart = e.start
        e.start = newStart
        return persistInteraction { e.start = oldStart }  // 최소 5분
    }

    // 일정 꾹 눌러 이동 — UIKit long-press(스크롤과 동시 인식). 이동이 시작되면 scrollDisabled로 그동안만 스크롤을 잠근다.
    private func beginMove(_ e: ScheduleEvent) {
        guard resizeID == nil, resizeTopID == nil else { return }
        dragID = e.id; selectedID = e.id; lastStep = 0
        autoScrollDY = 0; autoScrolling = false; autoScrollDir = 0
        deleteBubbleID = nil
        onInteractingChange?(true)
        Haptics.impact(.medium)
    }
    private func changeMove(_ e: ScheduleEvent, dy: CGFloat, topGap: CGFloat, bottomGap: CGFloat) {
        guard dragID == e.id else { return }
        dragDY = dy
        let step = Int(dragMinutes(dy + autoScrollDY))
        if step != lastStep { lastStep = step; Haptics.impact(.light) }

        // 위/아래 가장자리 band에 손가락이 들어오면 자동 스크롤. 더 깊이 갈수록 빠르게(당긴 정도 비례).
        let bottomBand: CGFloat = 165, topBand: CGFloat = 120
        if bottomGap >= 0 && bottomGap < bottomBand {                    // 아래 band → 아래로(맨 끝까지)
            let depth = Double((bottomBand - bottomGap) / bottomBand)
            autoScrollInterval = 0.85 - depth * 0.62                     // 느림 0.85s ~ 빠름 0.23s
            startAutoScroll(e, dir: 1)
        } else if topGap >= 0 && topGap < topBand {                      // 위 band → 위로
            let depth = Double((topBand - topGap) / topBand)
            autoScrollInterval = 0.85 - depth * 0.62
            startAutoScroll(e, dir: -1)
        } else {
            autoScrolling = false; autoScrollDir = 0
        }
    }
    private func endMove(_ e: ScheduleEvent, dy: CGFloat, dx: CGFloat = 0, dayW: CGFloat = 0) {
        guard dragID == e.id else { return }
        autoScrolling = false; autoScrollDir = 0
        let eff = dy + autoScrollDY
        let dayShift = dayW > 0 ? Int((dx / dayW).rounded()) : 0         // 맥 주 그리드: 열 폭 단위 반올림 → ±N일
        if dragMinutes(eff) != 0 || dayShift != 0 {
            if commitDrag(e, dy: eff, dayShift: dayShift) { Haptics.impact(.soft) }
        } else {
            #if os(iOS)
            deleteBubbleID = e.id; Haptics.impact(.medium)               // 안 움직이고 떼면 → 컨텍스트 메뉴(iOS)
            #endif
            // 맥: 우클릭 메뉴가 표준 경로 — 무이동 릴리즈는 아무 것도 안 함
        }
        dragID = nil; dragDY = 0; dragDX = 0; autoScrollDY = 0; lastStep = 0
        onInteractingChange?(false)
    }

    private func startAutoScroll(_ e: ScheduleEvent, dir: Int) {
        autoScrollDir = dir
        if !autoScrolling { autoScrolling = true; autoScrollTick(e) }
    }

    /// 일정 위 컨텍스트 메뉴(애플 캘린더식). 라벨은 기기(시스템) 언어. shift만큼 가로로 밀어 화면 안에 두고, 꼬리는 일정 위에 유지.
    private func eventMenu(_ e: ScheduleEvent, shift: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                menuItem(deviceTerm("잘라내기", "Cut", "カット", "剪切", "剪下", "Cortar", "Couper", "Ausschneiden")) {
                    cut(e) { dismissMenu() } }
                menuSep
                menuItem(deviceTerm("복사", "Copy", "コピー", "拷贝", "拷貝", "Copiar", "Copier", "Kopieren")) {
                    EventClipboard.shared.copy(e); dismissMenu() }
                menuSep
                menuItem(deviceTerm("복제", "Duplicate", "複製", "复制", "複製", "Duplicar", "Dupliquer", "Duplizieren")) {
                    duplicate(e) { dismissMenu() } }
                menuSep
                menuItem(deviceTerm("삭제", "Delete", "削除", "删除", "刪除", "Eliminar", "Supprimer", "Löschen"), tint: .red) {
                    deleteEvent(e) { Haptics.notify(.warning); dismissMenu() } }
            }
            .frame(height: 42)
            .fixedSize()
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 13, style: .continuous))   // 커스텀 메뉴를 진짜 유리로(시스템 메뉴와 통일)
            .background(GeometryReader { g in Color.clear.onAppear { menuW = g.size.width } })   // 실측 폭 → 클램프
            DownTriangle().fill(.regularMaterial).frame(width: 18, height: 9)
                .offset(x: -shift)                                   // 메뉴는 밀려도 꼬리는 일정 위를 가리킴
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .offset(x: shift, y: -56)
        .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
    }

    /// 기기(시스템) 언어 기준 표준 편집 용어(앱 언어 토글과 무관). 미지원 언어는 영어로.
    private func deviceTerm(_ ko: String, _ en: String, _ ja: String, _ zhHans: String, _ zhHant: String,
                            _ es: String, _ fr: String, _ de: String) -> String {
        switch Locale.current.language.languageCode?.identifier {
        case "ko": return ko
        case "ja": return ja
        case "zh": return Locale.current.language.script?.identifier == "Hant" ? zhHant : zhHans
        case "es": return es
        case "fr": return fr
        case "de": return de
        default: return en
        }
    }

    private func menuItem(_ title: String, tint: Color = .primary, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline).foregroundStyle(tint)
                .padding(.horizontal, 15).frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private var menuSep: some View {
        Rectangle().fill(.primary.opacity(0.15)).frame(width: 0.5).padding(.vertical, 9)
    }
    private func dismissMenu() { deleteBubbleID = nil; selectedID = nil }
    private func deleteEvent(_ e: ScheduleEvent, onSuccess: () -> Void = {}) {
        if EventActions.deleteSingle(e, in: context) {
            onSuccess()
        } else {
            reportPersistenceFailure()
        }
    }
    private func cut(_ e: ScheduleEvent, onSuccess: () -> Void = {}) {
        let copied = EventClipboard.shared.snapshot(e)
        deleteEvent(e) {
            EventClipboard.shared.item = copied
            onSuccess()
        }
    }
    private func duplicate(_ e: ScheduleEvent, onSuccess: () -> Void = {}) {
        if EventActions.create(title: e.title, start: e.start, end: e.end, location: e.location,
                               notes: e.notes, reminderMinutes: e.reminderMinutes,
                               reminderMinutes2: e.reminderMinutes2, recurrence: .none,
                               pinned: e.pinned, into: context) {
            Haptics.impact(.soft)
            onSuccess()
        } else {
            reportPersistenceFailure()
        }
    }

    /// 드래그 중 가장자리에 대고 있을 때 그리드를 그 방향으로 스크롤(일정도 같은 양만큼 따라옴). 속도는 autoScrollInterval.
    private func autoScrollTick(_ e: ScheduleEvent) {
        guard autoScrolling, dragID == e.id, let proxy = scrollProxy else { return }
        let target = (scrollHour ?? scrollAnchorHour) + autoScrollDir
        guard target >= firstHour, target <= lastHour - 1 else { autoScrolling = false; return }   // 끝이면 멈춤
        let dur = autoScrollInterval
        withAnimation(.linear(duration: dur)) {
            proxy.scrollTo(target, anchor: .top)
            autoScrollDY += CGFloat(autoScrollDir) * hourHeight
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { autoScrollTick(e) }
    }

    private func slotDate(y: CGFloat) -> Date {
        let mins = Double(y) / Double(hourHeight) * 60
        let snapped = (mins / 30).rounded(.down) * 30
        return gridTop.addingTimeInterval(snapped * 60)
    }

    // MARK: 동작
    private func addAt(y: CGFloat) {
        let mins = Double(y) / Double(hourHeight) * 60
        let snapped = (mins / 30).rounded(.down) * 30
        let date = gridTop.addingTimeInterval(snapped * 60)
        if let c = EventClipboard.shared.item {                   // 복사/잘라낸 일정이 있으면 그 자리에 붙여넣기(상단 칩으로 모드 표시·취소 가능)
            if EventActions.create(title: c.title, start: date, end: date.addingTimeInterval(c.duration),
                                   location: c.location, notes: c.notes, reminderMinutes: c.reminderMinutes,
                                   reminderMinutes2: c.reminderMinutes2, recurrence: .none,
                                   pinned: c.pinned, into: context) {
                Haptics.impact(.soft)
            } else {
                reportPersistenceFailure()
            }
        } else {
            onAdd(date)
        }
    }
    private func commitDrag(_ e: ScheduleEvent, dy: CGFloat, dayShift: Int = 0) -> Bool {
        let mins = dragMinutes(dy)
        let dur = e.end.timeIntervalSince(e.start)
        let oldStart = e.start
        let oldEnd = e.end
        var ns = e.start.addingTimeInterval(mins * 60)
        if dayShift != 0, let d = cal.date(byAdding: .day, value: dayShift, to: ns) { ns = d }   // 맥: 옆 요일 열로 이동
        e.start = ns
        e.end = ns.addingTimeInterval(dur)
        return persistInteraction {
            e.start = oldStart
            e.end = oldEnd
        }
    }

    private func persistInteraction(restore: () -> Void) -> Bool {
        do { try context.save(); return true }
        catch {
            restore()
            reportPersistenceFailure()
            return false
        }
    }
    private func reportPersistenceFailure() {
        saveError = lang.tr("변경사항을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.")
        Haptics.notify(.error)
    }
    private func dragMinutes(_ dy: CGFloat) -> Double { (Double(dy) / Double(hourHeight) * 60 / 5).rounded() * 5 }

    // MARK: 레이아웃 — 실제 시간 구간이 겹치는 클러스터를 컬럼으로 분할(애플 캘린더식).
    // 이전 방식(시작 위치 인접만 분할)은 10:00–12:00와 10:30–11:30처럼 시작이 떨어진 겹침을
    // 풀폭으로 포개 그려 아래 일정이 가려지고 탭도 가로채였음.
    private struct Laid { let event: ScheduleEvent; let col: Int; let cols: Int; let order: Int }
    private var laidOut: [Laid] {
        let evs = plan.singleDayEvents.sorted { $0.start < $1.start }
        // 최소 표시 높이(26pt)만큼은 시간상 안 겹쳐도 시각적으로 겹침 → 유효 종료로 보정
        let minVisualSec = Double(26) / Double(hourHeight) * 3600
        func effEnd(_ e: ScheduleEvent) -> Date { max(e.end, e.start.addingTimeInterval(minVisualSec)) }

        var result: [Laid] = []
        var i = 0
        while i < evs.count {
            // 서로 연결돼 겹치는 클러스터 수집
            var clusterEnd = effEnd(evs[i])
            var j = i + 1
            while j < evs.count, evs[j].start < clusterEnd {
                clusterEnd = max(clusterEnd, effEnd(evs[j]))
                j += 1
            }
            // 그리디 컬럼 배정 — 비어 있는 첫 컬럼에 넣기
            var colEnds: [Date] = []
            var assigned: [(e: ScheduleEvent, col: Int)] = []
            for k in i..<j {
                let e = evs[k]
                var c = 0
                while c < colEnds.count, colEnds[c] > e.start { c += 1 }
                if c == colEnds.count { colEnds.append(effEnd(e)) } else { colEnds[c] = effEnd(e) }
                assigned.append((e, c))
            }
            let cols = colEnds.count
            for (e, c) in assigned { result.append(Laid(event: e, col: c, cols: cols, order: result.count)) }
            i = j
        }
        return result
    }

    // MARK: 헬퍼
    private func clamp(_ d: Date) -> Date {
        let hi = gridTop.addingTimeInterval(Double(lastHour) * 3600)
        return min(max(d, gridTop), hi)
    }
    private func yOffset(for date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(gridTop) / 60) * (hourHeight / 60) }
    private func timeText(_ d: Date) -> String { d.formatted(.dateTime.hour().minute().locale(lang.locale)) }
}

// MARK: - 꾹 누르기(UIKit) — UIScrollView 스크롤과 "동시 인식". began/changed/ended로 이동까지(애플 캘린더식)
/// 일정 복사/잘라내기 클립보드(인앱). 빈 곳을 꾹 누르면 그 자리에 붙여넣기.
struct CopiedEvent {
    var title: String
    var duration: TimeInterval
    var location: String
    var notes: String
    var reminderMinutes: Int
    var reminderMinutes2: Int
    var pinned: Bool
}
@Observable final class EventClipboard {
    static let shared = EventClipboard()
    private init() {}
    var item: CopiedEvent?
    func snapshot(_ e: ScheduleEvent) -> CopiedEvent {
        CopiedEvent(title: e.title, duration: max(300, e.end.timeIntervalSince(e.start)),
                    location: e.location, notes: e.notes, reminderMinutes: e.reminderMinutes,
                    reminderMinutes2: e.reminderMinutes2, pinned: e.pinned)
    }
    func copy(_ e: ScheduleEvent) {
        item = snapshot(e)
    }
    func clear() { item = nil }
}

/// 아래를 가리키는 작은 삼각형(말풍선 꼬리).
private struct DownTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

#if os(iOS)
private struct LongPressArea: UIViewRepresentable {
    var minimumDuration: Double = 0.4
    var onBegan: (CGFloat) -> Void = { _ in }                                   // began 위치 y(콘텐츠 좌표)
    var onChanged: (_ translationY: CGFloat, _ topGap: CGFloat, _ bottomGap: CGFloat) -> Void = { _, _, _ in }
    var onEnded: (_ translationY: CGFloat) -> Void = { _ in }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let lp = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handle(_:)))
        lp.minimumPressDuration = minimumDuration
        lp.delegate = context.coordinator
        v.addGestureRecognizer(lp)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }
    func makeCoordinator() -> Coordinator { Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: (CGFloat) -> Void
        var onChanged: (CGFloat, CGFloat, CGFloat) -> Void
        var onEnded: (CGFloat) -> Void
        private var startY: CGFloat = 0
        init(onBegan: @escaping (CGFloat) -> Void,
             onChanged: @escaping (CGFloat, CGFloat, CGFloat) -> Void,
             onEnded: @escaping (CGFloat) -> Void) {
            self.onBegan = onBegan; self.onChanged = onChanged; self.onEnded = onEnded
        }
        @objc func handle(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began:
                startY = g.location(in: nil).y                  // window 기준 시작점(블록이 따라 움직여도 고정)
                onBegan(g.location(in: g.view).y)               // 콘텐츠 위치(이동 전이라 정확)
            case .changed:
                let winH = g.view?.window?.bounds.height ?? 99_999
                let winY = g.location(in: nil).y
                onChanged(winY - startY, winY, winH - winY)      // 이동량 + 위/아래 가장자리 거리(자동 스크롤용)
            case .ended, .cancelled, .failed:
                onEnded(g.location(in: nil).y - startY)
            default: break
            }
        }
        // 스크롤 팬과 동시 인식 → 움직이면 long-press가 취소돼 스크롤로, 정지 후엔 발동
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
#else
/// macOS: 롱프레스 지연 없이 클릭-드래그로 같은 콜백(onBegan/onChanged/onEnded)을 제공.
/// 세로 스크롤은 트랙패드/휠로 하므로 드래그와 충돌하지 않음. 가장자리 자동 스크롤은 비활성(수동 스크롤 사용).
private struct LongPressArea: View {
    var minimumDuration: Double = 0.4                        // macOS에선 미사용(지연 없음)
    var onBegan: (CGFloat) -> Void = { _ in }                // began 위치 y(콘텐츠 로컬 좌표)
    var onChanged: (_ translationY: CGFloat, _ topGap: CGFloat, _ bottomGap: CGFloat) -> Void = { _, _, _ in }
    var onEnded: (_ translationY: CGFloat) -> Void = { _ in }
    var onChangedXY: ((_ dx: CGFloat, _ dy: CGFloat) -> Void)? = nil   // 가로 성분 포함(요일 이동)
    var onEndedXY: ((_ dx: CGFloat, _ dy: CGFloat) -> Void)? = nil

    @State private var began = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)   // 4px 넘겨 끌면 시작 → 순수 클릭은 탭으로 통과
                    .onChanged { v in
                        if !began { began = true; onBegan(v.startLocation.y) }
                        if let xy = onChangedXY { xy(v.translation.width, v.translation.height) }
                        else { onChanged(v.translation.height, 99_999, 99_999) }
                    }
                    .onEnded { v in
                        began = false
                        if let xy = onEndedXY { xy(v.translation.width, v.translation.height) }
                        else { onEnded(v.translation.height) }
                    }
            )
    }
}
#endif

// MARK: - 맥 호버 커서(리사이즈 핸들)
private extension View {
    @ViewBuilder func hoverCursorResize() -> some View {
        #if os(macOS)
        self.onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        #else
        self
        #endif
    }
}

// MARK: - 스크롤 진행량 추적(앵커 대비) — 타임라인 연속 접기. iOS 18+에서만, 그 이하는 그대로
private extension View {
    @ViewBuilder
    func trackScroll(enabled: Bool, hourHeight: CGFloat,
                     onDelta: ((CGFloat) -> Void)?, onHour: @escaping (Int) -> Void) -> some View {
        if #available(iOS 18, *), enabled {
            self.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                onDelta?(y)                            // 그리드 절대 스크롤량(최상단=0) → 접힘 진행률 계산
                onHour(Int((y / hourHeight).rounded()))  // 공유 스크롤 위치(보이는 페이지만)
            }
        } else {
            self   // 비활성 페이지는 추적·쓰기 안 함 → 공유값 오염 방지
        }
    }
}
