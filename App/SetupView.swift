import AVFoundation
import Speech
import SwiftUI

/// Walks through the one-time setup the keyboard depends on, and offers a field to try it in.
struct SetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var microphone = Access.microphone
    @State private var speech = Access.speech
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AccessRow(title: "Microphone", symbol: "mic", access: microphone) {
                        await AVAudioApplication.requestRecordPermission()
                    }
                    AccessRow(title: "Speech Recognition", symbol: "waveform", access: speech) {
                        await requestSpeechAuthorization()
                    }
                } header: {
                    Text("1. Allow access")
                } footer: {
                    Text("The keyboard uses the access you grant here. Speech is recognised on device when your language supports it.")
                }

                Section {
                    Button("Open Settings", systemImage: "gear", action: openSettings)
                } header: {
                    Text("2. Turn on the keyboard")
                } footer: {
                    Text("In Settings, tap Keyboards, switch on InPlace, then switch on Allow Full Access. Full Access is what lets a keyboard use the microphone.")
                }

                Section {
                    TextField("Tap here, then pick InPlace with the globe key", text: $draft, axis: .vertical)
                        .lineLimit(4...)
                } header: {
                    Text("3. Try it")
                }
            }
            .navigationTitle("InPlace")
        }
        .onChange(of: scenePhase) { refresh() }
        .task { refresh() }
    }

    private func refresh() {
        microphone = Access.microphone
        speech = Access.speech
    }

    private func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}

private enum Access {
    case undetermined, granted, denied

    static var microphone: Access {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .undetermined: .undetermined
        default: .denied
        }
    }

    static var speech: Access {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }
}

private struct AccessRow: View {
    let title: String
    let symbol: String
    let access: Access
    let request: () async -> Void

    var body: some View {
        LabeledContent {
            switch access {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Allowed")
            case .undetermined:
                Button("Allow") { Task { await request() } }
            case .denied:
                Text("Denied — change in Settings").foregroundStyle(.secondary)
            }
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

/// Outside any actor because the system calls back on a queue of its own.
private nonisolated func requestSpeechAuthorization() async {
    await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
    }
}
