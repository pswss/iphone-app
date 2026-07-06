import SwiftUI
import AVFoundation
import UserNotifications
import UniformTypeIdentifiers

/// 딩동 — 내 알림음 라이브러리.
/// 기본(프리셋) 톤 + 음원을 트림해 만든 커스텀 톤을 이 앱의 알림 소리로 쓴다.
struct ContentView: View {
    @State private var store = ToneStore.shared
    @State private var importing = false
    @State private var trimSource: URL?
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var showReminder = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        section("기본 알림음", tones: store.tones.filter(\.isPreset))
                        let customs = store.tones.filter { !$0.isPreset }
                        if !customs.isEmpty {
                            section("내가 만든 알림음", tones: customs)
                        }
                        importCard
                        reminderCard
                        if let toast {
                            Text(toast).font(.footnote).foregroundStyle(.secondary).transition(.opacity)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: store.tones)
                }
            }
            .navigationTitle("딩동")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { pickFile($0) }
            .sheet(item: Binding(get: { trimSource.map { TrimItem(url: $0) } },
                                 set: { trimSource = $0?.url })) { item in
                TrimSheet(source: item.url) { tone in
                    store.selectedID = tone.id
                    note("'\(tone.name)' 저장 — 이 앱 알림음으로 설정됐어요")
                }
            }
            .sheet(isPresented: $showReminder) { ReminderSheet { note($0) } }
            .task { await requestPermission() }
        }
    }

    private struct TrimItem: Identifiable { let url: URL; var id: URL { url } }

    // MARK: 톤 리스트
    private func section(_ title: String, tones: [Tone]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).bold().foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(tones.enumerated()), id: \.element.id) { i, tone in
                    toneRow(tone)
                    if i < tones.count - 1 { Divider().padding(.leading, 46) }
                }
            }
            .padding(.vertical, 4)
            .glassCard(cornerRadius: 22)
        }
    }

    private func toneRow(_ tone: Tone) -> some View {
        HStack(spacing: 12) {
            Button { play(tone) } label: {
                Image(systemName: playingID == tone.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2).foregroundStyle(Color.accentDeep)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(tone.name).font(.body)
                Text(String(format: "%.1f초", tone.duration))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if store.selectedID == tone.id {
                Image(systemName: "checkmark").font(.subheadline.bold())
                    .foregroundStyle(Color.accentDeep)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) { store.selectedID = tone.id }
            play(tone)
        }
        .contextMenu {
            if !tone.isPreset {
                Button(role: .destructive) { store.remove(tone) } label: { Label("삭제", systemImage: "trash") }
            }
            Button { testNotification() } label: { Label("테스트 알림", systemImage: "bell") }
        }
    }

    // MARK: 가져오기 / 알림 만들기
    private var importCard: some View {
        Button { importing = true } label: {
            HStack {
                Image(systemName: "waveform.badge.plus").font(.title3)
                Text("음원으로 알림음 만들기").font(.body).bold()
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .foregroundStyle(Color.accentDeep)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 22)
    }

    private var reminderCard: some View {
        VStack(spacing: 10) {
            Button { showReminder = true } label: {
                HStack {
                    Image(systemName: "bell.badge").font(.title3)
                    Text("이 소리로 알림 만들기").font(.body).bold()
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .foregroundStyle(Color.accentDeep)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            Button { testNotification() } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("3초 뒤 테스트 알림").font(.subheadline)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }

    // MARK: 동작
    private func pickFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("import." + (url.pathExtension.isEmpty ? "m4a" : url.pathExtension))
        try? FileManager.default.removeItem(at: tmp)
        do {
            try FileManager.default.copyItem(at: url, to: tmp)
            trimSource = tmp
        } catch { note("파일을 읽지 못했어요") }
    }

    private func play(_ tone: Tone) {
        if playingID == tone.id { player?.stop(); playingID = nil; return }
        guard let p = try? AVAudioPlayer(contentsOf: tone.url) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        p.play()
        player = p
        playingID = tone.id
        Task {
            try? await Task.sleep(nanoseconds: UInt64(tone.duration * 1_000_000_000) + 100_000_000)
            if playingID == tone.id { playingID = nil }
        }
    }

    private func testNotification() {
        let content = UNMutableNotificationContent()
        content.title = "딩동"
        content.body = store.selected.map { "'\($0.name)' 소리예요" } ?? "기본 알림음이에요"
        content.sound = store.notificationSound
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
        UNUserNotificationCenter.current().add(req)
        note("3초 뒤에 울려요 — 홈으로 나가도 돼요")
    }

    private func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    private func note(_ s: String) {
        withAnimation { toast = s }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { if toast == s { toast = nil } }
        }
    }
}

// MARK: - 트리머 시트 (사진 앱 비디오 트림 감성)

struct TrimSheet: View {
    let source: URL
    var onSave: (Tone) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = "내 알림음"
    @State private var duration: TimeInterval = 0
    @State private var samples: [Float] = []
    @State private var start: TimeInterval = 0
    @State private var end: TimeInterval = 5
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var stopTask: Task<Void, Never>?
    @State private var error: String?

    private let maxLen: TimeInterval = 30

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 16) {
                    TextField("이름", text: $name)
                        .font(.headline)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .glassCard(cornerRadius: 16)

                    VStack(spacing: 12) {
                        WaveTrimmer(samples: samples, duration: duration,
                                    start: $start, end: $end, maxLength: maxLen)
                            .frame(height: 96)
                        HStack {
                            Text(timeText(start)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f초", end - start))
                                .font(.subheadline).bold().monospacedDigit()
                            Spacer()
                            Text(timeText(end)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Button { playing ? stop() : preview() } label: {
                            Label(playing ? "정지" : "미리 듣기", systemImage: playing ? "stop.fill" : "play.fill")
                                .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 22)

                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: 560)
            }
            .navigationTitle("알림음 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { stop(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }.bold()
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { load() }
            .onDisappear { stop() }
        }
    }

    private func load() {
        guard let f = try? AVAudioFile(forReading: source) else { error = "지원하지 않는 형식이에요"; return }
        duration = Double(f.length) / f.processingFormat.sampleRate
        samples = ToneStore.waveform(of: source)
        start = 0
        end = min(duration, 5)
    }

    private func preview() {
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: source) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        p.currentTime = start
        p.play()
        player = p
        playing = true
        let len = end - start
        stopTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(len * 1_000_000_000))
            if !Task.isCancelled { await MainActor.run { stop() } }
        }
    }

    private func stop() {
        stopTask?.cancel(); stopTask = nil
        player?.stop(); player = nil
        playing = false
    }

    private func save() {
        stop()
        do {
            let tone = try ToneStore.shared.importTrimmed(
                source: source, start: start, end: end,
                name: name.trimmingCharacters(in: .whitespaces))
            onSave(tone)
            dismiss()
        } catch { self.error = "저장하지 못했어요" }
    }

    private func timeText(_ t: TimeInterval) -> String {
        String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }
}

