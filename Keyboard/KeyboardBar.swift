import SwiftUI

/// The whole keyboard: one row. At rest it offers the dictation button and the keys worth
/// keeping next to it; during a dictation it becomes cancel, a live waveform, and done.
struct KeyboardBar: View {
    /// Height of the row; the keyboard is exactly this tall: 40 pt keys with 6 pt above and below.
    static let height: CGFloat = 52

    let dictation: Dictation
    let showsGlobe: Bool
    let onGlobe: () -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            switch dictation.phase {
            case .preparing, .idle: resting
            case .starting, .listening, .finishing: dictating
            }
        }
        .buttonStyle(.plain)
        // Every control is a capsule, so with these margins the end ones sit concentric in the
        // rounded corners of the system's keyboard backdrop instead of being clipped by them.
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: Self.height)
        .animation(.snappy(duration: 0.2), value: dictation.phase)
    }

    @ViewBuilder private var resting: some View {
        if showsGlobe {
            Key(symbol: "globe", label: "Next keyboard", action: onGlobe)
        }
        Button(action: dictation.toggle) {
            Label(
                dictation.problem ?? (dictation.phase == .idle ? "Tap to dictate" : "Preparing…"),
                systemImage: dictation.problem == nil ? "mic.fill" : "exclamationmark.triangle.fill"
            )
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(dictation.problem == nil ? Color.accentColor : .orange, in: .capsule)
            .opacity(dictation.phase == .idle ? 1 : 0.5)
        }
        .disabled(dictation.phase != .idle)
        Key(symbol: "delete.left", label: "Delete", action: onDelete)
            .buttonRepeatBehavior(.enabled)
        Key(symbol: "return", label: "Return", action: onReturn)
    }

    @ViewBuilder private var dictating: some View {
        let finishing = dictation.phase == .finishing
        Key(symbol: "xmark", label: "Cancel dictation", action: dictation.cancel)
        Waveform(levels: dictation.levels)
            .opacity(finishing ? 0.4 : 1)
            .accessibilityLabel(finishing ? "Finishing" : "Listening")
        Button(action: dictation.stop) {
            ZStack {
                if finishing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark").font(.body.weight(.bold))
                }
            }
            .frame(width: Key.width)
            .frame(maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: .capsule)
        }
        .disabled(finishing)
        .accessibilityLabel("Finish dictation")
    }
}

/// Recent input levels as bars that enter on the right and scroll left over a dotted
/// baseline, newest last.
private struct Waveform: View {
    let levels: [Float]

    private let barWidth: CGFloat = 3
    private let pitch: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let slots = Int(size.width / pitch)
            let recent = levels.suffix(slots)
            for slot in 0..<slots {
                let index = recent.endIndex - slots + slot
                let level = index >= recent.startIndex ? CGFloat(recent[index]) : 0
                // Speech peaks sit well below full scale; the square root lifts them into view.
                let height = max(barWidth, level.squareRoot() * size.height * 0.9)
                let bar = CGRect(
                    x: size.width - CGFloat(slots - slot) * pitch + (pitch - barWidth) / 2,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: bar, cornerRadius: barWidth / 2),
                    with: .style(height > barWidth ? .primary : .tertiary)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

private struct Key: View {
    static let width: CGFloat = 46

    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: Self.width)
                .frame(maxHeight: .infinity)
                .background(.fill.tertiary, in: .capsule)
        }
        .accessibilityLabel(label)
    }
}
