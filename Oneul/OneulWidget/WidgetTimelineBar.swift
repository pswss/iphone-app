import SwiftUI
import WidgetKit

/// 위젯/Live Activity용 무지개 바 (packed).
/// 단일일 일정은 무지개 칸, 멀티데이 일정은 바 위 흰 밴드(지난 부분은 안 빛남, 갱신 시점 기준).
struct WidgetTimelineBar: View {
    let segments: [EventSnapshot]           // ActivityKit 비의존 — Live Activity(ContentState.segments)·홈 위젯(HomeSnapshot.segments) 공용
    var height: CGFloat = 14

    private var single: [EventSnapshot] { segments.filter { !$0.isMultiDay } }
    private var multi: [EventSnapshot] { segments.filter { $0.isMultiDay } }
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

                    ForEach(Array(layout.segments.enumerated()), id: \.offset) { _, sl in
                        let span = max(1, sl.end.timeIntervalSince(sl.start))
                        let multi = sl.eventIndices.count > 1
                        ForEach(sl.eventIndices.sorted { single[$0].start > single[$1].start }, id: \.self) { i in
                            let e = single[i]
                            let color = EventPalette.color(e.colorIndex, of: segments.count)
                            let isCurrent = now >= e.start && now < e.end
                            let isPast = now >= e.end
                            let f0 = min(max(e.start.timeIntervalSince(sl.start) / span, 0), 1)
                            let f1 = min(max(e.end.timeIntervalSince(sl.start) / span, 0), 1)

                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color)
                                .frame(width: max(2, sl.width * (f1 - f0) * w - 1.5), height: height)
                                .opacity(isPast ? 0.3 : (isCurrent ? 1 : (multi ? 0.62 : 0.55)))   // 겹치면 반투명 유리판
                                .overlay {
                                    if multi {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                                    }
                                }
                                .offset(x: (sl.left + sl.width * f0) * w + 0.75)
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
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
