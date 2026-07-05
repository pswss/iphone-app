import Foundation
import Speech
import AVFoundation

/// 한국어 받아쓰기(온디바이스/서버). 토글로 녹음 → `transcript` 갱신.
@Observable
final class SpeechRecognizer {
    var transcript = ""
    var isRecording = false
    var onDenied: (() -> Void)?   // 권한 거부 시 UI 피드백(무반응이 고장으로 오인되던 문제)

    // 앱 언어에 맞는 인식 로케일(영어 모드에서 한국어 인식 고정 문제)
    @ObservationIgnored private var recognizer: SFSpeechRecognizer? {
        if _recognizer == nil || _recognizerLang != AppLanguage.shared.code {
            _recognizerLang = AppLanguage.shared.code
            _recognizer = SFSpeechRecognizer(locale: AppLanguage.shared.locale)
        }
        return _recognizer
    }
    @ObservationIgnored private var _recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var _recognizerLang = ""
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private lazy var engine = AVAudioEngine()
    private var wantsRecording = false   // 꾹 누르는 동안 true. 권한 비동기 처리 중 떼면 begin을 막는다.

    func toggle() { isRecording ? stop() : start() }

    func start() {
        wantsRecording = true
        transcript = ""
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async { self.onDenied?() }
                return
            }
            #if os(iOS)
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else { DispatchQueue.main.async { self.onDenied?() }; return }
                DispatchQueue.main.async { self.begin() }
            }
            #else
            AVCaptureDevice.requestAccess(for: .audio) { granted in   // macOS: 오디오 세션 없이 마이크 권한만
                guard granted else { DispatchQueue.main.async { self.onDenied?() }; return }
                DispatchQueue.main.async { self.begin() }
            }
            #endif
        }
    }

    private func begin() {
        guard wantsRecording, let recognizer, recognizer.isAvailable else { return }   // 이미 손을 뗐으면 시작 안 함
        do {
            #if os(iOS)
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if error != nil || (result?.isFinal ?? false) { self.stop() }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        wantsRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
