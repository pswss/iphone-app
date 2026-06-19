import SwiftUI

/// 애플 캘린더식 줄 캘린더.
/// - 접힘: 한 주만 표시, 좌우 스와이프(손가락 따라)로 이전/다음 주, 날짜 탭=선택.
/// - 헤더(월 이름/▼) 탭 → 월 달력으로 펼침. 펼침에서 좌우 스와이프=이전/다음 달, 날짜 탭=선택 후 접힘.
struct CalendarBar: View {
    @Binding var selectedDay: Date

    @State private var expanded = false
    @State private var weekIndex = 0
    @State private var monthIndex = 0

    private let cal = Calendar.current
    private let weekRange = -60...60
    private let monthRange = -30...30
    private let lang = AppLanguage.shared
    private var weekdaySymbols: [String] {
        lang.isEnglish ? ["S", "M", "T", "W", "T", "F", "S"] : ["일", "월", "화", "수", "목", "금", "토"]
    }

    var body: some View {
        VStack(spacing: 8) {
            headerRow
            if expanded {
                weekdayHeader
                monthPager
            } else {
                weekPager
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 22)
        .onAppear(perform: syncIndices)
        .onChange(of: selectedDay) { _, _ in syncIndices() }
    }

    // MARK: 헤더 (탭하면 펼침/접힘)
    private var headerRow: some View {
        Button(action: toggleExpanded) {
            HStack(spacing: 6) {
                Text(visibleMonth, format: .dateTime.year().month(.wide))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(Color.appAccentText)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    // MARK: 주 페이저
    private var weekPager: some View {
        TabView(selection: $weekIndex) {
            ForEach(weekRange, id: \.self) { idx in
                HStack(spacing: 4) {
                    ForEach(days(week: idx), id: \.self) { weekCell($0) }
                }
                .padding(.horizontal, 2)
                .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 58)
    }

    // MARK: 월 페이저
    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { i, s in
                Text(s).font(.caption2)
                    .foregroundStyle(i == 0 ? .red : (i == 6 ? .blue : .secondary))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthPager: some View {
        TabView(selection: $monthIndex) {
            ForEach(monthRange, id: \.self) { idx in
                monthGrid(monthStart(idx)).tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 250)
    }

    private func monthGrid(_ monthStart: Date) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
            ForEach(Array(monthDays(monthStart).enumerated()), id: \.offset) { _, day in
                if let day { monthCell(day) } else { Color.clear.frame(height: 34) }
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: 셀
    private func weekCell(_ date: Date) -> some View {
        let selected = cal.isDate(date, inSameDayAs: selectedDay)
        let today = cal.isDateInToday(date)
        return Button { select(date) } label: {
            VStack(spacing: 4) {
                Text(date, format: .dateTime.weekday(.narrow))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(verbatim: "\(cal.component(.day, from: date))")
                    .font(.subheadline).bold()
                    .frame(width: 32, height: 32)
                    .background { highlight(selected: selected, today: today) }
                    .foregroundStyle(dateColor(date, selected: selected))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// 날짜 숫자 색: 선택=대비색, 휴일·일요일=빨강, 토요일=파랑, 그 외=기본.
    private func dateColor(_ date: Date, selected: Bool) -> Color {
        if selected { return Color.appOnAccent }
        if Holidays.name(for: date) != nil { return .red }
        switch cal.component(.weekday, from: date) {
        case 1: return .red    // 일요일
        case 7: return .blue   // 토요일
        default: return .primary
        }
    }

    private func monthCell(_ date: Date) -> some View {
        let selected = cal.isDate(date, inSameDayAs: selectedDay)
        let today = cal.isDateInToday(date)
        return Button { select(date) } label: {
            Text(verbatim: "\(cal.component(.day, from: date))")
                .font(.subheadline)
                .frame(width: 34, height: 34)
                .background { highlight(selected: selected, today: today) }
                .foregroundStyle(dateColor(date, selected: selected))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func highlight(selected: Bool, today: Bool) -> some View {
        if selected {
            Circle().fill(Color.appAccent)
        } else if today {
            Circle().strokeBorder(Color.appAccentText, lineWidth: 1.5)
        }
    }

    // MARK: 동작
    private func toggleExpanded() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            if expanded {
                weekIndex = weekIdx(for: selectedDay)
            } else {
                monthIndex = monthIdx(for: visibleWeekMiddle)
            }
            expanded.toggle()
        }
    }

    private func select(_ date: Date) {
        withAnimation(.snappy(duration: 0.3)) { selectedDay = date }   // 메인 페이저도 슬라이드되도록
        if expanded {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { expanded = false }
        }
    }

    private func syncIndices() {
        weekIndex = weekIdx(for: selectedDay)
        monthIndex = monthIdx(for: selectedDay)
    }

    // MARK: 계산
    private var anchorWeekStart: Date {
        cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
    }
    private var anchorMonthStart: Date {
        cal.dateInterval(of: .month, for: Date())?.start ?? cal.startOfDay(for: Date())
    }
    private func weekStart(_ index: Int) -> Date {
        cal.date(byAdding: .weekOfYear, value: index, to: anchorWeekStart) ?? anchorWeekStart
    }
    private func monthStart(_ index: Int) -> Date {
        cal.date(byAdding: .month, value: index, to: anchorMonthStart) ?? anchorMonthStart
    }
    private func days(week index: Int) -> [Date] {
        let start = weekStart(index)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }
    private var visibleWeekMiddle: Date {
        cal.date(byAdding: .day, value: 3, to: weekStart(weekIndex)) ?? weekStart(weekIndex)
    }
    private var visibleMonth: Date {
        expanded ? monthStart(monthIndex) : visibleWeekMiddle
    }
    private func weekIdx(for date: Date) -> Int {
        let target = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return cal.dateComponents([.weekOfYear], from: anchorWeekStart, to: target).weekOfYear ?? 0
    }
    private func monthIdx(for date: Date) -> Int {
        let target = cal.dateInterval(of: .month, for: date)?.start ?? date
        return cal.dateComponents([.month], from: anchorMonthStart, to: target).month ?? 0
    }
    private func monthDays(_ monthStart: Date) -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthStart)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            cells.append(cal.date(byAdding: .day, value: d - 1, to: monthStart))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
