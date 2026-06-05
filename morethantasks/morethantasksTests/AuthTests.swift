//  AuthTests.swift
//  Covers the logic the MVVM refactor gave a home: AuthService's HTTP-status →
//  typed-error mapping, and ViewModel validation gating (invalid input must
//  never reach the network). Serialized because they share MockURLProtocol's
//  static state.

import Testing
import Foundation
@testable import morethantasks

@Suite(.serialized)
@MainActor
struct AuthTests {

    private func service(status: Int, json: [String: Any] = [:]) -> AuthService {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        MockURLProtocol.reset { _ in (status, data) }
        return AuthService(session: .mock())
    }

    /// A session that would record any attempted request — used to prove a call
    /// was *not* made.
    private func noNetworkService() -> AuthService {
        MockURLProtocol.reset { _ in (200, Data()) }
        return AuthService(session: .mock())
    }

    // MARK: - Status → typed error mapping
    //
    // Why it matters: callers (and users) react differently to a duplicate
    // email vs. bad credentials vs. a server outage. A regression that
    // collapses these to a generic failure would silently degrade UX.

    @Test func registerDuplicateMapsToDuplicateEmail() async {
        let auth = service(status: 409)
        await #expect(throws: AuthError.duplicateEmail) {
            try await auth.register(email: "a@b.com", password: "Password1")
        }
    }

    @Test func registerSuccessDoesNotThrow() async throws {
        let auth = service(status: 201)
        try await auth.register(email: "a@b.com", password: "Password1")
    }

    @Test func registerServerErrorMapsToServer() async {
        let auth = service(status: 500)
        await #expect(throws: AuthError.server(500)) {
            try await auth.register(email: "a@b.com", password: "Password1")
        }
    }

    @Test func loginUnauthorizedMapsToInvalidCredentials() async {
        let auth = service(status: 401)
        await #expect(throws: AuthError.invalidCredentials) {
            try await auth.login(email: "a@b.com", password: "wrong")
        }
    }

    @Test func loginMalformedBodyMapsToDecoding() async {
        let auth = service(status: 200, json: ["unexpected": true])
        await #expect(throws: AuthError.decoding) {
            try await auth.login(email: "a@b.com", password: "x")
        }
    }

    // MARK: - ViewModel validation gating
    //
    // Why it matters: firing a network call for empty/invalid input wastes a
    // round trip and surfaces a confusing server error instead of clear local
    // feedback. These tests fail if the guard is removed.

    @Test func loginWithInvalidEmailNeverHitsNetwork() async {
        let vm = LoginViewModel(auth: noNetworkService())
        vm.email = "not-an-email"
        vm.password = "Password1"
        await vm.login()
        #expect(MockURLProtocol.didReceiveRequest == false)
        #expect(vm.errorMessage != nil)
        #expect(vm.didAuthenticate == false)
    }

    @Test func loginWithEmptyPasswordNeverHitsNetwork() async {
        let vm = LoginViewModel(auth: noNetworkService())
        vm.email = "a@b.com"
        vm.password = ""
        await vm.login()
        #expect(MockURLProtocol.didReceiveRequest == false)
        #expect(vm.errorMessage != nil)
    }

    @Test func resetPasswordMismatchNeverHitsNetwork() async {
        let vm = ForgotPasswordViewModel(auth: noNetworkService())
        vm.email = "a@b.com"
        vm.password = "Password1"
        vm.confirmPassword = "Password2"
        await vm.resetPassword()
        #expect(MockURLProtocol.didReceiveRequest == false)
        #expect(vm.message != nil)
    }
}
