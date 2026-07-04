import SwiftUI

/// 인앱 무지개 타임라인 바 (packed).
/// 단일일 일정은 빈틈없이 붙인 무지개 칸으로, 멀티데이 일정은 바 위쪽 흰 글로우 밴드로 표시.
/// `live`가 true(오늘)일 때만 매 프레임 애니메이션 — 다른 날은 정적으로 그려 스와이프 부드럽게.
struct TimelineBar: View {
    let plan: DayPlan
    var height: CGFloat = 16
    var live: Bool = true

    private var single: [ScheduleEvent] { plan.singleDayEvents }
    private var layout: PackedLayout {
        PackedLayout(intervals: single.map { (start: $0.start, end: $0.end) })
    }
    private var bandCount: Int { plan.multiDayEvents.isEmpty ? 0 : 1 }   // 밴드는 한 줄만

    var body: some View {
        if live {
            TimelineView(.animation) { context in barContent(now: context.date) }
        } else {
            barContent(now: Date())
        }
    }

    @ViewBuilder
    private func barContent(now: Date) -> some View {
        let current = plan.current(at: now)
        let waiting = layout.isWaiting(at: now)
        let frac = layout.fraction(at: now)

        GeometryReader { geo in
            let w = geo.size.width
            VStack(spacing: 5) {
                if !plan.multiDayEvents.isEmpty {     // 멀티데이 밴드는 모두 동일하므로 한 줄만(여러 개여도 안 길어지게)
                    multiDayBand(width: w, fraction: frac)
                }

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                        .frame(height: height)
                        .frame(maxHeight: .infinity, alignment: .center)

                    ForEach(Array(layout.segments.enumerated()), id: \.offset) { _, seg in
                        let span = max(1, seg.end.timeIntervalSince(seg.start))
                        let multi = seg.eventIndices.count > 1
                        // 스테인글라스: 늦게 시작하는 일정을 먼저(뒤층) 그려 앞 일정 뒤로 비치게
                        ForEach(seg.eventIndices.sorted { single[$0].start > single[$1].start }, id: \.self) { i in
                            let e = single[i]
                            let color = EventPalette.color(plan.colorIndex(of: e), of: plan.events.count)
                            let isCurrent = current?.id == e.id
                            let isPast = now >= e.end
                            let f0 = min(max(e.start.timeIntervalSince(seg.start) / span, 0), 1)
                            let f1 = min(max(e.end.timeIntervalSince(seg.start) / span, 0), 1)

                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color)
                                .frame(width: max(2, seg.width * (f1 - f0) * w - 1.5),
                                       height: height * (isCurrent ? 1.15 : 1))   // 현재 일정 강조 높이
                                .opacity(isPast ? 0.25 : (isCurrent ? 1 : (multi ? 0.6 : 0.5)))   // 겹치면 반투명 유리판 → 뒤가 비침
                                .overlay {
                                    if multi {   // 각 유리판 윤곽 → '두 개'임이 보이게
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                                    }
                                }
                                .shadow(color: isCurrent ? color.opacity(0.6) : .clear, radius: 6, y: 3)
                                .offset(x: (seg.left + seg.width * f0) * w + 0.75)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                    }

                    if !single.isEmpty && live {
                        let px = frac * w
                        Capsule()
                            .fill(.white)
                            .frame(width: 2, height: height + 12)
                            .opacity(waiting ? 0.55 : 1)
                            .shadow(color: .white.opacity(0.85), radius: 4)
                            .offset(x: px - 1)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(height: height + 14)
            }
        }
        .frame(height: CGFloat(bandCount) * 12 + height + 14)
        .animation(.easeInOut(duration: 0.35), value: current?.id)
    }

    /// 멀티데이 흰 밴드: 지난 부분(흐림) + 남은 부분(흰 글로우).
    private func multiDayBand(width w: CGFloat, fraction f: Double) -> some View {
        let px = max(0, min(w, f * w))
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.16))
                .frame(width: px, height: 6)
            Capsule().fill(.white)
                .frame(width: max(0, w - px), height: 6)
                .shadow(color: .white.opacity(0.9), radius: 7)
                .shadow(color: .white.opacity(0.45), radius: 14)
                .offset(x: px)
        }
        .frame(width: w, height: 7, alignment: .leading)
    }
}
