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
        @Binding var searchText: String
        
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
                } else {
                    Button(action: {
                        // profile action
                    }) {
                        Image(systemName: "person.crop.circle")
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

    
    struct RecentNotes: View {
        let note: Notes
        let widthOfNote : CGFloat
        let heightOfNote : CGFloat
        var body : some View {
            ZStack{
                Rectangle()
                    .frame(width:widthOfNote, height: heightOfNote)
                    .foregroundColor(Color(hex: note.colorHex ?? "#007BFF")?.opacity(0.8) ?? Color.blue.opacity(0.8))
                    .cornerRadius(10)
                    .opacity(0.60)
                    .overlay(alignment: .bottom) {
                        Text(note.title)
                            .padding()
                            .frame(width:widthOfNote, height: heightOfNote/2, alignment: .bottomLeading)
                            .background(Color(hex: note.colorHex ?? "#007BFF")?.opacity(0.8) ?? Color.blue.opacity(0.8))
                            .cornerRadius(10)
                            .opacity(0.80)
                    }
            }
        }
        
    }
    
    struct NoteCell : View {
        let note : Notes
        var body: some View {
            Text(note.title)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(hex: note.colorHex ?? "#007BFF")?.opacity(0.8) ?? Color.blue.opacity(0.8))
                .cornerRadius(10)
            
        }
    }
}


