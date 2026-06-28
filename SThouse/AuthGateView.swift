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
                ProgressView("auth.loading.checkingAccount")
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
                return String(localized: "auth.mode.signIn")
            case .register:
                return String(localized: "auth.mode.createAccount")
            }
        }

        var actionTitle: String {
            switch self {
            case .signIn:
                return String(localized: "auth.action.signIn")
            case .register:
                return String(localized: "auth.action.createAccount")
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
                    Picker("auth.field.mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("auth.section.account") {
                    TextField("auth.field.email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()

                    SecureField("auth.field.password", text: $password)
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

                                Text("auth.action.continueWithGoogle")
                            }

                            Spacer(minLength: 0)
                        }
                    }
                    .disabled(authSession.isSubmitting)
                }

                if let errorMessage = authSession.errorMessage {
                    Section("auth.section.error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("app.name")
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
