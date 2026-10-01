import SwiftUI

enum FlowBarMetrics {
    /// Invisible canvas; the pill sits bottom-center, toasts float above it.
    static let panelSize = CGSize(width: 440, height: 120)
    /// Gap between the bottom of the work area (above the Dock) and the panel.
    static let bottomInset: CGFloat = 0
    static let pillBottomPadding: CGFloat = 12
    static let rowHeight: CGFloat = 40

    static let resting = CGSize(width: 16, height: 16)
    static let ready = CGSize(width: 136, height: 36)
    static let listening = CGSize(width: 172, height: 40)
    static let handsFree = CGSize(width: 256, height: 40)
    static let processing = CGSize(width: 150, height: 40)

    /// Screen-space rect that should receive mouse events (the pill plus some slop).
    static func hitRect(in panelFrame: NSRect, expanded: Bool) -> NSRect {
        let size = expanded ? handsFree : CGSize(width: 56, height: 32)
        return NSRect(
            x: panelFrame.midX - size.width / 2 - 6,
            y: panelFrame.minY + pillBottomPadding - 6,
            width: size.width + 12,
            height: max(size.height, rowHeight) + 12)
    }
}

/// The dictation pill: a frosted chip that grows from a resting crumb into
/// ready → listening → hands-free → transcribing.
struct FlowBarView: View {
    @ObservedObject var hover: FlowBarHoverState
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var settings: AppSettings

    private enum Mode: Equatable { case resting, ready, listening, handsFree, processing }

    private var mode: Mode {
        switch controller.phase {
        case .recording(let handsFree): return handsFree ? .handsFree : .listening
        case .transcribing: return .processing
        case .idle: return hover.isHovering ? .ready : .resting
        }
    }

    private var size: CGSize {
        switch mode {
        case .resting: return FlowBarMetrics.resting
        case .ready: return FlowBarMetrics.ready
        case .listening: return FlowBarMetrics.listening
        case .handsFree: return FlowBarMetrics.handsFree
        case .processing: return FlowBarMetrics.processing
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if let toast = controller.toast {
                Toast(text: toast)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
            pill
                .frame(height: FlowBarMetrics.rowHeight, alignment: .bottom)
                .padding(.bottom, FlowBarMetrics.pillBottomPadding)
        }
        .frame(width: FlowBarMetrics.panelSize.width, height: FlowBarMetrics.panelSize.height)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: mode)
        .animation(.easeOut(duration: 0.18), value: controller.toast)
    }

    private var pill: some View {
        let corner = min(13, size.height / 2)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return ZStack {
            shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            shape.fill(Theme.pillInk.opacity(mode == .resting ? 0.55 : 0.82))
            shape.strokeBorder(Theme.pillStroke, lineWidth: 1)
            content
                .padding(.horizontal, mode == .resting ? 0 : 10)
                .transition(.opacity)
                .id(mode)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(color: .black.opacity(mode == .resting ? 0.15 : 0.3), radius: mode == .resting ? 3 : 10, y: 3)
        .contentShape(shape)
        .onTapGesture {
            if mode == .ready { controller.toggleHandsFree() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .resting:
            Circle()
                .fill(controller.toast != nil ? Theme.error : Theme.honey)
                .frame(width: 6, height: 6)
        case .ready:
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Theme.honey)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.pillInk)
                }
                .frame(width: 22, height: 22)
                Text("Hold \(settings.hotkey.displayName)")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.crumb)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        case .listening:
            HStack(spacing: 10) {
                RecordDot()
                LevelHistory(levels: controller.levels)
                Elapsed(since: controller.recordingStartedAt)
            }
        case .handsFree:
            HStack(spacing: 9) {
                ChipButton(help: "Cancel") {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.crumb)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                } action: { controller.cancelFromUI() }
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.honey)
                LevelHistory(levels: controller.levels)
                Elapsed(since: controller.recordingStartedAt)
                ChipButton(help: "Finish and paste") {
                    Text("Done")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .fixedSize()
                        .foregroundStyle(Theme.pillInk)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Theme.honey))
                } action: { controller.toggleHandsFree() }
            }
        case .processing:
            HStack(spacing: 9) {
                BouncingDots()
                Text("Transcribing")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.crumb.opacity(0.85))
            }
        }
    }
}

/// Coral "on air" dot with a soft breathing halo.
private struct RecordDot: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * 2 * .pi / 1.4) + 1) / 2
            ZStack {
                Circle().fill(Theme.record.opacity(0.25 + 0.2 * pulse)).frame(width: 14 + 4 * pulse, height: 14 + 4 * pulse)
                Circle().fill(Theme.record).frame(width: 8, height: 8)
            }
            .frame(width: 18, height: 18)
        }
    }
}

/// Scrolling level history: newest sample on the right, older ones fade out to the left.
private struct LevelHistory: View {
    let levels: [Float]
    private let count = 16

    var body: some View {
        let recent = Array(levels.suffix(count))
        HStack(alignment: .center, spacing: 2) {
            ForEach(recent.indices, id: \.self) { i in
                let level = CGFloat(recent[i])
                Capsule()
                    .fill(Theme.crumb.opacity(0.35 + 0.65 * Double(i + 1) / Double(recent.count)))
                    .frame(width: 3, height: 3 + 17 * level)
            }
        }
        .frame(height: 22)
        .animation(.linear(duration: 0.05), value: levels)
    }
}

private struct Elapsed: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 0.5)) { timeline in
            let s = max(0, Int(timeline.date.timeIntervalSince(since)))
            Text(String(format: "%d:%02d", s / 60, s % 60))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.crumb.opacity(0.75))
        }
    }
}

private struct BouncingDots: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = t * 2 * .pi / 0.9 - Double(i) * 0.7
                    Circle()
                        .fill(Theme.honey)
                        .frame(width: 6, height: 6)
                        .offset(y: -3 * max(0, sin(phase)))
                }
            }
            .frame(height: 16)
        }
    }
}

private struct ChipButton<Label: View>: View {
    let help: String
    @ViewBuilder var label: Label
    let action: () -> Void

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(.plain)
            .help(help)
    }
}

private struct Toast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.crumb)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.pillInk.opacity(0.92))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.pillStroke)))
            .frame(maxWidth: 400)
    }
}
