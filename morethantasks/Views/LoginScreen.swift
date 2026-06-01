//
//  LoginScreen.swift
//  morethantasks
//
//  Created by Toprak Birben on 07/11/2025.
//

import SwiftUI
import Foundation

enum FocusedField {
    case email
    case password
    case confirmPassword
}


struct LoginScreen: View {
    @Binding var selectedTab: UIComponents.Tab

    @FocusState private var focusedField: FocusedField?
    @State private var presentNextView = false
    @State private var viewStack: ViewStack = .login
    @State var emailText: String = ""
    @State var passText: String = ""
    @State var isVisible: Bool = true
    @StateObject var userDB = userDatabase.shared
    var body: some View {
        NavigationStack {
            VStack {
                Text("Welcome to")
                    .font(.system(size: 14, weight: .light))
                Text("MoreThanTasks")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.bottom, 60)
                TextField("Email", text: $emailText)
                    .focused($focusedField, equals: .email)
                    .padding()
                    .background(Color("secondary-blue").opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(focusedField == .email ? Color("primary-blue"): Color.white, lineWidth: 3)
                    )
                    .padding(.horizontal)
                UIComponents.passwordFields(passwordField: $passText)
                HStack {
                    Spacer()
                    Button {
                        presentNextView.toggle()
                        viewStack = .forgottenPassword
                    } label: {
                        Text("Forgot my password")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color("primary-blue"))
                            .padding(.trailing)
                    }
                }
                
                Button {
                    userDB.loginUser(email: emailText, password: passText) { success, error in
                            if success {
                                selectedTab = .home
                            }
                        }
                } label: {
                    Text("Sign in")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color("primary-blue")))
                .padding(.horizontal)
                .padding(.vertical)
                
                OtherLoginOptions()
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

struct forgotPassword: View {
    @StateObject var userDB = userDatabase.shared

    @FocusState private var focusedField: FocusedField?

    @State var emailText: String = ""
    @State var passText: String = ""
    @State var confirmPass: String = ""
    @State var message: String = ""
    @State var isVisible: Bool = false

    var body: some View {
        VStack {
            Text("Reset Password")
                .font(.system(size: 20, weight: .bold))
                .padding(.bottom, 60)
            TextField("Email", text: $emailText)
                .focused($focusedField, equals: .email)
                .padding()
                .background(Color("secondary-blue").opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(focusedField == .email ? Color("primary-blue"): Color.white, lineWidth: 3)
                )
                .padding(.horizontal)
            
            UIComponents.passwordFields(passwordField: $passText)
            UIComponents.passwordFields(passwordField: $confirmPass)


            Button {
                if(passText == confirmPass && !passText.isEmpty && !emailText.isEmpty && !confirmPass.isEmpty) {
                    userDB.resetPassword(email: emailText, password: passText) { success, error in
                        if success {
                            message = "Password successfully changed!"
                        }
                        else {
                            message = "Password reset failed!"
                        }
                        
                    }
                }
            } label : {
                Text("Reset Password")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color("primary-blue")))
                .padding(.horizontal)
                .padding(.vertical)
            Text(message)
                .font(.system(size: 14, weight: .medium))
        }
    }
}

// This section includes logging in with other means such as google, facebook or etc
// Currently not active as it does not include functionality besides visuals.
struct OtherLoginOptions: View {
    var body: some View {
        VStack {
            Text("Or continue with")
                .foregroundStyle(Color("primary-blue"))
                .font(.system(size: 14, weight: .semibold))
            HStack {
                Button{
                    
                } label: {
                    Image(systemName: "tire")
                }
                .padding()
                .background(Color.gray.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                Button{
                    
                } label: {
                    Image(systemName: "abs.brakesignal")
                }
                .padding()
                .background(Color.gray.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                Button{
                    
                } label: {
                    Image(systemName: "robotic.vacuum")
                }
                .padding()
                .background(Color.gray.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.vertical)
        }
        .padding(.vertical)

    }
}
struct AccountSettings: View {
    var body: some View {
        Text("Account Settings")
    }
}


struct LoginScreenPreviews: PreviewProvider {
    static var previews: some View {
        RootView(selectedTab: .constant(.login))
    }
}
