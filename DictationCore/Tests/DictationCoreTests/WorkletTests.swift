import Foundation
import JavaScriptCore
import Testing
@testable import DictationCore

/// Runs the real audio worklet script in JavaScriptCore with the worklet globals stubbed.
private struct Tap {
    let context = JSContext()!

    init(inputRate: Int, rate: Int, chunkFrames: Int) throws {
        let script = try String(contentsOf: #require(WebMicrophone.resource("pcm-worklet.js")), encoding: .utf8)
        context.exceptionHandler = { _, error in Issue.record("JavaScript error: \(error!)") }
        context.evaluateScript("""
            var sampleRate = \(inputRate), chunks = [], registered = {};
            class AudioWorkletProcessor { port = { postMessage: (chunk) => chunks.push(chunk) }; }
            var registerProcessor = (name, processor) => { registered[name] = processor; };
            \(script)
            var tap = new registered['pcm-tap']({ processorOptions: { rate: \(rate), chunkFrames: \(chunkFrames) } });
            // Feeds `seconds` of audio in render quanta of 128 frames, like an AudioContext does.
            function feed(seconds, signal) {
              const total = Math.round(seconds * sampleRate);
              for (let start = 0; start < total; start += 128) {
                const quantum = Float32Array.from({ length: Math.min(128, total - start) }, (_, i) => signal(start + i));
                tap.process([[quantum]]);
              }
            }
            """)
    }

    func feed(seconds: Double, signal: String) {
        context.evaluateScript("feed(\(seconds), \(signal))")
    }

    var samples: [Int] {
        context.evaluateScript("chunks.flatMap((chunk) => Array.from(new Int16Array(chunk.pcm)))").toArray() as! [Int]
    }

    var chunkLengths: [Int] {
        context.evaluateScript("chunks.map((chunk) => chunk.pcm.byteLength / 2)").toArray() as! [Int]
    }

    var peaks: [Double] {
        context.evaluateScript("chunks.map((chunk) => chunk.peak)").toArray() as! [Double]
    }
}

@Suite struct WorkletTests {
    @Test func downsamplesByAnIntegerRatio() throws {
        let tap = try Tap(inputRate: 48000, rate: 16000, chunkFrames: 1600)
        tap.feed(seconds: 1, signal: "() => 0.5")

        #expect(tap.chunkLengths == Array(repeating: 1600, count: 10))
        #expect(tap.samples.allSatisfy { $0 == 16384 })
        #expect(tap.peaks.allSatisfy { abs($0 - 0.5) < 1e-6 })
    }

    @Test func downsamplesByAFractionalRatio() throws {
        let tap = try Tap(inputRate: 44100, rate: 16000, chunkFrames: 100)
        tap.feed(seconds: 1, signal: "() => -0.25")

        #expect((159...160).contains(tap.chunkLengths.count))
        #expect(tap.samples.allSatisfy { abs($0 + 8192) <= 1 })
    }

    @Test func preservesPitch() throws {
        let tap = try Tap(inputRate: 48000, rate: 16000, chunkFrames: 1600)
        tap.feed(seconds: 1, signal: "(n) => 0.8 * Math.sin(2 * Math.PI * 440 * n / sampleRate)")

        let samples = tap.samples
        let risingCrossings = zip(samples, samples.dropFirst()).count { $0 < 0 && $1 >= 0 }
        #expect((439...441).contains(risingCrossings))
        #expect((0.75...0.8).contains(tap.peaks.max()!))
    }

    @Test func passesAudioThroughAtTheTargetRate() throws {
        let tap = try Tap(inputRate: 8000, rate: 8000, chunkFrames: 4)
        tap.feed(seconds: 0.001, signal: "(n) => [0, 0.5, -0.5, 1, -1, 0.25, 0, 0][n]")

        #expect(tap.samples == [0, 16384, -16383, 32767, -32767, 8192, 0, 0])
    }

    @Test func clipsOutOfRangeInput() throws {
        let tap = try Tap(inputRate: 16000, rate: 16000, chunkFrames: 2)
        tap.feed(seconds: 2.0 / 16000, signal: "(n) => [3, -3][n]")

        #expect(tap.samples == [32767, -32767])
        #expect(tap.peaks == [1])
    }

    @Test func holdsBackAnIncompleteChunk() throws {
        let tap = try Tap(inputRate: 16000, rate: 16000, chunkFrames: 1600)
        tap.feed(seconds: 0.05, signal: "() => 0.1")

        #expect(tap.chunkLengths.isEmpty)
    }
}
