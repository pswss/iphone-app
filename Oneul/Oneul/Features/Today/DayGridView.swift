import SwiftUI
import SwiftData

/// 애플 캘린더식 시간 그리드(=시간표) 일간뷰. 앱 스타일 유지.
/// - 빈 곳 탭 → 일정 추가, 일정 탭 → 수정
/// - 꾹 눌러 드래그 → 시간 이동(햅틱), 아래 휴지통에 놓으면 삭제
/// - 일정 없어도 시간 격자 항상 표시, 화면 가득
struct DayGridView: View {
    let plan: DayPlan
    let day: Date
    var onEdit: (ScheduleEvent) -> Void
    var onAdd: (Date) -> Void
    var onScrollDelta: ((CGFloat) -> Void)? = nil    // 앵커 대비 스크롤 진행량 — 타임라인 연속 접기/펼치기
    var previewStart: Date? = nil                    // 탭으로 추가 중인 새 일정 미리보기(1시간)

    @Environment(\.modelContext) private var context
    private let lang = AppLanguage.shared
    private let cal = Calendar.current
    private let hourHeight: CGFloat = 58
    private let leftInset: CGFloat = 52

    @State private var dragID: UUID?
    @State private var dragDY: CGFloat = 0
    @State private var lastStep = 0
    @State private var inTrash = false
    @State private var viewportH: CGFloat = 600
    @State private var resizeID: UUID?
    @State private var resizeDY: CGFloat = 0
    @State private var selectedID: UUID?
    @State private var scrollBase: CGFloat?

