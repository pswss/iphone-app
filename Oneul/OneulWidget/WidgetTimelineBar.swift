import SwiftUI
import WidgetKit

/// 위젯/Live Activity용 무지개 바 (packed).
/// 단일일 일정은 무지개 칸, 멀티데이 일정은 바 위 흰 밴드(지난 부분은 안 빛남, 갱신 시점 기준).
struct WidgetTimelineBar: View {
    let state: ScheduleActivityAttributes.ContentState
    var height: CGFloat = 14

    private var single: [EventSnapshot] { state.segments.filter { !$0.isMultiDay } }
    private var multi: [EventSnapshot] { state.segments.filter { $0.isMultiDay } }
    private var layout: PackedLayout {
        PackedLayout(intervals: single.map { (start: $0.start, end: $0.end) })
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let now = Date()
            let frac = layout.fraction(at: now)
            VStack(spacing: 4) {
                ForEach(multi) { _ in band(width: w, fraction: frac) }

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.14))
                        .frame(height: height)
                        .frame(maxHeight: .infinity, alignment: .center)

                    ForEach(Array(single.enumerated()), id: \.element.id) { idx, seg in
                        let slot = layout.slots[idx]
                        let isCurrent = now >= seg.start && now < seg.end
                        let isPast = now >= seg.end

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(EventPalette.color(seg.colorIndex))
                            .frame(width: max(2, slot.width * w - 1.5), height: height)
                            .opacity(isPast ? 0.3 : (isCurrent ? 1 : 0.55))
                            .offset(x: slot.left * w + 0.75)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }

                    if !single.isEmpty {
                        let px = frac * w
                        Capsule()
                            .fill(.white)
                            .frame(width: 2, height: height + 8)
                            .shadow(color: .white.opacity(0.8), radius: 3)
                            .offset(x: px - 1)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(height: height + 10)
            }
        }
        .frame(height: CGFloat(multi.count) * 10 + height + 10)
    }

    /// 멀티데이 흰 밴드: 지난 부분(흐림) + 남은 부분(흰 글로우).
    private func band(width w: CGFloat, fraction f: Double) -> some View {
        let px = max(0, min(w, f * w))
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.16)).frame(width: px, height: 5)
            Capsule().fill(.white).frame(width: max(0, w - px), height: 5)
                .shadow(color: .white.opacity(0.85), radius: 5)
                .offset(x: px)
        }
        .frame(width: w, height: 6, alignment: .leading)
    }
}