/// 파형 트리머 — 양쪽 핸들로 구간 선택.
struct WaveTrimmer: View {
    let samples: [Float]
    let duration: TimeInterval
    @Binding var start: TimeInterval
    @Binding var end: TimeInterval
    let maxLength: TimeInterval

    private let handleW: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let x0 = x(of: start, w: w)
            let x1 = x(of: end, w: w)

            ZStack(alignment: .leading) {
                wave(w: w, h: h).opacity(0.3)
                wave(w: w, h: h)
                    .mask(Rectangle().frame(width: max(0, x1 - x0)).offset(x: x0))

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentDeep, lineWidth: 3)
                    .frame(width: max(handleW * 2, x1 - x0), height: h)
                    .offset(x: x0)

                handle(left: true)
                    .position(x: x0 + handleW / 2, y: h / 2)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        let t = time(atX: v.location.x, w: w)
                        start = min(max(0, t), end - 0.5)
                        if end - start > maxLength { end = start + maxLength }
                    })
                handle(left: false)
                    .position(x: x1 - handleW / 2, y: h / 2)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        let t = time(atX: v.location.x, w: w)
                        end = max(min(duration, t), start + 0.5)
                        if end - start > maxLength { start = end - maxLength }
                    })
            }
        }
    }

    private func wave(w: CGFloat, h: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
                Capsule().fill(Color.accentDeep)
                    .frame(width: max(1, (w / CGFloat(max(samples.count, 1))) - 1.5),
                           height: max(3, CGFloat(s) * (h - 16)))
            }
        }
        .frame(width: w, height: h)
    }

    private func handle(left: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.accentDeep)
            .frame(width: handleW, height: 44)
            .overlay(Image(systemName: left ? "chevron.compact.left" : "chevron.compact.right")
                .font(.caption.bold()).foregroundStyle(.white))
            .contentShape(Rectangle().inset(by: -12))
    }

    private func x(of t: TimeInterval, w: CGFloat) -> CGFloat {
        duration > 0 ? CGFloat(t / duration) * w : 0
    }
    private func time(atX px: CGFloat, w: CGFloat) -> TimeInterval {
        Double(min(max(0, px), w) / w) * duration
    }
}

// MARK: - 알림 만들기 시트

struct ReminderSheet: View {
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date().addingTimeInterval(60)

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 14) {
                    TextField("무엇을 알려드릴까요?", text: $title)
                        .font(.headline)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .glassCard(cornerRadius: 16)
                    DatePicker("시각", selection: $date, in: Date()...)
                        .datePickerStyle(.graphical)
                        .padding(12)
                        .glassCard(cornerRadius: 22)
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: 560)
            }
            .navigationTitle("알림 만들기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") { add() }.bold()
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func add() {
        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = ToneStore.shared.notificationSound
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content,
                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        UNUserNotificationCenter.current().add(req)
        onDone(date.formatted(.dateTime.month().day().hour().minute()) + "에 울려요")
        dismiss()
    }
}
