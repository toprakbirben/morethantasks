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
}


struct LoginScreen: View {
    @FocusState private var focusedField: FocusedField?
    @State private var presentNextView = false
    @State private var viewStack: ViewStack = .login
    @State var emailText: String = ""
    @State var passText: String = ""
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
                TextField("Password", text: $passText)
                    .focused($focusedField, equals: .password)
                    .padding()
                    .background(Color("secondary-blue").opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(focusedField == .password ? Color("primary-blue"): Color.white, lineWidth: 3)
                    )
                    .padding(.horizontal)
                HStack {
                    Spacer()
                    Button {
                        presentNextView.toggle()
                        viewStack = .forgottenPassword
                    } label: {
                        Text("Forgor my password")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color("primary-blue"))
                            .padding(.trailing)
                    }
                }
                
                Button {
                    /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Action@*/ /*@END_MENU_TOKEN@*/
                    //make this button go to LandingPage
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
    var body: some View {
        Text("Forgot Password?")
    }
}

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


#Preview {
    LoginScreen()
}
