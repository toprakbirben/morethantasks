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
    @State var emailText: String = ""
    @State var passText: String = ""
    @State var isValidEmail: Bool = false
    @State var isValidPassword: Bool = false
    @StateObject var userDB = userDatabase.shared

    var body: some View {
        NavigationStack {
            VStack {
                Text("Register Here")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.bottom, 60)
                TextField("Email", text: $emailText)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .email)
                    .padding()
                    .background(Color("secondary-blue").opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(!isValidEmail ? .red : focusedField == .email ? Color("primary-blue"): Color.white, lineWidth: 3)
                    )
                    .padding(.horizontal)
                    .onChange(of: emailText) { oldValue, newValue in
                        isValidEmail = Validator.isValidEmail(newValue)
                    }
                SecureField("Password", text: $passText)
                    .focused($focusedField, equals: .password)
                    .padding()
                    .background(Color("secondary-blue").opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(!isValidPassword ? .red :focusedField == .password ? Color("primary-blue"): Color.white, lineWidth: 3)
                    )
                    .padding(.horizontal)
                    .onChange(of: passText) { oldValue, newValue in
                        isValidPassword = Validator.isValidPassword(newValue)
                    }
                
                Button {
                    userDB.registerUser(email: emailText, passwordHash: passText) { success in
                        if success {
                            //viewStack = .landingPage
                            //presentNextView.toggle()
                        }
                    }
                }
                label: {
                    Text("Sign up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(isValidPassword && isValidPassword ? Color("primary-blue"): Color("primary-blue").opacity(0.6)))
                .padding(.horizontal)
                .padding(.vertical)
                .disabled(!(isValidPassword || isValidPassword))
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
