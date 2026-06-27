//
//  AuthGateView.swift
//  SThouse
//
//  Created by Codex on 27/6/2026.
//

import SwiftUI

struct AuthGateView: View {
    @State private var authSession = FirebaseAuthSession()

    var body: some View {
        Group {
            if authSession.isResolvingAuthState {
                ProgressView("Checking account…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authSession.isAuthenticated {
                ContentView(authSession: authSession)
            } else {
                EmailPasswordAuthView(authSession: authSession)
            }
        }
    }
}

private struct EmailPasswordAuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case register

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn:
                return "Sign in"
            case .register:
                return "Create account"
            }
        }

        var actionTitle: String {
            switch self {
            case .signIn:
                return "Sign in"
            case .register:
                return "Create account"
            }
        }
    }

    let authSession: FirebaseAuthSession

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Account") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                }

                Section {
                    Button(mode.actionTitle) {
                        Task {
                            switch mode {
                            case .signIn:
                                await authSession.signIn(email: trimmedEmail, password: password)
                            case .register:
                                await authSession.register(email: trimmedEmail, password: password)
                            }
                        }
                    }
                    .disabled(!canSubmit)
                }

                Section {
                    Button {
                        Task {
                            await authSession.signInWithGoogle()
                        }
                    } label: {
                        HStack {
                            Spacer(minLength: 0)

                            HStack(spacing: 10) {
                                Image("GoogleLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)

                                Text("Continue with Google")
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .disabled(authSession.isSubmitting)
                }

                if let errorMessage = authSession.errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("SThouse")
            .overlay {
                if authSession.isSubmitting {
                    ProgressView()
                }
            }
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedEmail.isEmpty && password.count >= 6 && !authSession.isSubmitting
    }
}
