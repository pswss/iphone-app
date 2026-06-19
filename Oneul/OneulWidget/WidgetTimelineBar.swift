import SwiftUI
import WidgetKit

/// 위젯/Live Activity용 무지개 바 (packed).
/// 일정을 빈틈없이 붙여 바를 채우고, 진행 위치 선을 그립니다.
/// (쉬는 시간엔 다음 칸 경계에 정지 — 업데이트 시점 기준)
struct WidgetTimelineBar: View {
    let state: ScheduleActivityAttributes.ContentState
    var height: CGFloat = 14

    private var layout: PackedLayout {
        PackedLayout(intervals: state.segments.map { (start: $0.start, end: $0.end) })
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let now = Date()
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: height)
                    .frame(maxHeight: .infinity, alignment: .center)

                ForEach(Array(state.segments.enumerated()), id: \.element.id) { idx, seg in
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

                let px = layout.fraction(at: now) * w
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