    private let firstHour = 0
    private let lastHour = 24
    private var midnight: Date { cal.startOfDay(for: day) }
    private var gridTop: Date { midnight }
    private var gridHeight: CGFloat { CGFloat(lastHour - firstHour) * hourHeight }
    /// 처음 보여줄 위치(오늘이면 현재 시각 1시간 전, 아니면 첫 일정 또는 오전 7시).
    private var scrollAnchorHour: Int {
        if cal.isDateInToday(day) { return max(0, cal.component(.hour, from: Date()) - 1) }
        let first = plan.singleDayEvents.map { cal.component(.hour, from: $0.start) }.min()
        return max(0, (first ?? 8) - 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            if !plan.multiDayEvents.isEmpty { allDayRow }

            GeometryReader { geo in
                let gridW = geo.size.width - leftInset - 8
                ZStack(alignment: .bottom) {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    ForEach(firstHour..<lastHour, id: \.self) { h in
                                        hourRow(h, width: geo.size.width).id(h)
                                    }
                                }
                                Rectangle().fill(.white.opacity(0.12))   // 시간 ↔ 일정 구분선
                                    .frame(width: 1, height: gridHeight).offset(x: leftInset)
                                Color.clear
                                    .frame(width: geo.size.width, height: gridHeight)
                                    .contentShape(Rectangle())
                                    .gesture(SpatialTapGesture().onEnded { v in addAt(y: v.location.y) })
                                if cal.isDateInToday(day) { nowLine(width: geo.size.width) }
                                ForEach(laidOut, id: \.event.id) { eventBlock($0, gridW: gridW) }
                                if let ps = previewStart { previewBlock(ps, gridW: gridW) }
                            }
                            .frame(height: gridHeight, alignment: .topLeading)
                        }
                        .onAppear { proxy.scrollTo(scrollAnchorHour, anchor: .top) }
                        .trackScrollDelta(enabled: onScrollDelta != nil,
                                          base: $scrollBase, onDelta: onScrollDelta)
                    }
                    if dragID != nil { trashBar }
                }
                .coordinateSpace(name: "grid")
                .onAppear { viewportH = geo.size.height }
                .onChange(of: geo.size.height) { _, h in viewportH = h }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: 종일(멀티데이)
    private var allDayRow: some View {
        VStack(spacing: 6) {
            ForEach(plan.multiDayEvents) { e in
                Button { onEdit(e) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.expand.vertical").font(.caption2)
                        Text(e.title.isEmpty ? lang.tr("제목 없음") : e.title).font(.caption).bold()
                        Spacer()
                        Text(lang.tr("종일")).font(.caption2).foregroundStyle(.secondary)
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
    private func hourRow(_ h: Int, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
            Text(hourLabel(h))
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: leftInset - 8, alignment: .leading)
                .offset(y: -7)
        }
        .frame(width: width, height: hourHeight, alignment: .topLeading)
    }

    private func nowLine(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Circle().fill(.white).frame(width: 7, height: 7).offset(x: leftInset - 3)
            Rectangle().fill(.white).frame(height: 2)
                .shadow(color: .white.opacity(0.8), radius: 3).padding(.leading, leftInset)
        }
        .frame(width: width)
        .offset(y: yOffset(for: Date()) - 1)
    }

    // MARK: 휴지통
    private var trashBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash.fill")
            Text(inTrash ? lang.tr("놓으면 삭제") : lang.tr("여기로 끌어 삭제"))
        }
        .font(.subheadline.bold())
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(inTrash ? Color.red : Color.red.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 30).padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: 새 일정 미리보기 — 탭한 자리에 1시간 점선 블록
    private func previewBlock(_ start: Date, gridW: CGFloat) -> some View {
        let top = yOffset(for: clamp(start))
        let end = start.addingTimeInterval(3600)
        let h = max(26, yOffset(for: clamp(end)) - top)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return VStack(alignment: .leading, spacing: 1) {
            Text(lang.tr("새 일정")).font(.caption).bold().foregroundStyle(.white).lineLimit(1)
            Text(timeText(start) + " – " + timeText(end))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .frame(width: gridW, height: h, alignment: .topLeading)
        .background(Color.appAccent.opacity(0.4), in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
        .shadow(color: Color.appAccent.opacity(0.5), radius: 10)
        .offset(x: leftInset, y: top)
        .allowsHitTesting(false)
        .zIndex(40)
    }

    // MARK: 일정 블록 (솔리드 무지개 컬러)
    private func eventBlock(_ item: Laid, gridW: CGFloat) -> some View {
        let e = item.event
        let top = yOffset(for: clamp(e.start))
        let resizing = resizeID == e.id
        let h = max(26, yOffset(for: clamp(e.end)) - top + (resizing ? resizeDY : 0))
        let colW = (gridW - CGFloat(item.cols - 1) * 4) / CGFloat(item.cols)
        let color = EventPalette.color(plan.colorIndex(of: e))
        let dragging = dragID == e.id
        let selected = selectedID == e.id
        let lifted = dragging || resizing            // 잡고 옮기는/늘리는 중
        let glowing = selected && !lifted            // 그냥 하이라이트 = 빛나는 유리 느낌
        let dy = dragging ? dragDY : 0
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        // 실시간 표시 시간(5분 스냅): 이동 중엔 시작·끝 둘 다, 리사이즈 중엔 끝만
        let moveMin = dragging ? dragMinutes(dragDY) : 0
        let resizeMin = resizing ? dragMinutes(resizeDY) : 0
        let dispStart = e.start.addingTimeInterval(moveMin * 60)
        let dispEnd = e.end.addingTimeInterval((moveMin + resizeMin) * 60)

        return blockContent(e, h: h, start: dispStart, end: dispEnd)
            .frame(width: colW, height: h, alignment: .topLeading)
            // 하이라이트: 원래 모습 유지하되 색만 진하게 + 은은한 색 글로우(유리 느낌). 두꺼운 흰 테두리 X
            .background(color.opacity(lifted ? 0.9 : (selected ? 0.72 : 0.5)), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(lifted ? 0.6 : (selected ? 0.4 : 0.22)),
                                        lineWidth: lifted ? 1.5 : 1))
            .shadow(color: glowing ? color.opacity(0.7) : .black.opacity(lifted ? 0.4 : 0.12),
                    radius: glowing ? 13 : (lifted ? 10 : 3),
                    y: glowing ? 0 : (lifted ? 6 : 2))
            .overlay(alignment: .topTrailing) { bubble(e, dy: dy, show: dragging && !inTrash) }
            .overlay { if selected { cornerHighlight(shape).allowsHitTesting(false) } }  // 왼쪽 아래 코너 곡선만 흰색
            .overlay { gestureLayer(e, selected: selected) }       // 본문=탭/이동, 아래 손잡이=리사이즈(영역 분리)
            .scaleEffect(dragging ? 1.04 : 1)
            .opacity(dragging && inTrash ? 0.4 : 1)
            .offset(x: leftInset + CGFloat(item.col) * (colW + 4), y: top + dy)
            .zIndex(dragging || resizing ? 100000 : (selected ? 10000 : Double(item.order)))           // 선택 시 맨 앞으로
            .animation(.snappy(duration: 0.16), value: dragID)
            .animation(.snappy(duration: 0.16), value: inTrash)
            .animation(.snappy(duration: 0.16), value: selectedID)
    }

    /// 선택 시 좌하단 코너에만 보이는 순수 흰색 곡선.
    /// 블록과 같은 연속곡률 shape를 strokeBorder(안쪽 stroke)로 그려 블록 내부 불투명 영역에만 떨어지게 하고,
    /// 마스크로 좌하단 1/4만 노출해 코너 곡선처럼 보이게 한다. (회색 합성 방지)
    @ViewBuilder
    private func cornerHighlight(_ shape: RoundedRectangle) -> some View {
        GeometryReader { geo in
            shape
                .strokeBorder(.white, lineWidth: 2.5)
                .mask(alignment: .bottomLeading) {
                    Rectangle()
                        .frame(width: geo.size.width / 2, height: geo.size.height / 2)
                }
        }
    }

    /// 제스처 레이어 — 두 영역이 겹치지 않게 분리.
    /// 위쪽 본문: 탭(하이라이트/수정) + 꾹 눌러 이동.
    /// 아래 손잡이(하이라이트일 때만): 끝 시간만 리사이즈. 영역이 분리돼 손잡이를 당겨도 이동이 끼어들지 않음(시작 시간 고정).
    @ViewBuilder
    private func gestureLayer(_ e: ScheduleEvent, selected: Bool) -> some View {
        VStack(spacing: 0) {
            bodyZone(e, selected: selected)
            if selected {
                Color.clear                                       // 잡는 영역(아래 strip) — 시각 표시는 코너 곡선이 담당
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .highPriorityGesture(resizeGesture(e))
            }
        }
    }

    /// 본문: 탭(선택/수정). 이동(꾹 누르기)은 "선택된 일정"에만 붙는다 →
    /// 비선택 일정 위엔 어떤 드래그 제스처도 없어 세로 스크롤이 100% 통과(애플 캘린더 방식).
    @ViewBuilder
    private func bodyZone(_ e: ScheduleEvent, selected: Bool) -> some View {
        let base = Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                guard dragID == nil else { return }
                if selected { onEdit(e) }                          // 하이라이트 상태에서 다시 탭 → 수정
                else { selectedID = e.id; Haptics.impact(.light) } // 탭 → 하이라이트(선택)
            }
        if selected {
            base.simultaneousGesture(moveGesture(e))               // 선택된 일정만 꾹 눌러 이동
        } else {
            base                                                   // 비선택: 제스처 없음 → 스크롤 우선
        }
    }

    @ViewBuilder
    private func blockContent(_ e: ScheduleEvent, h: CGFloat, start: Date, end: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(e.title.isEmpty ? lang.tr("제목 없음") : e.title)
                .font(.caption).bold().foregroundStyle(.white).lineLimit(1)
            if h > 36 {
                Text(timeText(start) + " – " + timeText(end))   // 이동/리사이즈 중 실시간 갱신
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
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
                }
                if resizeID == e.id {
                    resizeDY = v.translation.height
                    let step = Int(dragMinutes(resizeDY))
                    if step != lastStep { lastStep = step; Haptics.impact(.light) }
                }
            }
            .onEnded { _ in
                if resizeID == e.id { commitResize(e); Haptics.impact(.soft) }
                resizeID = nil; resizeDY = 0; lastStep = 0
            }
    }

    private func commitResize(_ e: ScheduleEvent) {
        let newEnd = e.end.addingTimeInterval(dragMinutes(resizeDY) * 60)
        if newEnd >= e.start.addingTimeInterval(300) { e.end = newEnd; try? context.save() }  // 최소 5분
    }

    // 손가락이 6pt 이상 움직이면(=스크롤 의도) 꾹 누르기 인식이 취소돼 스크롤이 통과. 정지 상태로 0.32초 눌러야만 이동 시작.
    private func moveGesture(_ e: ScheduleEvent) -> some Gesture {
        LongPressGesture(minimumDuration: 0.32, maximumDistance: 6)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("grid")))
            .onChanged { value in
                guard resizeID == nil else { return }                       // 리사이즈 중엔 이동 안 함
                guard case .second(true, let drag?) = value else { return }  // 움직임이 실제로 생긴 뒤에만
                if dragID != e.id { dragID = e.id; selectedID = e.id; lastStep = 0; Haptics.impact(.medium) }
                dragDY = drag.translation.height
                let step = Int(dragMinutes(dragDY))
                if step != lastStep { lastStep = step; Haptics.impact(.light) }
                let nowInTrash = drag.location.y > viewportH - 64
                if nowInTrash != inTrash { inTrash = nowInTrash; if nowInTrash { Haptics.impact(.rigid) } }
            }
            .onEnded { _ in
                if dragID == e.id {
                    if inTrash { EventActions.deleteSingle(e, in: context); Haptics.notify(.warning) }
                    else if dragMinutes(dragDY) != 0 { commitDrag(e); Haptics.impact(.soft) }
                }
                dragID = nil; dragDY = 0; inTrash = false; lastStep = 0
            }
    }

    // MARK: 동작
    private func addAt(y: CGFloat) {
        if selectedID != nil { selectedID = nil; return }   // 선택된 게 있으면 먼저 해제
        let mins = Double(y) / Double(hourHeight) * 60
        let snapped = (mins / 30).rounded(.down) * 30
        let date = gridTop.addingTimeInterval(snapped * 60)
        onAdd(date)
    }
    private func commitDrag(_ e: ScheduleEvent) {
        let mins = dragMinutes(dragDY)
        let dur = e.end.timeIntervalSince(e.start)
        e.start = e.start.addingTimeInterval(mins * 60)
        e.end = e.start.addingTimeInterval(dur)
        try? context.save()
    }
    private func dragMinutes(_ dy: CGFloat) -> Double { (Double(dy) / Double(hourHeight) * 60 / 5).rounded() * 5 }

    // MARK: 레이아웃 — 기본 풀폭(겹쳐도 안 줄임). 제목 텍스트끼리 세로로 겹칠 때만 그 그룹을 N등분.
    private struct Laid { let event: ScheduleEvent; let col: Int; let cols: Int; let order: Int }
    private let textBand: CGFloat = 22   // 제목이 겹치는 세로 간격(pt)
    private var laidOut: [Laid] {
        let evs = plan.singleDayEvents.sorted { $0.start < $1.start }
        var result: [Laid] = []
        var i = 0
        while i < evs.count {
            // 시작 위치가 textBand 이내로 인접한 것들 = 제목 충돌 그룹
            var group = [evs[i]]
            var lastY = yOffset(for: clamp(evs[i].start))
            var j = i + 1
            while j < evs.count {
                let y = yOffset(for: clamp(evs[j].start))
                if y - lastY < textBand { group.append(evs[j]); lastY = y; j += 1 } else { break }
            }
            for (ci, e) in group.enumerated() { result.append(Laid(event: e, col: ci, cols: group.count, order: result.count)) }
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
    private func hourLabel(_ h: Int) -> String {
        let h12 = h % 12 == 0 ? 12 : h % 12
        if lang.isEnglish { return "\(h12) \(h < 12 || h == 24 ? "AM" : "PM")" }
        return "\(h < 12 || h == 24 ? "오전" : "오후") \(h12)시"
    }
    private func timeText(_ d: Date) -> String { d.formatted(.dateTime.hour().minute().locale(lang.locale)) }
}

// MARK: - 스크롤 진행량 추적(앵커 대비) — 타임라인 연속 접기. iOS 18+에서만, 그 이하는 그대로
private extension View {
    @ViewBuilder
    func trackScrollDelta(enabled: Bool,
                          base: Binding<CGFloat?>,
                          onDelta: ((CGFloat) -> Void)?) -> some View {
        if #available(iOS 18, *), enabled {
            self.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                if base.wrappedValue == nil { base.wrappedValue = y }
                onDelta?(y - (base.wrappedValue ?? y))   // 앵커(처음 보여준 위치) 대비 이동량
            }
        } else {
            self
        }
    }
}
