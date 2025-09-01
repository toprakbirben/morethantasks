//
//  morethantasksApp.swift
//  morethantasks
//
//  Created by Toprak Birben on 29/04/2025.
//

import SwiftUI

@main
struct morethantasksApp: App {
    
    @State private var selectedTab: UIComponents.Tab = .home
    @State private var notes: [Notes] = []
    
    var body: some Scene {
        WindowGroup {
            RootView(selectedTab: $selectedTab, notes: $notes)
        }
    }
}
