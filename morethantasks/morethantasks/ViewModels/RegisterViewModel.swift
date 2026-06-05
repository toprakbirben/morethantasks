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
    @Published var message: String?
    @Published var errorMessage: String?

    private let auth: AuthService
    init(auth: AuthService? = nil) { self.auth = auth ?? .shared }

    var isValidEmail: Bool { Validator.isValidEmail(email) }
    var isValidPassword: Bool { Validator.isValidPassword(password) }
    var canSubmit: Bool { isValidEmail && isValidPassword }

    func register() async {
        errorMessage = nil
        message = nil
        guard canSubmit else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.register(email: email, password: password)
            message = "Successfully registered!"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
