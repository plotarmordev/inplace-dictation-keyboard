import Foundation
import Testing
@testable import DictationCore

@Suite struct MicEventTests {
    @Test func decodesStates() {
        #expect(MicEvent(message: ["state": "ready"]) == .ready)
        #expect(MicEvent(message: ["state": "live", "rate": 16000]) == .live(sampleRate: 16000))
        #expect(MicEvent(message: ["state": "ended", "reason": "closed"]) == .ended(reason: "closed"))
        #expect(MicEvent(message: ["state": "ended"]) == .ended(reason: "unknown"))
    }

    @Test func decodesAudio() {
        let pcm = Data([0x01, 0x00, 0xff, 0x7f])
        let event = MicEvent(message: ["pcm": pcm.base64EncodedString(), "level": 0.25])
        #expect(event == .audio(pcm: pcm, level: 0.25))
    }

    @Test func rejectsMalformedMessages() {
        let malformed: [Any] = [
            "not a dictionary",
            [String: Any](),
            ["state": "paused"],
            ["state": "live"],
            ["state": "live", "rate": 0],
            ["pcm": "not base64!"],
            ["pcm": ""],
            ["pcm": Data([1, 2, 3]).base64EncodedString()],
        ]
        for message in malformed {
            #expect(MicEvent(message: message) == nil, "\(message)")
        }
    }
}
