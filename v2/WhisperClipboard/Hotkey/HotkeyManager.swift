import Core
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global dictation toggle. Default ⌃Space.
    static let toggleDictation = Self(
        "toggleDictation",
        default: .init(.space, modifiers: [.control])
    )
}

/// Binds the global dictation hotkey to the controller, honoring the current
/// ``AppSettings/hotkeyMode``. In toggle mode a key-down toggles; in
/// push-to-talk mode key-down starts and key-up stops. Debounce lives in the
/// controller.
@MainActor
final class HotkeyManager {
    private let controller: DictationController
    private let modeProvider: () -> AppSettings.HotkeyMode

    init(controller: DictationController, modeProvider: @escaping () -> AppSettings.HotkeyMode) {
        self.controller = controller
        self.modeProvider = modeProvider
        installHandlers()
    }

    private func installHandlers() {
        // Correctie na review (22 augustus 2026): de Carbon-callback loopt wél
        // op de main thread (`CarbonKeyboardShortcuts.swift` installeert op
        // `GetEventDispatcherTarget()`, de main runloop; de tweede route via
        // een `NSEvent`-monitor is ook main thread). De package bewaart deze
        // closures in Swift 5-modus als kale `() -> Void`, dus de compiler kan
        // de isolatie niet uit de aanroeper afleiden. Expliciet `@Sendable`
        // typeren plus de hop naar `Task { @MainActor }` maakt de conversie
        // compile-time schoon en de isolatie expliciet in plaats van afgeleid;
        // het is een correctheidsverduidelijking, geen fix voor een race. Dit
        // verklaart de crashrapporten van 3 augustus 2026 (frame
        // `swift_task_isCurrentExecutorWithFlagsImpl`) dus NIET: een mislukte
        // isolatiecontrole geeft een trap, geen EXC_BAD_ACCESS. Die crash blijft
        // open tot iemand aantoont wie deze callback vanaf een andere thread
        // aanroept.
        //
        // Volgorde bij push-to-talk: omdat de Carbon-callback op de main thread
        // loopt, komen key-down en key-up hier altijd serieel binnen, en Tasks
        // die na elkaar vanuit dezelfde context op de main actor worden gepland
        // voeren ook in die volgorde uit (FIFO). Geen aparte serialisatie nodig.
        let onDown: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch self.modeProvider() {
                case .toggle:
                    self.controller.toggle()
                case .pushToTalk:
                    self.controller.pushToTalkDown()
                }
            }
        }

        let onUp: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.modeProvider() == .pushToTalk {
                    self.controller.pushToTalkUp()
                }
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleDictation, action: onDown)
        KeyboardShortcuts.onKeyUp(for: .toggleDictation, action: onUp)
    }

    /// Human-readable current shortcut (e.g. "⌃Space") for display in the UI.
    var shortcutDescription: String {
        KeyboardShortcuts.getShortcut(for: .toggleDictation)?.description ?? "⌃Space"
    }
}
