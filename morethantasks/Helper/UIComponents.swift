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
        case notes, home, calendar, welcome, login, register
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
            .padding(.horizontal)
            .padding(.vertical)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 4)
            .padding()
        }
    }
    
    struct SearchBar: View {
        @Binding var searchText: String
        @Binding var selectedTab: UIComponents.Tab

        @State private var presentNextView = false
        @State private var viewStack: ViewStack = .welcome
        
        var body: some View {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.black)

                TextField("Zoek", text: $searchText)
                    .foregroundColor(.black)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label : {
                        Image(systemName: "xmark")
                            .foregroundColor(.black)
                    }
                } else {
                    Button {
                        presentNextView.toggle()
                        viewStack = .accountSettings
                    } label : {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.black)
                    }
                }
            }
            .navigationDestination(isPresented: $presentNextView) {
                switch viewStack {
                    case .accountSettings: AccountView(selectedTab: $selectedTab)
                    default: EmptyView()
                }
            }
            .padding(.horizontal)
            .padding(.vertical)
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
                    .foregroundColor(Color(hex: note.colorHex ?? "#007BFF").opacity(0.8))
                    .cornerRadius(12)
                    .opacity(0.80)
                    .overlay(alignment: .bottom) {
                        Text(note.title)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 14, weight: .semibold))
                            .padding()
                            .frame(width:widthOfNote, height: heightOfNote/2)
                            .background(Color(hex: note.colorHex ?? "#007BFF"))
                            .cornerRadius(12)
                    }
            }
        }
        
    }
    
    struct NoteCell : View {
        let note : Notes
        var body: some View {
            Text(note.title)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(hex: note.colorHex ?? "#007BFF").opacity(0.8))
                .cornerRadius(12)
            
        }
    }
    
    struct passwordFields : View {
        @Binding var passwordField: String
        @State var isVisible: Bool = false
        @FocusState private var focusedField: FocusedField?

        var body: some View {
            ZStack {
                Group {
                    if isVisible {
                        TextField("Confirm Password", text: $passwordField)
                    } else {
                        SecureField("Confirm Password", text: $passwordField)
                    }
                }
                .focused($focusedField, equals: .confirmPassword)
                .padding()
                .background(Color("secondary-blue").opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(focusedField == .confirmPassword ? Color("primary-blue") : Color.white,
                                lineWidth: 3)
                )
                .padding(.horizontal)
                .overlay(
                    Button {
                        isVisible.toggle()
                    } label: {
                        Image(systemName: isVisible ? "eye" : "eye.slash")
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal)
                    .padding(.trailing, 20),
                    alignment: .trailing
                )
            }
        }
    }
}


