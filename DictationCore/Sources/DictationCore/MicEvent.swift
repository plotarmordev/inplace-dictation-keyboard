import Foundation

/// What the capture page reports back to native code.
public enum MicEvent: Equatable, Sendable {
    /// The page has loaded and can be asked to open the microphone.
    case ready
    /// The microphone is open; audio chunks follow at `sampleRate`.
    case live(sampleRate: Double)
    /// A chunk of 16-bit little-endian mono PCM and its peak amplitude (0...1).
    case audio(pcm: Data, level: Float)
    /// The microphone was released, by request or because of `reason`.
    case ended(reason: String)

    /// Decodes a script message body; returns `nil` for anything malformed.
    public init?(message body: Any) {
        guard let body = body as? [String: Any] else { return nil }
        if let encoded = body["pcm"] as? String {
            guard let pcm = Data(base64Encoded: encoded), !pcm.isEmpty, pcm.count.isMultiple(of: 2) else { return nil }
            self = .audio(pcm: pcm, level: (body["level"] as? NSNumber)?.floatValue ?? 0)
            return
        }
        switch body["state"] as? String {
        case "ready":
            self = .ready
        case "live":
            guard let rate = (body["rate"] as? NSNumber)?.doubleValue, rate > 0 else { return nil }
            self = .live(sampleRate: rate)
        case "ended":
            self = .ended(reason: body["reason"] as? String ?? "unknown")
        default:
            return nil
        }
    }
}
