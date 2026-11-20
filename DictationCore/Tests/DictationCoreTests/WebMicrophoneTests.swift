import Testing
import WebKit
@testable import DictationCore

@Suite struct WebMicrophoneTests {
    /// The page must load from the bundle into a context where WebKit allows capture.
    @MainActor @Test(.timeLimit(.minutes(1)))
    func pageLoadsReadyToCapture() async throws {
        let microphone = WebMicrophone()
        let first = await nextEvent(from: microphone)
        #expect(first == .ready)

        let ready = try await microphone.webView.evaluateJavaScript(
            "isSecureContext && typeof AudioWorkletNode === 'function' && typeof GainNode === 'function' && typeof Mic.open === 'function'"
        ) as? Bool
        #expect(ready == true)

        // macOS WebKit does not expose navigator.mediaDevices to custom URL schemes; iOS does.
        #if os(iOS)
        let canCapture = try await microphone.webView.evaluateJavaScript(
            "typeof navigator.mediaDevices?.getUserMedia === 'function'"
        ) as? Bool
        #expect(canCapture == true)
        #endif
    }

    /// The audio graph must keep the worklet pulled while muting its output to the destination.
    @MainActor @Test(.timeLimit(.minutes(1)))
    func openRoutesTapThroughZeroGainNode() async throws {
        let microphone = WebMicrophone()
        #expect(await nextEvent(from: microphone) == .ready)

        let edges = try await microphone.webView.callAsyncJavaScript(
            """
            const edges = [];
            class Node {
              constructor(kind) { this.kind = kind; }
              connect(target) {
                edges.push({ from: this.kind, to: target.kind, gain: this.gain?.value ?? null });
                return target;
              }
            }
            window.AudioWorkletNode = class extends Node {
              constructor(_ctx, name) { super(`worklet:${name}`); this.port = {}; }
            };
            window.GainNode = class extends Node {
              constructor(_ctx, opts = {}) { super('gain'); this.gain = { value: opts.gain ?? 1 }; }
            };
            window.AudioContext = class {
              sampleRate = 48000;
              state = 'running';
              destination = new Node('destination');
              audioWorklet = { addModule: async () => {} };
              resume = async () => {};
              close = async () => {};
              createMediaStreamSource() { return new Node('source'); }
              createGain() { return new window.GainNode(this); }
            };
            Object.defineProperty(navigator, 'mediaDevices', {
              configurable: true,
              value: {
                getUserMedia: async () => ({
                  getAudioTracks: () => [{}],
                  getTracks: () => [{ stop() {} }],
                }),
              },
            });
            await Mic.open();
            Mic.close();
            return edges;
            """,
            contentWorld: .page
        ) as? [[String: Any]]

        let graph = try #require(edges)
        #expect(graph.count == 3)
        #expect(graph[0]["from"] as? String == "source")
        #expect(graph[0]["to"] as? String == "worklet:pcm-tap")
        #expect(graph[1]["from"] as? String == "worklet:pcm-tap")
        #expect(graph[1]["to"] as? String == "gain")
        #expect(graph[2]["from"] as? String == "gain")
        #expect(graph[2]["to"] as? String == "destination")
        #expect(graph[2]["gain"] as? Double == 0)
    }

    @MainActor
    private func nextEvent(from microphone: WebMicrophone) async -> MicEvent {
        await withCheckedContinuation { continuation in
            microphone.onEvent = { event in
                microphone.onEvent = nil
                continuation.resume(returning: event)
            }
        }
    }
}
