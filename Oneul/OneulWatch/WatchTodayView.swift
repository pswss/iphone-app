import SwiftUI

struct WatchTodayView: View {
    @Environment(WatchStore.self) private var store

    private var p: WatchSchedulePayload { store.payload }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    highlight
                    if p.events.isEmpty {
                        Text("오늘 일정이 없어요")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                    } else {
                        ForEach(p.events) { row($0) }
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("오늘")
        }
    }

    /// 다음 일정(없으면 진행 중) 강조 카드.
    @ViewBuilder private var highlight: some View {
        if let title = p.nextTitle, let start = p.nextStart {
            card(tag: "다음", title: title, time: start, accent: .orange)
        } else if let title = p.currentTitle, let end = p.currentEnd {
            card(tag: "진행 중", title: title, time: end, accent: .green, isEnd: true)
        }
    }

    private func card(tag: String, title: String, time: Date, accent: Color, isEnd: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(accent)
            Text(title).font(.headline).lineLimit(2)
            Text(time, style: .relative)
                .font(.caption2).foregroundStyle(.secondary)
                + Text(isEnd ? " 남음" : " 후").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3).padding(.vertical, 8)
        }
    }

    private func row(_ e: EventSnapshot) -> some View {
        HStack(spacing: 8) {
            Text(e.start, format: .dateTime.hour().minute())
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Circle().fill(EventPalette.color(e.colorIndex)).frame(width: 7, height: 7)
            Text(e.title).font(.caption).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .opacity(e.end < Date() ? 0.45 : 1)   // 지난 일정은 흐리게
    }
}
