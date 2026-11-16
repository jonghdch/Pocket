import AVFoundation
import OSLog
import Speech
import SwiftUI

/// 받아쓰기. 인식이 도중에 끝나도 다시 이어 붙여 긴 말을 받는다.
@MainActor
final class SpeechService: ObservableObject {
    enum Failure: Equatable { case denied, unavailable, noSpeech }

    @Published private(set) var isListening = false
    @Published private(set) var committed = ""
    @Published private(set) var partial = ""
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var startedAt: Date?
    @Published var failure: Failure?

    nonisolated private static let log = Logger(subsystem: "com.jonghdch.pocket", category: "speech")
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var heardAnything = false
    /// 지금 인식 요청이 글자를 하나라도 받았는지. 재시도 판단에 쓴다.
    private var taskHeard = false
    private var retry = RecognitionRetry(onDevice: true)

    var transcript: String {
        [committed, partial].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start(keeping text: String = "") async {
        guard !isListening else { return }
        failure = nil
        guard await Self.requestPermissions() else { failure = .denied; return }
        guard let recognizer, recognizer.isAvailable else { failure = .unavailable; return }
        committed = text
        partial = ""
        heardAnything = !text.isEmpty
        retry = RecognitionRetry(onDevice: recognizer.supportsOnDeviceRecognition)
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                let value = Self.rms(buffer)
                Task { @MainActor in self?.level = value }
            }
            engine.prepare()
            try engine.start()
            isListening = true
            startedAt = .now
            beginRecognition(onDevice: retry.onDevice)
        } catch {
            stopAudio()
            failure = .unavailable
        }
    }

    /// 인식을 끝내고 최종 글자를 돌려준다.
    @discardableResult
    func stop() -> String {
        guard isListening else { return transcript }
        let result = transcript
        commitPartial()
        stopAudio()
        if !heardAnything { failure = .noSpeech }
        return result
    }

    func discard() {
        stopAudio()
        committed = ""
        partial = ""
        failure = nil
    }

    private func beginRecognition(onDevice: Bool) {
        guard let recognizer else { return }
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.shouldReportPartialResults = true
        next.addsPunctuation = true
        next.requiresOnDeviceRecognition = onDevice
        request = next
        taskHeard = false
        task = recognizer.recognitionTask(with: next) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            if let error = error as NSError? {
                Self.log.error("recognition failed onDevice=\(onDevice) domain=\(error.domain, privacy: .public) code=\(error.code) \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in self?.handle(text: text, isFinal: isFinal, failed: failed, from: next) }
        }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, from source: SFSpeechAudioBufferRecognitionRequest) {
        guard source === request else { return } // 이전 인식의 뒤늦은 결과는 버린다.
        if let text, !text.isEmpty {
            partial = text
            heardAnything = true
            taskHeard = true
        }
        guard isFinal || failed else { return }
        commitPartial()
        guard isListening else { return }
        guard failed else {
            beginRecognition(onDevice: retry.onDevice) // 정상 끝: 이어서 듣는다.
            return
        }
        switch retry.afterFailure(heardText: taskHeard) {
        case .restart(let onDevice):
            beginRecognition(onDevice: onDevice)
        case .giveUp:
            // 실패가 이어지면 헛돌지 않고 멈춘다. 화면은 "음성 인식을 쓸 수 없어요"를 보여 준다.
            stopAudio()
            failure = .unavailable
        }
    }

    private func commitPartial() {
        committed = transcript
        partial = ""
    }

    private func stopAudio() {
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
        startedAt = nil
        level = 0
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return CGFloat(min(1, sqrt(sum / Float(count)) * 12))
    }
}
