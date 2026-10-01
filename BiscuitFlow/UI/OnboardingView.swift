import SwiftUI

/// First-run setup: permissions, model download, and a try-it-now step.
struct OnboardingView: View {
    @EnvironmentObject private var permissions: Permissions
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: Store
    @State private var practice = ""
    @FocusState private var practiceFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    BrandMark().frame(width: 34, height: 34)
                    Text("Speak, don't type.")
                        .font(Theme.display(40))
                    Text("BiscuitFlow turns your voice into clean text in any app — privately, on-device, with Qwen3-ASR.")
                        .font(.system(size: 14.5))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Step(number: 1, title: "Allow microphone access",
                         detail: "So BiscuitFlow can hear you while you hold the dictation key.",
                         done: permissions.microphone == .authorized) {
                        Button("Allow", action: permissions.requestMicrophone).buttonStyle(AccentButtonStyle())
                    }
                    Step(number: 2, title: "Allow Accessibility",
                         detail: "Lets BiscuitFlow notice the dictation key and paste text where your cursor is. Toggle BiscuitFlow on in System Settings, then come back.",
                         done: permissions.accessibility) {
                        Button("Open Settings", action: permissions.requestAccessibility).buttonStyle(AccentButtonStyle())
                    }
                    Step(number: 3, title: "Load the speech model",
                         detail: modelDetail,
                         done: controller.modelState == .ready) {
                        if case .loading(let p, _) = controller.modelState {
                            ProgressView(value: p).frame(width: 120)
                        } else {
                            Button("Retry", action: controller.loadModel).buttonStyle(AccentButtonStyle())
                        }
                    }
                }

                if permissions.allGranted {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Try it").font(.system(size: 17, weight: .semibold))
                        (Text("Click the box, hold ") + Text(settings.hotkey.displayName).bold()
                         + Text(", say something, and let go."))
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $practice)
                            .font(.system(size: 14))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(height: 110)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(practiceFocused ? Theme.highlight.opacity(0.6) : Theme.hairline))
                            .focused($practiceFocused)
                        HStack {
                            Spacer()
                            Button("Finish setup") { settings.hasCompletedOnboarding = true }
                                .buttonStyle(AccentButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 56)
            .padding(.bottom, 40)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { permissions.startPolling() }
    }

    private var modelDetail: String {
        switch controller.modelState {
        case .ready: return "\(Transcriber.displayName) is ready."
        case .loading(_, let message): return message
        case .failed(let message): return "Couldn't load the model: \(message)"
        case .notLoaded: return "\(Transcriber.displayName) runs entirely on this Mac."
        }
    }
}

private struct Step<Action: View>: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.15) : Theme.sidebarSelection)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if !done { action }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))
    }
}
