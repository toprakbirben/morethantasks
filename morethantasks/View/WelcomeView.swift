//
//  WelcomeView.swift
//  morethantasks
//
//  Created by Toprak Birben on 07/11/2025.
//

import SwiftUI

enum ViewStack {
    case registration
    case login
    case forgottenPassword
}

struct WelcomeView: View {
    @State private var presentNextView = false
    @State private var viewStack: ViewStack = .login
    var body: some View {
        NavigationStack {
            VStack {
                Image("welcome")
                    .resizable()
                    .scaledToFit()
                    .frame(width: .infinity)
                    .padding(.top)
                    .padding(.bottom, 16)
                Text("Your notes, reminders, and tasks. All in one place.")
                    .font(.system(size: 35, weight: .bold))
                    .foregroundStyle(Color("primary-blue"))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                Text("Make your life easier with morethantasks, organised and accessible from anywhere.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                
                HStack {
                    Button {
                        presentNextView.toggle()
                        viewStack = .login
                    } label : {
                        Text("Login")
                            .font(.system(size: 20, weight: .medium))
                            .padding()
                            .foregroundStyle(Color.white)
                            .background(Color("primary-blue"))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    
                    Button {
                        presentNextView.toggle()
                        viewStack = .registration
                    } label : {
                        Text("Register")
                            .font(.system(size: 20, weight: .medium))
                            .padding()
                            .foregroundStyle(Color.white)
                            .background(Color("primary-blue"))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }
                .frame(alignment: .center)
            }
            .padding()
            .navigationDestination(isPresented: $presentNextView) {
                switch viewStack {
                    case .login: LoginScreen()
                    case .registration: AccountSettings() //for now
                    default: EmptyView()
                }
            }
        }
    }
}

#Preview {
    WelcomeView()
}
