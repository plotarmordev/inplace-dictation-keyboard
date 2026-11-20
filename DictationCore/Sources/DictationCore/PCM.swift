import AVFoundation

public extension AVAudioPCMBuffer {
    /// Wraps 16-bit little-endian mono PCM, as produced by the capture page.
    convenience init?(int16Mono pcm: Data, sampleRate: Double) {
        let frames = AVAudioFrameCount(pcm.count / MemoryLayout<Int16>.size)
        guard frames > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)
        else { return nil }
        self.init(pcmFormat: format, frameCapacity: frames)
        frameLength = frames
        pcm.withUnsafeBytes { bytes in
            UnsafeMutableRawPointer(int16ChannelData![0]).copyMemory(from: bytes.baseAddress!, byteCount: Int(frames) * 2)
        }
    }
}
