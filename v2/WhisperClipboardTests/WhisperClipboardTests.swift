import AppKit
import XCTest
@testable import WhisperClipboard

final class WhisperClipboardTests: XCTestCase {
    @MainActor
    func testHostedTestsDoNotBootstrapUserServices() {
        XCTAssertTrue(AppDelegate.isUnitTestHost)
    }

    @MainActor
    func testClosingLastWindowKeepsAppAliveAndReopenTargetsMainScene() async {
        let delegate = AppDelegate()
        let opened = expectation(description: "Main scene opened from main actor")
        opened.expectedFulfillmentCount = 2
        var requests = 0
        delegate.openMainWindow = {
            XCTAssertTrue(Thread.isMainThread)
            requests += 1
            opened.fulfill()
        }
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
        XCTAssertFalse(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
        XCTAssertFalse(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: true))
        XCTAssertEqual(requests, 0, "Return to AppKit before activating/opening a scene")
        await fulfillment(of: [opened], timeout: 3)
        XCTAssertEqual(requests, 2)
    }

    @MainActor
    func testDockReopenThroughObjectiveCCallbackIsDeferredAndNotLost() async {
        let delegate = AppDelegate()
        let count = 200
        let opened = expectation(description: "All repeated Dock requests delivered")
        opened.expectedFulfillmentCount = count
        var requests = 0
        delegate.openMainWindow = {
            XCTAssertTrue(Thread.isMainThread)
            requests += 1
            opened.fulfill()
        }
        let selector = #selector(AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:))
        typealias Reopen = @convention(c) (AnyObject, Selector, NSApplication, Bool) -> Bool
        let callback = unsafeBitCast(delegate.method(for: selector), to: Reopen.self)
        for i in 0..<count {
            XCTAssertFalse(callback(delegate, selector, .shared, i.isMultiple(of: 2)))
        }
        XCTAssertEqual(requests, 0)
        await fulfillment(of: [opened], timeout: 5)
        XCTAssertEqual(requests, count)
    }

    @MainActor
    func testHUDRestoresEntirePanelAcrossMonitorLayouts() {
        let main = NSRect(x: 0, y: 40, width: 1440, height: 860)
        let left = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        let size = NSSize(width: 360, height: 220)
        let cases: [(NSPoint?, [NSRect])] = [
            (NSPoint(x: 200, y: -160), [main]), // old 20-pixel sliver
            (NSPoint(x: 1400, y: 850), [main]), // right/top edge
            (NSPoint(x: -3000, y: 0), [main]), // disconnected display
            (NSPoint(x: -1800, y: -150), [main, left]),
            (NSPoint(x: CGFloat.nan, y: CGFloat.infinity), [main]),
            (nil, [main])
        ]
        for (origin, screens) in cases {
            let fitted = RecordingHUDController.fittedOrigin(origin, size: size, screens: screens, fallback: main)
            XCTAssertTrue(screens.contains { $0.contains(NSRect(origin: fitted, size: size)) })
        }
        let good = NSPoint(x: -1700, y: 200)
        XCTAssertEqual(RecordingHUDController.fittedOrigin(good, size: size, screens: [main, left], fallback: main), good)
        // Content expansion must not push the top controls out of view.
        let grown = NSSize(width: 360, height: 400)
        let fitted = RecordingHUDController.fittedOrigin(NSPoint(x: 500, y: 700), size: grown, screens: [main], fallback: main)
        XCTAssertTrue(main.contains(NSRect(origin: fitted, size: grown)))
    }

    @MainActor
    func testPassivePanelsRemainNonActivatingThroughObjCCallbacks() {
        let panels: [NSPanel] = [
            NonKeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false),
            NonKeyCaptionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        ]
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        for panel in panels {
            for selector in [#selector(getter: NSWindow.canBecomeKey), #selector(getter: NSWindow.canBecomeMain)] {
                let implementation = unsafeBitCast(panel.method(for: selector), to: Getter.self)
                // Exercise the same Objective-C entry point used by AppKit,
                // not an optimised direct Swift property read.
                for _ in 0..<10_000 { XCTAssertFalse(implementation(panel, selector)) }
            }
        }
    }

    @MainActor
    func testConstantFocusAnswersDoNotRequireAnExecutor() async {
        let hud = NonKeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let captions = NonKeyCaptionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Only constant getters are queried off-actor; no AppKit state is read
        // or changed. This also prevents accidentally reintroducing isolation.
        let refused = await Task.detached {
            !hud.canBecomeKey && !hud.canBecomeMain &&
            !captions.canBecomeKey && !captions.canBecomeMain
        }.value
        XCTAssertTrue(refused)
    }

    /// Smoke test: the app state exposes Dutch status text and sensible defaults.
    func testAppStateStatusText() {
        XCTAssertEqual(AppState.ready.statusText, "Klaar voor opname")
        XCTAssertEqual(AppState.recording.statusText, "Opname loopt")
        XCTAssertEqual(AppState.transcribing.statusText, "Transcriptie maken…")
        XCTAssertTrue(AppState.recording.isRecording)
        XCTAssertFalse(AppState.ready.isRecording)
        XCTAssertEqual(AppState.error("boom").statusText, "Fout: boom")
    }
}
