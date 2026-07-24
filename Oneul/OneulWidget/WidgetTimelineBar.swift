import SwiftUI
import WidgetKit

/// 무지개 타임라인 바(위젯·Live Activity 공용) — Canvas 단일 패스 렌더.
///
/// 원래 GeometryReader + ForEach/offset 조합이었는데, Live Activity 렌더 환경에서
/// 그 계층 구조가 확장을 죽여 activity가 시작 직후 dismissed되는 문제가 있었다
/// (일정이 있을 때만 그려지므로 '일정 생기면 안 됨' 증상). Canvas는 뷰 계층 없이
/// 한 번에 그려 같은 비주얼을 안전하게 재현한다.
struct WidgetTimelineBar: View {
    let segments: [EventSnapshot]           // ActivityKit 비의존 — LA(ContentState)·홈 위젯(HomeSnapshot) 공용
    var height: CGFloat = 14

    private var single: [EventSnapshot] { segments.filter { !$0.isMultiDay } }
    private var multi: [EventSnapshot] { segments.filter { $0.isMultiDay } }

    var body: some View {
        let bandArea = CGFloat(multi.count) * 10
        Canvas { ctx, size in
            let w = size.width
            guard w > 0 else { return }
            let now = Date()
            let layout = PackedLayout(intervals: single.map { (start: $0.start, end: $0.end) })
            let frac = layout.fraction(at: now)

            // 멀티데이 흰 밴드(지난 부분 흐림 + 남은 부분 흰색)
            for (k, _) in multi.enumerated() {
                let y = CGFloat(k) * 10 + 2.5
                let px = max(0, min(w, frac * w))
                if px > 0 {
                    ctx.fill(Capsule().path(in: CGRect(x: 0, y: y, width: px, height: 5)),
                             with: .color(.white.opacity(0.16)))
                }
                if w - px > 0 {
                    ctx.fill(Capsule().path(in: CGRect(x: px, y: y, width: w - px, height: 5)),
                             with: .color(.white))
                }
            }

            let barY = bandArea + 5
            // 트랙
            ctx.fill(Capsule().path(in: CGRect(x: 0, y: barY, width: w, height: height)),
                     with: .color(.white.opacity(0.14)))

            // 일정 칸들 — 겹침 클러스터 안에서 실제 시각 비율로 배치(스테인글라스)
            for sl in layout.segments {
                let span = max(1, sl.end.timeIntervalSince(sl.start))
                let isOverlap = sl.eventIndices.count > 1
                for i in sl.eventIndices.sorted(by: { single[$0].start > single[$1].start }) {
                    let e = single[i]
                    let color = EventPalette.color(e.colorIndex, of: single.count)
                    let isCurrent = now >= e.start && now < e.end
                    let isPast = now >= e.end
                    let f0 = min(max(e.start.timeIntervalSince(sl.start) / span, 0), 1)
                    let f1 = min(max(e.end.timeIntervalSince(sl.start) / span, 0), 1)
                    let x = (sl.left + sl.width * f0) * w + 0.75
                    let bw = max(2, sl.width * (f1 - f0) * w - 1.5)
                    let rect = CGRect(x: x, y: barY, width: bw, height: height)
                    let shape = RoundedRectangle(cornerRadius: 3, style: .continuous).path(in: rect)
                    let alpha: Double = isPast ? 0.3 : (isCurrent ? 1 : (isOverlap ? 0.62 : 0.55))
                    ctx.fill(shape, with: .color(color.opacity(alpha)))
                    if isOverlap {
                        ctx.stroke(shape, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
                    }
                }
            }

            // 현재 위치 마커
            if !single.isEmpty {
                let px = max(1, min(w - 1, frac * w))
                let marker = Capsule().path(in: CGRect(x: px - 1, y: barY - 4, width: 2, height: height + 8))
                ctx.fill(marker, with: .color(.white))
            }
        }
        .frame(height: bandArea + height + 10)
    }
}
