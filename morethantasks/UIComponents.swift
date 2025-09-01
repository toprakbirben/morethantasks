//
//  UIComponents.swift
//  morethantasks
//
//  Created by Toprak Birben on 29/08/2025.
//

import Foundation
import SwiftUI

struct UIComponents {
    
    enum Tab {
        case notes, home, calendar
    }
    
    struct TaskBar: View {
        @Binding var selectedTab: Tab
        
        var body: some View {
            HStack(spacing: 44) {
                // Notes
                Button {
                    selectedTab = .notes
                } label: {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(selectedTab == .notes ? .gray : .blue)
                }
                
                // Home
                Button {
                    selectedTab = .home
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 36))
                        .foregroundColor(selectedTab == .home ? .gray : .blue)
                }
                
                // Calendar
                Button {
                    selectedTab = .calendar
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 36))
                        .foregroundColor(selectedTab == .calendar ? .gray : .blue)
                }
            }
            .padding(.horizontal, 16.0)
            .padding(.vertical, 10.0)
            .background(Color(white: 0.9))
            .cornerRadius(40.0)
            .padding()
        }
    }
    
    struct SearchBar: View {
        @State private var searchText: String = ""
        
        var body: some View {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.black)

                    TextField("Zoek", text: $searchText)
                        .foregroundColor(.black)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark")
                                .foregroundColor(.black)
                        }
                    }
                    else {
                        Button(action: {
                            
                        }) {
                            Image(systemName:"person.crop.circle")
                                .foregroundColor(.black)
                        }
                    }
                }
                .padding(.horizontal, 16.0)
                .padding(.vertical, 10.0)
                .background(Color(white: 0.9))
                .cornerRadius(40.0)
                .padding()
            }
    }
}


