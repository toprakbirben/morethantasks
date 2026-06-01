//
//  morethantasksApp.swift
//  morethantasks
//
//  Created by Toprak Birben on 29/04/2025.
//

import SwiftUI

@main
struct morethantasksApp: App {
    
    @State private var selectedTab: UIComponents.Tab = .welcome
    @StateObject private var userDB = userDatabase.shared
    
    var body: some Scene {
        WindowGroup {
            RootView(selectedTab: $selectedTab)
        }
    }
}
