//
//  FirebaseAuthSession.swift
//  SThouse
//
//  Created by Codex on 27/6/2026.
//

import Foundation
import Observation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

@MainActor
@Observable
final class FirebaseAuthSession {
    var currentUser: User?
    var isResolvingAuthState = true
    var isSubmitting = false
    var errorMessage: String?

    @ObservationIgnored private var listenerHandle: AuthStateDidChangeListenerHandle?

    init(auth: Auth = Auth.auth()) {
        listenerHandle = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isResolvingAuthState = false
            }
        }
    }

    deinit {
        if let listenerHandle {
            Auth.auth().removeStateDidChangeListener(listenerHandle)
        }
    }

    var isAuthenticated: Bool {
        currentUser != nil
    }

    var userEmail: String {
        currentUser?.email ?? ""
    }

    var userDisplayName: String {
        currentUser?.displayName ?? ""
    }

    func signIn(email: String, password: String) async {
        await submit {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        }
    }

    func register(email: String, password: String) async {
        await submit {
            _ = try await Auth.auth().createUser(withEmail: email, password: password)
        }
    }

    func signInWithGoogle() async {
        await submit {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw GoogleSignInError.missingClientID
            }

            guard let presentingViewController = Self.presentingViewController() else {
                throw GoogleSignInError.missingPresentingViewController
            }

            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                throw GoogleSignInError.missingIDToken
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            _ = try await Auth.auth().signIn(with: credential)
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit(_ action: () async throws -> Void) async {
        errorMessage = nil
        isSubmitting = true

        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    private static func presentingViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .topMostViewController
    }
}

private enum GoogleSignInError: LocalizedError {
    case missingClientID
    case missingPresentingViewController
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return String(localized: "auth.error.google.missingClientID")
        case .missingPresentingViewController:
            return String(localized: "auth.error.google.missingPresenter")
        case .missingIDToken:
            return String(localized: "auth.error.google.missingIDToken")
        }
    }
}

private extension UIViewController {
    var topMostViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostViewController
        }

        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topMostViewController ?? navigationController
        }

        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.topMostViewController ?? tabBarController
        }

        return self
    }
}
