import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating, always-on-top panel that hosts the dictation pill.
/// It never steals focus from the app the user is dictating into.
final class OverlayPanel: NSPanel {
    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: FlowBarMetrics.panelSize.width, height: FlowBarMetrics.panelSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        host.frame = contentRect(forFrameRect: frame)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the overlay panel, keeps it positioned bottom-center on the active screen,
/// and lets mouse events through except over the pill itself.
@MainActor
final class OverlayController {
    private let panel: OverlayPanel
    private let controller: DictationController
    private let settings: AppSettings
    private var cancellables: Set<AnyCancellable> = []
    private var mouseTimer: Timer?
    private var currentScreen: NSScreen?

    init(controller: DictationController, settings: AppSettings) {
        self.controller = controller
        self.settings = settings
        let hover = FlowBarHoverState()
        panel = OverlayPanel(rootView: FlowBarView(hover: hover)
            .environmentObject(controller)
            .environmentObject(settings))
        self.hover = hover

        controller.$phase.combineLatest(controller.$toast)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateVisibility() }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.updateVisibility() } }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.reposition(force: true) } }

        // Follow the mouse to whichever display is in use, and track hover so the
        // panel only intercepts clicks while the cursor is over the pill.
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        reposition(force: true)
        updateVisibility()
    }

    private let hover: FlowBarHoverState

    private func updateVisibility() {
        let active = controller.phase != .idle || controller.toast != nil
        if active || settings.showFlowBarWhenIdle {
            reposition(force: false)
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func tick() {
        reposition(force: false)
        let mouse = NSEvent.mouseLocation
        let pill = FlowBarMetrics.hitRect(in: panel.frame, expanded: hover.isHovering || controller.phase != .idle)
        let inside = pill.contains(mouse)
        if hover.isHovering != inside { hover.isHovering = inside }
        panel.ignoresMouseEvents = !inside
    }

    private func reposition(force: Bool) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen, force || screen != currentScreen else { return }
        currentScreen = screen
        let size = FlowBarMetrics.panelSize
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: (visible.minY + FlowBarMetrics.bottomInset).rounded())
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

final class FlowBarHoverState: ObservableObject {
    @Published var isHovering = false
}
