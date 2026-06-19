import SwiftUI

struct EventRow: View {
    let event: ScheduleEvent
    let colorIndex: Int
    var isCurrent: Bool = false

    private let lang = AppLanguage.shared

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(EventPalette.color(colorIndex))
                .frame(width: 4)

            Text(timeText(event.start))
                .font(.caption).bold()
                .foregroundStyle(.secondary)
                .frame(width: 58)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? lang.tr("제목 없음") : event.title)
                    .font(.subheadline).bold()
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if isCurrent {
                Text("LIVE")
                    .font(.caption2).bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(red: 1, green: 0.27, blue: 0.23), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.appAccent, lineWidth: isCurrent ? 1.5 : 0)
        )
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(lang.locale))
    }

    private var subtitle: String {
        let s = timeText(event.start)
        let e = timeText(event.end)
        return event.location.isEmpty ? "\(s) – \(e)" : "\(s) – \(e) · \(event.location)"
    }
}
