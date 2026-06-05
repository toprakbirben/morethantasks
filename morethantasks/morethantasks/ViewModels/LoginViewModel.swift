//
//  LoginViewModel.swift
//  morethantasks
//

import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var didAuthenticate = false

    private let auth: AuthService
    init(auth: AuthService? = nil) { self.auth = auth ?? .shared }

    func login() async {
        errorMessage = nil
        // Gate on a well-formed email + non-empty password so we never fire a
        // network call for empty input. We deliberately don't enforce the
        // password *policy* here — that would lock out valid existing accounts.
        guard Validator.isValidEmail(email), !password.isEmpty else {
            errorMessage = "Enter a valid email and password."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.login(email: email, password: password)
            didAuthenticate = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
