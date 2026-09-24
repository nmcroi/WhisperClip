import AppKit
import ObjectiveC

final class NonKeyPanel: NSPanel {
    // AppKit calls these Objective-C getters while selecting a key window.
    // They read no UI state. Avoid an unnecessary Swift executor check here
    // (2.0.2 crash in @objc canBecomeKey -> SerialExecutor._isSameExecutor).
    nonisolated override var canBecomeKey: Bool { false }
    nonisolated override var canBecomeMain: Bool { false }
}

final class NonKeyCaptionPanel: NSPanel {
    // AppKit calls these Objective-C getters while selecting a key window.
    // They read no UI state. Avoid an unnecessary Swift executor check here
    // (2.0.2 crash in @objc canBecomeKey -> SerialExecutor._isSameExecutor).
    nonisolated override var canBecomeKey: Bool { false }
    nonisolated override var canBecomeMain: Bool { false }
}


@main struct Stress {
 @MainActor static func main() {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
  var callbacks = 0
  for _ in 0..<250 {
   autoreleasepool {
    let panels: [NSPanel] = [NonKeyPanel(contentRect: NSRect(x: 100, y: 200, width: 200, height: 60), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false), NonKeyCaptionPanel(contentRect: NSRect(x: 100, y: 200, width: 200, height: 60), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)]
    for panel in panels {
     panel.isReleasedWhenClosed = false
     panel.alphaValue = 0
     panel.orderFrontRegardless()
     for selector in [#selector(getter: NSWindow.canBecomeKey), #selector(getter: NSWindow.canBecomeMain)] {
      let f = unsafeBitCast(panel.method(for: selector), to: Getter.self)
      for _ in 0..<100 { precondition(!f(panel, selector)); callbacks += 1 }
     }
     panel.makeKey()
     precondition(!panel.isKeyWindow && !panel.isMainWindow)
     panel.orderOut(nil)
     panel.close()
    }
   }
   RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
  }
  print("PASS: 500 panel lifecycles; \(callbacks) Objective-C getter calls; no focus acquired")
 }
}
