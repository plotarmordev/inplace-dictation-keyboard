import AVFoundation
import DictationCore
import Observation

/// Drives one dictation at a time: microphone → speech recogniser → text field.
@MainActor @Observable
final class Dictation {
    enum Phase {
        /// The capture page is still loading.
        case preparing
        case idle
        /// Waiting for the microphone to open.
        case starting
        case listening
        /// The microphone is closed; waiting for the final transcript.
        case finishing
    }

    private(set) var phase = Phase.preparing
    /// Peak amplitude (0...1) of each audio chunk heard in this dictation, oldest first.
    private(set) var levels: [Float] = []
    /// Why dictation could not start or stopped early.
    private(set) var problem: String?

    let microphone = WebMicrophone()
    private let transcriber = SpeechTranscriber()
    private var typist = Typist()
    private let target: () -> TextTarget
    private let hasFullAccess: () -> Bool

    init(target: @escaping () -> TextTarget, hasFullAccess: @escaping () -> Bool) {
        self.target = target
        self.hasFullAccess = hasFullAccess
        microphone.onEvent = { [unowned self] in handle($0) }
    }

    func toggle() {
        switch phase {
        case .idle: start()
        case .starting, .listening: stop()
        case .preparing, .finishing: break
        }
    }

    /// Closes the microphone and keeps what was said.
    func stop() {
        guard phase == .starting || phase == .listening else { return }
        microphone.close()
        finish()
    }

    /// Closes the microphone and removes what this dictation typed.
    func cancel() {
        guard phase != .preparing, phase != .idle else { return }
        typist.update(to: "", in: target())
        abandon()
    }

    /// Ends the dictation without waiting for a final transcript.
    private func abandon() {
        microphone.close()
        transcriber?.cancel()
        phase = .idle
    }

    private func start() {
        problem = if !hasFullAccess() {
            "Allow Full Access in Settings"
        } else if AVAudioApplication.shared.recordPermission != .granted {
            "Allow the microphone in the InPlace app"
        } else if !SpeechTranscriber.isAuthorized {
            "Allow speech recognition in the InPlace app"
        } else if transcriber?.isAvailable != true {
            "Speech recognition is unavailable"
        } else {
            nil
        }
        guard problem == nil else { return }
        phase = .starting
        levels = []
        typist.begin(in: target())
        microphone.open()
    }

    private func handle(_ event: MicEvent) {
        switch (event, phase) {
        case (.ready, .preparing):
            phase = .idle
        case (.live(let sampleRate), .starting):
            phase = .listening
            transcriber?.begin(sampleRate: sampleRate) { [unowned self] in handle($0) }
        case (.audio(let pcm, let level), .listening):
            levels.append(level)
            transcriber?.feed(pcm)
        case (.live, _):
            // Opened after the dictation it was meant for was stopped.
            microphone.close()
        case (.ended(let reason), .starting), (.ended(let reason), .listening):
            // "closed" answers our own `close()`, which has been dealt with already.
            guard reason != "closed" else { break }
            problem = "Microphone stopped: \(reason)"
            finish()
        default:
            break
        }
    }

    private func handle(_ update: SpeechTranscriber.Update) {
        switch update {
        case .partial(let transcript):
            // The focus moved to another field: leave both fields as they are.
            if !typist.update(to: transcript, in: target()) { abandon() }
            return
        case .finished(let transcript):
            typist.update(to: transcript, in: target())
        case .failed(let reason):
            // After the user has stopped, a failure only means nothing more was heard.
            if phase == .listening { problem = reason }
        }
        microphone.close()
        phase = .idle
    }

    /// Moves on once the microphone has closed.
    private func finish() {
        if phase == .listening {
            phase = .finishing
            transcriber?.finish()
        } else {
            phase = .idle
        }
    }
}
