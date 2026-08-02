import SwiftUI
import UIKit

/// Hiding the navigation bar also disarms UIKit's edge-swipe pop gesture. This
/// re-arms it for the one screen it is attached to — scoped, unlike the common
/// UINavigationController-category swizzle, so Home keeps stock behaviour and the
/// original delegate comes back when the screen goes away.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Enabler { Enabler() }
    func updateUIViewController(_ controller: Enabler, context: Context) {}

    final class Enabler: UIViewController, UIGestureRecognizerDelegate {
        private weak var gesture: UIGestureRecognizer?
        private weak var previousDelegate: UIGestureRecognizerDelegate?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        // The parent chain doesn't reach the navigation controller until the hosting
        // controller is pushed, so didMove alone can be too early; trying again on
        // every appearance is idempotent via the `gesture == nil` guard.
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { arm() } else { disarm() }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            arm()
        }

        private func arm() {
            guard gesture == nil,
                  let recognizer = navigationController?.interactivePopGestureRecognizer
            else { return }
            gesture = recognizer
            previousDelegate = recognizer.delegate
            recognizer.delegate = self
        }

        private func disarm() {
            guard let gesture, gesture.delegate === self else { return }
            gesture.delegate = previousDelegate
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Never on the root: popping nothing freezes the navigation controller.
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
