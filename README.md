# InPlace

An iOS keyboard that dictates in place: tap the microphone, talk, and the words appear in the
text field you are in. No switching to another app and back.

I built it because every dictation option I tried stole focus — open the app, dictate, copy,
switch back, paste. InPlace is a keyboard, so the text lands where the cursor already is.

The whole keyboard is a single row of 40-point keys, so it leaves almost the whole screen to the
app you are typing in. On iPhones with Face ID, iOS draws its own globe and dictation icons under
every keyboard, so the row has 14 points above it and nothing below; on iPhones with a Home button
it has 6 points above and below.

## Try it on your iPhone

1. Open `InPlace.xcodeproj` in Xcode 16 or later.
2. In `Config.xcconfig`, set `DEVELOPMENT_TEAM` to your Apple developer team ID and
   `BUNDLE_ID_PREFIX` to a prefix you own.
3. Run the `InPlace` scheme on your iPhone.
4. In the app, allow the microphone and speech recognition.
5. In Settings > General > Keyboard > Keyboards > Add New Keyboard, add InPlace, then open it
   and switch on Allow Full Access.
6. In any text field, hold the globe key, pick InPlace, and tap the microphone.

While it listens, the row shows a live waveform between a cancel button (removes what this
dictation typed) and a done button (keeps it).

If two or more of your preferred languages (Settings > General > Language & Region) have a
speech recogniser, a language key such as `EN` or `FR` appears beside the dictation button. Tap
it to move to the next language; the following dictation is recognised in that one, and the
keyboard remembers the choice. With a single such language the key is not shown.

## How it works

iOS doesn't let a keyboard extension record through the usual audio APIs, but a web view inside
the keyboard can. The pieces, in the order audio flows through them:

| Piece | Where | What it does |
| --- | --- | --- |
| Capture page | `DictationCore/Sources/DictationCore/Web` | Opens the microphone with `getUserMedia`; an audio worklet downsamples to 16 kHz mono 16-bit PCM and sends 100 ms chunks to native code. |
| `WebMicrophone` | `DictationCore` | Hosts the page in a `WKWebView` (sized 1×1 by the keyboard), serves it from a private URL scheme, grants it the microphone only, and decodes its messages into `MicEvent`s. |
| `SpeechTranscriber` | `DictationCore` | Feeds the PCM to Apple's speech recogniser, on device when the language supports it. |
| `Typist` | `DictationCore` | Retypes only the changed tail of each revised transcript in the text field — and walks away if focus moved to another field mid-dictation. |
| `Dictation`, `KeyboardBar` | `Keyboard` | The state machine and the one-row SwiftUI interface. |
| `SetupView` | `App` | The host app: permissions and setup steps. |

Native code acknowledges every audio chunk. If acknowledgements stop — because the keyboard was
dismissed or suspended — the page releases the microphone by itself, so the mic can't be left
open in a dead view. The audio worklet routes through a zero-gain node to the output so WebKit
keeps pulling samples without ever playing the microphone back.

Full Access is required: without it iOS gives a keyboard no microphone. Speech is recognised on
device when your language supports it (otherwise Apple's speech service handles it); nothing else
leaves the phone.

## Develop

```sh
swift test --package-path DictationCore   # unit tests, runs on macOS 14+
brew install xcodegen && xcodegen         # regenerate InPlace.xcodeproj after editing project.yml
```

The tests run the real audio worklet in JavaScriptCore and load the real capture page in WebKit.
Requires iOS 17 or later.

Dictation also works in the iOS Simulator, which listens through the Mac's default audio input.
Simulator builds switch off WebKit's mock capture devices (otherwise the page hears a test tone)
and recognise speech over the network, because the Simulator has no on-device speech model. Both
are compiled out of device builds.

## License

MIT. See [LICENSE](LICENSE).
