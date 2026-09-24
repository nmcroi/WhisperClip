import AppKit

// The lifecycle and showMainWindow methods below are extracted unchanged
// from AppDelegate.swift. Other services are intentionally absent.
@MainActor
final class ReopenStressDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?
    var window: NSWindow!
    var count = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 120), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        openMainWindow = { [weak self] in
            guard let self else { return }
            precondition(Thread.isMainThread)
            self.window.makeKeyAndOrderFront(nil)
            precondition(self.window.isVisible)
            self.window.close()
            self.count += 1
            try! String(self.count).write(toFile: "/tmp/whisper204-reopen-count", atomically: true, encoding: .utf8)
        }
        try! "ready".write(toFile: "/tmp/whisper204-reopen-ready", atomically: true, encoding: .utf8)
    }
    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // macOS 27 crash reports show an invalid executor reference at this
        // Objective-C entry point. Return to AppKit before touching UI state;
        // an explicitly main-actor task establishes the UI execution context.
        // Do not use assumeIsolated here: that re-enters the crashing check.
        Task { @MainActor [weak self] in
            self?.showMainWindow()
        }
        return false
    }

    private func showMainWindow() {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        // Target the main scene, never an arbitrary settings window.
        openMainWindow?()
    }

}
@main
struct ReopenStressMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ReopenStressDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
