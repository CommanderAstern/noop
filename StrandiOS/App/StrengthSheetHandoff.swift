#if os(iOS)
import SwiftUI
import UIKit

/// SwiftUI sheets can belong to a tab's children (for example Today's Settings),
/// so enumerating only the shell's bindings misses real presentations. Inspect this
/// scene's actual presenter, and deliver only after any existing presentation ends.
struct StrengthSheetHandoff: UIViewControllerRepresentable {
    @ObservedObject var tracker: StrengthWorkoutController
    var enabled: Bool
    var deliver: () -> Void

    func makeUIViewController(context: Context) -> Host { Host() }
    func updateUIViewController(_ host: Host, context: Context) {
        host.request = { [weak host] in
            guard enabled, tracker.pendingPresentation != nil else { return }
            guard let host, let root = host.view.window?.rootViewController else { return }
            // An already-open strength sheet consumes a navigation event in place.
            if tracker.presented { deliver(); return }
            if let existing = root.presentedViewController {
                if existing.isBeingPresented || existing.isBeingDismissed,
                   let transition = existing.transitionCoordinator {
                    host.busy = true
                    transition.animate(alongsideTransition: nil) { _ in
                        host.busy = false; host.schedule()
                    }
                } else {
                    host.busy = true
                    root.dismiss(animated: true) {
                        host.busy = false
                        // Re-read the latest readiness/request after dismissal.
                        host.schedule()
                    }
                }
            } else { deliver() }
        }
        host.schedule()
    }

    final class Host: UIViewController {
        var request: (() -> Void)?
        var busy = false
        private var scheduled = false
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); schedule() }
        func schedule() {
            guard !busy, !scheduled else { return }
            scheduled = true
            // Let SwiftUI commit sheet-binding changes before inspecting UIKit.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                guard !self.busy else { return }
                self.request?()
            }
        }
    }
}
#endif
