import Foundation
import AVFoundation
import UserNotifications

/// 톤 하나 — Library/Sounds의 .caf 파일.
struct Tone: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var fileName: String        // Library/Sounds 내 파일명
    var isPreset: Bool
    var duration: TimeInterval

    var url: URL { ToneStore.soundsDir.appendingPathComponent(fileName) }
}

/// 톤 저장소 — 프리셋(자체 신디사이즈) + 사용자 커스텀(트림). 전부 이 앱 알림 전용.
@Observable
final class ToneStore {
    static let shared = ToneStore()

    private(set) var tones: [Tone] = []
    var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedTone") }
    }

    static var soundsDir: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "tones"),
           let list = try? JSONDecoder().decode([Tone].self, from: data) {
            tones = list.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        }
        if let raw = UserDefaults.standard.string(forKey: "selectedTone") {
            selectedID = UUID(uuidString: raw)
        }
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(tones), forKey: "tones")
    }

    var selected: Tone? { tones.first { $0.id == selectedID } }

    /// 선택된 톤의 알림 사운드 — 없으면 시스템 기본음.
    var notificationSound: UNNotificationSound {
        guard let t = selected, FileManager.default.fileExists(atPath: t.url.path) else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(t.fileName))
    }

    func add(_ tone: Tone) {
        tones.append(tone)
        persist()
    }

    func remove(_ tone: Tone) {
        guard !tone.isPreset else { return }
        try? FileManager.default.removeItem(at: tone.url)
        tones.removeAll { $0.id == tone.id }
        if selectedID == tone.id { selectedID = nil }
        persist()
    }

    func rename(_ tone: Tone, to name: String) {
        guard let i = tones.firstIndex(of: tone) else { return }
        tones[i].name = name
        persist()
    }

    // MARK: 프리셋 — 코드로 합성한 '기본 알림음' 5종(저작권 청정)
    func installPresetsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "presetsInstalled") else { return }
        let specs: [(String, [Synth.Note])] = [
            ("딩동", [.init(freq: 659.3, at: 0.00, len: 0.45),      // E5 → C5 (초인종)
                     .init(freq: 523.3, at: 0.28, len: 0.70)]),
            ("벨", [.init(freq: 880, at: 0, len: 1.2, harmonics: true)]),
            ("차임", [.init(freq: 523.3, at: 0.00, len: 0.5),
                     .init(freq: 659.3, at: 0.16, len: 0.5),
                     .init(freq: 784.0, at: 0.32, len: 0.9)]),
            ("또록", [.init(freq: 1046.5, at: 0.00, len: 0.12),
                     .init(freq: 1318.5, at: 0.14, len: 0.18)]),
            ("콩콩", [.init(freq: 392, at: 0.00, len: 0.16),
                     .init(freq: 392, at: 0.22, len: 0.28)]),
        ]
        for (name, notes) in specs {
            let file = "preset-\(name).caf"
            let url = Self.soundsDir.appendingPathComponent(file)
            if let dur = try? Synth.render(notes: notes, to: url) {
                add(Tone(id: UUID(), name: name, fileName: file, isPreset: true, duration: dur))
            }
        }
        if selectedID == nil { selectedID = tones.first?.id }
        UserDefaults.standard.set(true, forKey: "presetsInstalled")
    }

    // MARK: 커스텀 — 원본에서 [start, end) 구간을 알림음 포맷(.caf, Linear PCM)으로 렌더
    func importTrimmed(source: URL, start: TimeInterval, end: TimeInterval, name: String) throws -> Tone {
        let file = "custom-\(UUID().uuidString.prefix(8)).caf"
        let dest = Self.soundsDir.appendingPathComponent(file)

        let asset = try AVAudioFile(forReading: source)
        let fmt = asset.processingFormat
        let sr = fmt.sampleRate
        let clampedEnd = min(end, Double(asset.length) / sr)
        let len = max(0.1, clampedEnd - start)
        asset.framePosition = AVAudioFramePosition(max(0, start) * sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(len * sr)) else {
            throw NSError(domain: "Tone", code: 1)
        }
        try asset.read(into: buf, frameCount: AVAudioFrameCount(len * sr))

        let out = try AVAudioFile(forWriting: dest, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: fmt.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try out.write(from: buf)

        let tone = Tone(id: UUID(), name: name, fileName: file, isPreset: false, duration: len)
        add(tone)
        return tone
    }

    /// 파형 표시용 다운샘플(RMS).
    static func waveform(of url: URL, bins: Int = 120) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let total = AVAudioFrameCount(file.length)
        guard total > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: total),
              (try? file.read(into: buf)) != nil,
              let ch = buf.floatChannelData?[0] else { return [] }
        let n = Int(buf.frameLength)
        let per = max(1, n / bins)
        var out: [Float] = []
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

/// 간단 신디사이저 — 사인(+배음) 노트들을 감쇠 포락선으로 합성해 .caf로.
enum Synth {
    struct Note { let freq: Double; let at: TimeInterval; let len: TimeInterval; var harmonics = false }

    static func render(notes: [Note], to url: URL, sampleRate: Double = 44100) throws -> TimeInterval {
        let total = (notes.map { $0.at + $0.len }.max() ?? 1) + 0.15
        let frames = Int(total * sampleRate)
        var pcm = [Float](repeating: 0, count: frames)

        for n in notes {
            let s = Int(n.at * sampleRate)
            let e = min(frames, s + Int(n.len * sampleRate))
            for i in s..<e {
                let t = Double(i - s) / sampleRate
                let env = exp(-4.5 * t / n.len)                       // 자연스러운 감쇠
                var v = sin(2 * .pi * n.freq * t)
                if n.harmonics {
                    v += 0.4 * sin(2 * .pi * n.freq * 2.76 * t)       // 벨 특유의 비정수 배음
                    v += 0.2 * sin(2 * .pi * n.freq * 5.40 * t)
                }
                pcm[i] += Float(v * env * 0.55)
            }
        }
        // 클리핑 방지 정규화
        let peak = max(pcm.map(abs).max() ?? 1, 0.0001)
        if peak > 0.98 { for i in 0..<frames { pcm[i] /= peak / 0.98 } }

        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames)) else {
            throw NSError(domain: "Synth", code: 1)
        }
        buf.frameLength = AVAudioFrameCount(frames)
        memcpy(buf.floatChannelData![0], pcm, frames * MemoryLayout<Float>.size)

        try? FileManager.default.removeItem(at: url)
        let out = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try out.write(from: buf)
        return total
    }
}
