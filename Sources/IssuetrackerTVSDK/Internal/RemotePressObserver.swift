import UIKit

// Siri Remote trigger: press and hold Play/Pause for 2 seconds. The
// tvOS sibling of the two-finger long-press on iOS/web — exposed
// under the same `longPressToReport` flag name so entitlement
// matrices and docs stay consistent across SDKs.
//
// Play/Pause is the only safe candidate on the remote:
//  - Menu/Back is system navigation; intercepting it is an App Store
//    rejection.
//  - Select carries every focus interaction in the app.
//  - A quick Play/Pause tap is common in playback UIs, but a 2-second
//    HOLD has no system meaning and no common in-app meaning.
// Hosts with heavy playback surfaces can disable the trigger via
// `longPressToReport: false` and wire `Issuetracker.report()` to a
// settings row instead.
//
// Attached to the key window at install time. cancelsTouchesInView is
// false and the delegate allows simultaneous recognition so we don't
// interfere with the host app's own press handling.
@MainActor
enum RemotePressObserver {
    private static let coordinator = Coordinator()
    private static var onTrigger: (() -> Void)?
    private static var attached = false

    static func install(onTrigger handler: @escaping () -> Void) {
        self.onTrigger = handler
        attach()
    }

    static var isInstalled: Bool { onTrigger != nil }

    private static func attach() {
        guard !attached else { return }
        guard let window = keyWindow() else {
            // No window yet (configure called before scene attaches).
            // Re-try on the next run loop tick.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                attach()
            }
            return
        }
        let recognizer = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.fired(_:))
        )
        recognizer.minimumPressDuration = 2.0
        recognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = coordinator
        window.addGestureRecognizer(recognizer)
        attached = true
    }

    fileprivate static func fire() {
        onTrigger?()
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return active?.windows.first(where: { $0.isKeyWindow }) ?? active?.windows.first
    }

    private final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func fired(_ gr: UIGestureRecognizer) {
            guard gr.state == .began else { return }
            Task { @MainActor in RemotePressObserver.fire() }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Let host-app press handling keep working alongside ours.
            return true
        }
    }
}
