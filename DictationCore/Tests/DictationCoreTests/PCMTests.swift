import AVFoundation
import Testing
@testable import DictationCore

@Suite struct PCMTests {
    @Test func wrapsSamplesUnchanged() throws {
        let samples: [Int16] = [0, 1, -1, .max, .min]
        let pcm = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let buffer = try #require(AVAudioPCMBuffer(int16Mono: pcm, sampleRate: 16000))

        #expect(buffer.format.sampleRate == 16000)
        #expect(buffer.format.channelCount == 1)
        #expect(buffer.frameLength == 5)
        #expect(Array(UnsafeBufferPointer(start: buffer.int16ChannelData![0], count: 5)) == samples)
    }

    @Test func rejectsEmptyAudio() {
        #expect(AVAudioPCMBuffer(int16Mono: Data(), sampleRate: 16000) == nil)
    }
}
