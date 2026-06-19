import SwiftUI

/// 인앱 무지개 타임라인 바 (packed).
/// 일정을 빈틈없이 붙여 바를 채우고, 진행 중이면 그 칸 안에서 선이 이동,
/// 쉬는 시간엔 다음 칸 경계에 선이 멈춥니다.
struct TimelineBar: View {
    let plan: DayPlan
    var height: CGFloat = 16

    private var layout: PackedLayout {
        PackedLayout(intervals: plan.events.map { (start: $0.start, end: $0.end) })
    }

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let current = plan.current(at: now)
            let waiting = layout.isWaiting(at: now)

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                        .frame(height: height)
                        .frame(maxHeight: .infinity, alignment: .center)

                    ForEach(Array(plan.events.enumerated()), id: \.element.id) { idx, event in
                        let slot = layout.slots[idx]
                        let isCurrent = current?.id == event.id
                        let isPast = now >= event.end

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(EventPalette.color(idx))
                            .frame(width: max(2, slot.width * w - 1.5),
                                   height: height * (isCurrent ? 1.45 : 1))
                            .opacity(isPast ? 0.25 : (isCurrent ? 1 : 0.5))
                            .shadow(color: isCurrent ? EventPalette.color(idx).opacity(0.6) : .clear,
                                    radius: 6, y: 3)
                            .offset(x: slot.left * w + 0.75)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }

                    // 현재-시각 선 (쉬는 시간엔 경계에 정지 + 흐려짐)
                    let px = layout.fraction(at: now) * w
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
            .animation(.easeInOut(duration: 0.35), value: current?.id)
        }
    }
}
