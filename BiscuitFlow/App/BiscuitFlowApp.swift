import AppKit
import ServiceManagement
import SwiftUI

@main
enum Main {
    static func main() {
        // `--bench` runs headless (works over SSH, without a GUI login session).
        if let i = CommandLine.arguments.firstIndex(of: "--bench") {
            Benchmark.run(arguments: Array(CommandLine.arguments.dropFirst(i + 1)), settings: .shared)
            dispatchMain()
        }
        BiscuitFlowApp.main()
    }
}

struct BiscuitFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("BiscuitFlow", id: "hub") {
            HubView()
                .environmentObject(appDelegate.controller)
                .environmentObject(appDelegate.store)
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.permissions)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1000, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appDelegate.controller)
                .environmentObject(appDelegate.store)
                .environmentObject(appDelegate.settings)
        } label: {
            MenuBarIcon()
                .environmentObject(appDelegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings.shared
    let store = Store()
    let permissions = Permissions()
    lazy var controller = DictationController(settings: settings, store: store, permissions: permissions)
    private var overlay: OverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosting unit tests: don't start the tap, overlay or model.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        overlay = OverlayController(controller: controller, settings: settings)
        controller.start()
        if !permissions.allGranted {
            permissions.startPolling()
        }
        // First launch: surface the system Accessibility prompt right away (once).
        if !permissions.accessibility, !UserDefaults.standard.bool(forKey: "promptedAccessibility") {
            UserDefaults.standard.set(true, forKey: "promptedAccessibility")
            permissions.requestAccessibility()
        }
        // Start the hotkey tap as soon as Accessibility is granted.
        permissions.$accessibility
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.controller.startHotkeysIfPossible() }
            .store(in: &cancellables)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { HubWindow.open() }
        return true
    }

    private var cancellables: Set<AnyCancellable> = []
}

import Combine

enum HubWindow {
    @MainActor static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "hub" || $0.title == "BiscuitFlow" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?("hub")
        }
    }

    /// Captured from SwiftUI so AppKit code can open the hub scene.
    @MainActor static var openWindowAction: ((String) -> Void)?
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[BiscuitFlow] Launch at login: \(error)")
        }
    }
}
