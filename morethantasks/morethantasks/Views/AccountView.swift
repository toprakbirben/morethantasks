//
//  AccountView.swift
//  morethantasks
//
//  Created by Toprak Birben on 12/11/2025.
//

import SwiftUI
import Foundation


struct AccountView : View {
    @StateObject private var vm = AccountViewModel()
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
                Text("Hello \(vm.userEmail)")
                    .font(.system(size: 20, weight: .medium))


                Button {
                    vm.logout()
                } label : {
                    Text("Log out")
                }

                Button {
                    Task { await vm.deleteAccount() }
                } label : {
                    Text("Delete Account")
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                }

            }
            .onChange(of: vm.didSignOut) { _, didSignOut in
                if didSignOut { selectedTab = .welcome }
            }
        }
    }
}

struct AccountSetting: PreviewProvider {
    static var previews: some View {
        RootView(selectedTab: .constant(.login))
    }
}
