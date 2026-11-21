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

    /// The languages the user can dictate in: those of `Locale.preferredLanguages` that have a
    /// recogniser, most preferred first.
    public static var languages: [Locale] {
        languages(preferred: Locale.preferredLanguages, supported: SFSpeechRecognizer.supportedLocales())
    }

    /// One recogniser per language, so that a two-letter code is enough to tell them apart.
    static func languages(preferred: [String], supported: Set<Locale>) -> [Locale] {
        let supported = Set(supported.map { $0.identifier(.bcp47) })
        var listed = Set<Locale.LanguageCode>()
        return preferred.compactMap { identifier in
            let language = Locale.Language(identifier: identifier)
            guard let code = language.languageCode, !listed.contains(code) else { return nil }
            // iOS adds the device's region to every preferred language ("fr-US"). Where that
            // pair has no recogniser, the region the language is most spoken in stands in,
            // then any region that has one.
            let home = Locale.Language(
                identifier: Locale.Language(languageCode: code, script: language.script).maximalIdentifier
            )
            guard let match = [language.region, home.region]
                .compactMap({ region in region.map { "\(code.identifier)-\($0.identifier)" } })
                .first(where: supported.contains)
                ?? supported.filter({ $0.hasPrefix("\(code.identifier)-") }).min()
            else { return nil }
            listed.insert(code)
            return Locale(identifier: match)
        }
    }

    /// The language to dictate in: the `saved` one while it is still among `languages`,
    /// otherwise the most preferred.
    public static func language(saved: String?, among languages: [Locale]) -> Locale? {
        languages.first { $0.identifier == saved } ?? languages.first
    }

    /// Fails when neither `locale` nor US English is supported.
    public init?(locale: Locale) {
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
