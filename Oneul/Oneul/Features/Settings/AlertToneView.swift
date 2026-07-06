#if os(iOS)
import SwiftUI
import AVFoundation
import UserNotifications
import UniformTypeIdentifiers

/// 커스텀 알림음 — 음원 파일을 가져와 애플식 파형 트리머로 구간(≤30초)을 골라
/// 이 앱의 알림음으로 저장한다. (시스템 전체 벨소리가 아니라 Oneul 알림 전용)
enum AlertTone {
    static let fileName = "oneul-alert.caf"

    static var soundsDir: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var fileURL: URL { soundsDir.appendingPathComponent(fileName) }
    static var isSet: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// 알림에 쓸 사운드 — 커스텀이 있으면 그것, 없으면 기본음.
    static var notificationSound: UNNotificationSound {
        isSet ? UNNotificationSound(named: UNNotificationSoundName(fileName)) : .default
    }

    static func remove() { try? FileManager.default.removeItem(at: fileURL) }

    /// 원본에서 [start, end) 구간을 Linear PCM .caf로 렌더(알림음 허용 포맷).
    static func render(source: URL, start: TimeInterval, end: TimeInterval) throws {
        let asset = try AVAudioFile(forReading: source)
        let fmt = asset.processingFormat
        let sr = fmt.sampleRate
        let from = AVAudioFramePosition(max(0, start) * sr)
        let count = AVAudioFrameCount(max(0.1, min(end, Double(asset.length) / sr) - start) * sr)

        asset.framePosition = from
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: count) else {
            throw NSError(domain: "AlertTone", code: 1)
        }
        try asset.read(into: buf, frameCount: count)

        try? FileManager.default.removeItem(at: fileURL)
        let out = try AVAudioFile(forWriting: fileURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: fmt.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try out.write(from: buf)
    }

    /// 파형 표시용 다운샘플(RMS) — bins개 막대.
    static func waveform(of url: URL, bins: Int = 120) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let fmt = file.processingFormat
        let total = AVAudioFrameCount(file.length)
        guard total > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: total),
              (try? file.read(into: buf)) != nil,
              let ch = buf.floatChannelData?[0] else { return [] }
        let n = Int(buf.frameLength)
        let per = max(1, n / bins)
        var out: [Float] = []
        out.reserveCapacity(bins)
        var i = 0
        while i < n {
            var acc: Float = 0
            let hi = min(i + per, n)
            for j in i..<hi { acc += ch[j] * ch[j] }
            out.append(sqrt(acc / Float(hi - i)))
            i = hi
        }
        let peak = max(out.max() ?? 1, 0.0001)
        return out.map { min(1, $0 / peak) }
    }
}

/// 설정 시트 — 가져오기 → 파형 트리머 → 저장/미리듣기/기본음 복원.
struct AlertToneView: View {
    @Environment(\.dismiss) private var dismiss
    private let lang = AppLanguage.shared

    @State private var importing = false
    @State private var sourceURL: URL?
    @State private var duration: TimeInterval = 0
    @State private var samples: [Float] = []
    @State private var trimStart: TimeInterval = 0
    @State private var trimEnd: TimeInterval = 5
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var stopTask: Task<Void, Never>?
    @State private var message: String?
    @State private var isCustomSet = AlertTone.isSet

