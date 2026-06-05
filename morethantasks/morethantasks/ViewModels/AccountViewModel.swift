//
//  AccountViewModel.swift
//  morethantasks
//

import Foundation

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var didSignOut = false
    @Published var errorMessage: String?

    private let auth: AuthService
    init(auth: AuthService? = nil) { 
        self.auth = auth ?? .shared
    }

    var userEmail: String { auth.currentUserEmail ?? "" }

    func logout() {
        auth.logout()
        didSignOut = true
    }

    func deleteAccount() async {
        errorMessage = nil
        do {
            try await auth.deleteAccount()
            didSignOut = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
