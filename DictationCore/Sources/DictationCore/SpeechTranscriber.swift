import AVFoundation
import Speech

/// Streams PCM chunks into Apple's speech recogniser, on device when the language allows it.
@MainActor
public final class SpeechTranscriber {
    public enum Update: Sendable {
        case partial(String)
        case finished(String)
        /// Recognition ended early; the associated value says why.
        case failed(String)
    }

    public static var isAuthorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var sampleRate = 0.0

    /// Fails when neither `locale` nor US English is supported.
    public init?(locale: Locale = .current) {
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        else { return nil }
        self.recognizer = recognizer
    }

    public var isAvailable: Bool { recognizer.isAvailable }

    /// Starts a recognition pass. `onUpdate` receives partial transcripts on the main actor,
    /// then exactly one `.finished` carrying the final transcript, or one `.failed`.
    public func begin(sampleRate: Double, onUpdate: @escaping @MainActor (Update) -> Void) {
        cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        #if targetEnvironment(simulator)
        // The simulator reports on-device support but ships no speech model, so recognition
        // there only works over the network.
        request.requiresOnDeviceRecognition = false
        #else
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        #endif
        self.request = request
        self.sampleRate = sampleRate
        // The recogniser calls back on the main queue.
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, self.request === request else { return }
            if let result, !result.isFinal, error == nil {
                return onUpdate(.partial(result.bestTranscription.formattedString))
            }
            self.request = nil
            self.task = nil
            if let result, result.isFinal {
                onUpdate(.finished(result.bestTranscription.formattedString))
            } else {
                onUpdate(.failed(error?.localizedDescription ?? "Speech recognition stopped"))
            }
        }
    }

    public func feed(_ pcm: Data) {
        guard let request, let buffer = AVAudioPCMBuffer(int16Mono: pcm, sampleRate: sampleRate) else { return }
        request.append(buffer)
    }

    /// Signals the end of speech; the final transcript arrives through `onUpdate`.
    public func finish() {
        request?.endAudio()
    }

    /// Abandons the current pass without delivering further updates.
    public func cancel() {
        task?.cancel()
        task = nil
        request = nil
    }
}