    private let maxLen: TimeInterval = 30

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        statusCard
                        if sourceURL != nil { trimmerCard }
                        if let message {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                                .transition(.opacity)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: sourceURL)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isCustomSet)
                }
            }
            .navigationTitle(lang.tr("알림음"))
            .navBarInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(lang.tr("닫기")) { close() } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { load($0) }
            .onDisappear { stopPreview() }
        }
    }

    // MARK: 상태 + 가져오기
    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: isCustomSet ? "bell.badge.waveform.fill" : "bell.badge.waveform")
                    .font(.title2).foregroundStyle(Color.appAccentText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isCustomSet ? lang.tr("커스텀 알림음 사용 중") : lang.tr("기본 알림음"))
                        .font(.body).bold()
                    Text(lang.tr("Oneul의 일정·시험 알림에 쓰여요"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Button {
                    importing = true
                } label: {
                    Label(lang.tr("음원 가져오기"), systemImage: "waveform.badge.plus")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                if isCustomSet {
                    Button {
                        AlertTone.remove()
                        isCustomSet = false
                        message = lang.tr("기본 알림음으로 되돌렸어요")
                    } label: {
                        Text(lang.tr("기본음으로")).font(.subheadline)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }

    // MARK: 트리머
    private var trimmerCard: some View {
        VStack(spacing: 14) {
            WaveTrimmer(samples: samples, duration: duration,
                        start: $trimStart, end: $trimEnd, maxLength: maxLen)
                .frame(height: 96)

            HStack {
                Text(timeText(trimStart)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f%@", trimEnd - trimStart, lang.tr("초")))
                    .font(.subheadline).bold().monospacedDigit()
                Spacer()
                Text(timeText(trimEnd)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    playing ? stopPreview() : preview()
                } label: {
                    Label(playing ? lang.tr("정지") : lang.tr("미리 듣기"),
                          systemImage: playing ? "stop.fill" : "play.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                Button {
                    save()
                } label: {
                    Label(lang.tr("알림음으로 저장"), systemImage: "checkmark")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: 동작
    private func load(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // 보안 스코프 밖에서도 읽을 수 있게 임시 복사
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tone-src." + (url.pathExtension.isEmpty ? "m4a" : url.pathExtension))
        try? FileManager.default.removeItem(at: tmp)
        do { try FileManager.default.copyItem(at: url, to: tmp) } catch {
            message = lang.tr("파일을 읽지 못했어요"); return
        }
        guard let f = try? AVAudioFile(forReading: tmp) else {
            message = lang.tr("지원하지 않는 오디오 형식이에요"); return
        }
        sourceURL = tmp
        duration = Double(f.length) / f.processingFormat.sampleRate
        samples = AlertTone.waveform(of: tmp)
        trimStart = 0
        trimEnd = min(duration, 5)
        message = nil
        stopPreview()
    }

    private func preview() {
        guard let src = sourceURL else { return }
        stopPreview()
        guard let p = try? AVAudioPlayer(contentsOf: src) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        p.currentTime = trimStart
        p.play()
        player = p
        playing = true
        let len = trimEnd - trimStart
        stopTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(len * 1_000_000_000))
            if !Task.isCancelled { await MainActor.run { stopPreview() } }
        }
    }

    private func stopPreview() {
        stopTask?.cancel(); stopTask = nil
        player?.stop(); player = nil
        playing = false
    }

    private func save() {
        guard let src = sourceURL else { return }
        stopPreview()
        do {
            try AlertTone.render(source: src, start: trimStart, end: trimEnd)
            isCustomSet = true
            message = lang.tr("저장했어요 — 다음 알림부터 이 소리로 울려요")
            Haptics.notify(.success)
        } catch {
            message = lang.tr("저장하지 못했어요")
        }
    }

    private func close() {
        stopPreview()
        dismiss()
    }

    private func timeText(_ t: TimeInterval) -> String {
        String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }
}

/// 애플식 파형 트리머 — 노란 프레임 핸들 두 개로 구간 선택(사진 앱 비디오 트리머 감성).
private struct WaveTrimmer: View {
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
                // 파형(전체 — 바깥은 흐리게)
                wave(w: w, h: h).opacity(0.3)
                wave(w: w, h: h)
                    .mask(Rectangle().frame(width: max(0, x1 - x0)).offset(x: x0))

                // 선택 프레임
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.appAccent, lineWidth: 3)
                    .frame(width: max(handleW * 2, x1 - x0), height: h)
                    .offset(x: x0)

                handle(edge: .leading)
                    .position(x: x0 + handleW / 2, y: h / 2)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        let t = time(atX: v.location.x, w: w)
                        start = min(max(0, t), end - 0.5)
                        if end - start > maxLength { end = start + maxLength }
                    })
                handle(edge: .trailing)
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
                Capsule().fill(Color.appAccentText)
                    .frame(width: max(1, (w / CGFloat(max(samples.count, 1))) - 1.5),
                           height: max(3, CGFloat(s) * (h - 16)))
            }
        }
        .frame(width: w, height: h)
    }

    private func handle(edge: HorizontalEdge) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.appAccent)
            .frame(width: handleW, height: 44)
            .overlay(Image(systemName: edge == .leading ? "chevron.compact.left" : "chevron.compact.right")
                .font(.caption.bold()).foregroundStyle(Color.appOnAccent))
            .contentShape(Rectangle().inset(by: -12))
    }

    private func x(of t: TimeInterval, w: CGFloat) -> CGFloat {
        duration > 0 ? CGFloat(t / duration) * w : 0
    }
    private func time(atX x: CGFloat, w: CGFloat) -> TimeInterval {
        Double(min(max(0, x), w) / w) * duration
    }
}
#endif
