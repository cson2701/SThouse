//
//  KeyboardDismissal.swift
//  SThouse
//
//  Created by Codex on 27/6/2026.
//

import SwiftUI
import UIKit

private struct KeyboardDismissalBackground: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        view.onDidMoveToWindow = { [weak coordinator = context.coordinator] containerView in
            coordinator?.installRecognizerIfNeeded(on: containerView.window)
        }
        return view
    }

    func updateUIView(_ uiView: PassthroughView, context: Context) {
        context.coordinator.installRecognizerIfNeeded(on: uiView.window)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private weak var tapRecognizer: UITapGestureRecognizer?

        func installRecognizerIfNeeded(on window: UIWindow?) {
            guard let window else {
                return
            }

            guard installedWindow !== window else {
                return
            }

            if let tapRecognizer, let installedWindow {
                installedWindow.removeGestureRecognizer(tapRecognizer)
            }

            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tapRecognizer.cancelsTouchesInView = false
            tapRecognizer.delegate = self
            window.addGestureRecognizer(tapRecognizer)

            installedWindow = window
            self.tapRecognizer = tapRecognizer
        }

        @objc
        private func handleTap() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else {
                return true
            }

            return !touchedView.isDescendant(ofControlType: UIControl.self)
        }
    }
}

private final class PassthroughView: UIView {
    var onDidMoveToWindow: ((UIView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onDidMoveToWindow?(superview ?? self)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }
}

private extension UIView {
    func isDescendant<T: UIView>(ofControlType type: T.Type) -> Bool {
        sequence(first: self, next: \.superview).contains { $0 is T }
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissalBackground())
    }
}
