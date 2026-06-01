//
//  AccountView.swift
//  morethantasks
//
//  Created by Toprak Birben on 12/11/2025.
//

import SwiftUI
import Foundation


struct AccountView : View {
    @StateObject var userDB = userDatabase.shared
    @Binding var selectedTab: UIComponents.Tab

    var body: some View {
        
        NavigationStack {
            VStack {
                Text("Profile Settings")
                    .font(.system(size: 24, weight: .bold))
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .foregroundColor(Color("primary-blue"))
                Text("Hello \(UserDefaults.standard.string(forKey: "loggedInUserEmail") ?? "")")
                    .font(.system(size: 20, weight: .medium))
                
                
                Button {
                    userDB.logout()
                    selectedTab = .welcome
                } label : {
                    Text("Log out")
                }
                
                Button {
                    userDB.delete_user { success in
                        if success {
                            print("User deleted successfully")
                            selectedTab = .welcome
                        } else {
                            print("Failed to delete user")
                        }
                    }
                } label : {
                    Text("Delete Account")
                }
                
            }
        }
    }
}

struct AccountSetting: PreviewProvider {
    static var previews: some View {
        RootView(selectedTab: .constant(.login))
    }
}
