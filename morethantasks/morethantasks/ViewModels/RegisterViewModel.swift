//
//  RegisterViewModel.swift
//  morethantasks
//

import Foundation

@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var didAuthenticate = false

    private let auth: AuthService
    init(auth: AuthService? = nil) { self.auth = auth ?? .shared }

    var isValidEmail: Bool { Validator.isValidEmail(email) }
    var isValidPassword: Bool { Validator.isValidPassword(password) }
    var canSubmit: Bool { isValidEmail && isValidPassword }

    /// Only flag the email as invalid once something has been typed, so an
    /// untouched (empty) field isn't shown in red on first appearance.
    var emailFieldInvalid: Bool { !email.isEmpty && !isValidEmail }

    func register() async {
        errorMessage = nil
        guard canSubmit else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.register(email: email, password: password)
            // Auto-login with the same credentials so the new user lands
            // straight in the app (establishes the session + seeds the store).
            try await auth.login(email: email, password: password)
            didAuthenticate = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
