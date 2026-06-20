import Foundation
import Speech
import AVFoundation

/// 한국어 받아쓰기(온디바이스/서버). 토글로 녹음 → `transcript` 갱신.
@Observable
final class SpeechRecognizer {
    var transcript = ""
    var isRecording = false

    @ObservationIgnored private lazy var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko_KR"))   // 첫 녹음 때 생성(AI 탭 진입 렉↓)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private lazy var engine = AVAudioEngine()
    private var wantsRecording = false   // 꾹 누르는 동안 true. 권한 비동기 처리 중 떼면 begin을 막는다.

    func toggle() { isRecording ? stop() : start() }

    func start() {
        wantsRecording = true
        transcript = ""
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else { return }
                DispatchQueue.main.async { self.begin() }
            }
        }
    }

    private func begin() {
        guard wantsRecording, let recognizer, recognizer.isAvailable else { return }   // 이미 손을 뗐으면 시작 안 함
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)

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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
