//
//  RegisterScreen.swift
//  morethantasks
//
//  Created by Toprak Birben on 08/11/2025.
//

import SwiftUI

struct RegisterView : View {
    @FocusState private var focusedField: FocusedField?
    @State private var presentNextView = false
    @State private var viewStack: ViewStack = .registration
    @StateObject private var vm = RegisterViewModel()

    var body: some View {
        NavigationStack {
            VStack {
                Text("Register Here")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.bottom, 60)
                TextField("Email", text: $vm.email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .email)
                    .padding()
                    .background(Color("secondary-blue").opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(!vm.isValidEmail ? .red : focusedField == .email ? Color("primary-blue"): Color.white, lineWidth: 3)
                    )
                    .padding(.horizontal)

                UIComponents.passwordFields(passwordField: $vm.password)

                Button {
                    Task { await vm.register() }
                }
                label: {
                    Text("Sign up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(vm.canSubmit ? Color("primary-blue"): Color("primary-blue").opacity(0.6)))
                .padding(.horizontal)
                .padding(.vertical)
                .disabled(!vm.canSubmit || vm.isLoading)

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                } else {
                    Text(vm.message ?? "")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .navigationDestination(isPresented: $presentNextView) {
                switch viewStack {
                    case .forgottenPassword: forgotPassword()
                    default: EmptyView()
                }
            }
        }
    }
}

#Preview {
    RegisterView()
}
