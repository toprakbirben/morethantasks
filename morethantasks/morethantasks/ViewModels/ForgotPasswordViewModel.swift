//
//  ForgotPasswordViewModel.swift
//  morethantasks
//

import Foundation

@MainActor
final class ForgotPasswordViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published private(set) var isLoading = false
    @Published var message: String?

    private let auth: AuthService
    init(auth: AuthService? = nil) { self.auth = auth ?? .shared }

    private var inputsValid: Bool {
        password == confirmPassword
            && !password.isEmpty
            && !email.isEmpty
            && !confirmPassword.isEmpty
    }

    func resetPassword() async {
        message = nil
        guard inputsValid else {
            message = "Passwords must match and no field can be empty."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.resetPassword(email: email, password: password)
            message = "Password successfully changed!"
        } catch {
            message = error.localizedDescription
        }
    }
}
