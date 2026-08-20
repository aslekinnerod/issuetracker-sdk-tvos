import SwiftUI
import UIKit

// Owns the lifetime of the onboarding panel. The hosting controller
// must be retained for as long as it's on screen; once the user
// selects "Got it" we dismiss + drop the reference.
//
// Two entry points:
// - `presentIfNeeded(...)` is the configure-time path: checks the
//   "has been shown" flag, drops out silently if the user has seen
//   it before or if the remote trigger is disabled.
// - `presentForced(...)` is the public `Issuetracker.showOnboarding()`
//   path: bypasses the flag but still respects the trigger-disabled
//   no-op (there's literally nothing to teach — programmatic-only
//   integrations surface their own entry point).
enum OnboardingPresenter {
    @MainActor
    private static var presented = false

    @MainActor
    static func presentIfNeeded(longPressEnabled: Bool) {
        guard !OnboardingStore.hasBeenShown else { return }
        present(longPressEnabled: longPressEnabled, markShown: true)
    }

    @MainActor
    static func presentForced(longPressEnabled: Bool) {
        present(longPressEnabled: longPressEnabled, markShown: false)
    }

    @MainActor
    private static func present(longPressEnabled: Bool, markShown: Bool) {
        // With the trigger off there is nothing the panel can teach.
        // We still mark "shown" in the configure-time path so flipping
        // the trigger on later doesn't surprise the user with an
        // out-of-context panel.
        guard longPressEnabled else {
            if markShown { OnboardingStore.markShown() }
            return
        }
        guard !presented else { return }
        presented = true

        let view = OnboardingView(
            onDismiss: {
                topViewController()?.dismiss(animated: true) {
                    presented = false
                }
            }
        )
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .blurOverFullScreen
        host.view.backgroundColor = .clear

        // Defer one runloop tick so the host app's own root view
        // controller has a chance to mount before we present on top
        // of it. Without this, presentation from `App.init` reliably
        // no-ops on a window that doesn't have a root yet.
        DispatchQueue.main.async {
            guard let presenter = topViewController() else {
                presented = false
                return
            }
            presenter.present(host, animated: true) {
                if markShown { OnboardingStore.markShown() }
            }
        }
    }

    // Same top-controller walker the reporting session uses. Lives in
    // its own scope here (rather than importing ReportingSession's
    // private helper) because the two flows can outlive each other —
    // the onboarding panel doesn't depend on ReportingSession state.
    @MainActor
    private static func topViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let root: UIViewController? = base ?? UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .keyWindow?
            .rootViewController
        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }
}
