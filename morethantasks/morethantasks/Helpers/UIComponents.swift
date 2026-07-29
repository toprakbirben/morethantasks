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
        @StateObject private var invitesVM = InvitesViewModel()

        var body: some View {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.black)

                TextField("Zoek", text: $searchText)
                    .textInputAutocapitalization(.never)
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
                            .overlay(alignment: .topTrailing) {
                                if invitesVM.invites.count > 0 {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 10, height: 10)
                                        .offset(x: 3, y: -3)
                                }
                            }
                    }
                    .task { await invitesVM.loadInvites() }
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
                .textInputAutocapitalization(.never)
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

    /// Shows the /date format hint while the user has typed "/date" but hasn't
    /// finished a valid marker yet.
    struct DateMarkerHint: View {
        let text: String

        private var isShowing: Bool {
            text.contains("/date") && Helper.shared.parseDateMarker(from: text) == nil
        }

        var body: some View {
            if isShowing {
                Text("Format: /date DD-MM-YYYY  or  /date DD-MM-YYYY HH:mm")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }

    /// A note body editor that shows the /date format hint while typing, and once a
    /// /date DD-MM-YYYY[ HH:mm] marker has been idle for a second, animates it into a
    /// pretty "28/07/2026 14:30" display. This is a display-only animation: the stored
    /// `text` binding (what gets saved as note.body) always holds the raw
    /// "/date DD-MM-YYYY[ HH:mm]" form, so EventManager/ReminderManager can keep parsing
    /// it. Moving the cursor back inside the pretty text expands it back to the raw,
    /// editable /date command, pre-filled with the same date.
    @MainActor
    struct DateMarkerTextEditor: View {
        @Binding var text: String
        var minHeight: CGFloat = 400
        var onTextChange: ((String) -> Void)? = nil

        @State private var displayText: String
        @State private var selection: TextSelection?
        @State private var collapsedRange: Range<String.Index>?
        @State private var collapsedDate: Date?
        @State private var collapsedHasTime: Bool = false
        @State private var collapseTask: Task<Void, Never>?

        init(text: Binding<String>, minHeight: CGFloat = 400, onTextChange: ((String) -> Void)? = nil) {
            self._text = text
            self.minHeight = minHeight
            self.onTextChange = onTextChange
            self._displayText = State(initialValue: text.wrappedValue)
        }

        var body: some View {
            ZStack(alignment: .bottom) {
                TextEditor(text: $displayText, selection: $selection)
                    .font(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
                    .onChange(of: displayText) { _, newValue in
                        validateCollapsedRange(in: newValue)
                        let canonical = canonicalText(from: newValue)
                        text = canonical
                        onTextChange?(canonical)
                        scheduleCollapseCheck(for: newValue)
                    }
                    .onChange(of: selection) { _, newValue in
                        expandIfNeeded(newSelection: newValue)
                    }
                    .onAppear {
                        scheduleCollapseCheck(for: displayText)
                    }

                UIComponents.DateMarkerHint(text: displayText)
            }
        }

        /// Reconstructs the raw "/date DD-MM-YYYY[ HH:mm]" form for storage, regardless of
        /// whether the editor is currently showing the collapsed "28/07/2026" display.
        private func canonicalText(from displayed: String) -> String {
            guard let collapsedRange, let collapsedDate,
                  collapsedRange.upperBound <= displayed.endIndex else {
                return displayed
            }
            let raw = Helper.shared.rawDateMarkerText(date: collapsedDate, hasTime: collapsedHasTime)
            return displayed.replacingCharacters(in: collapsedRange, with: raw)
        }

        /// Drops collapsed-range tracking if an edit elsewhere in the note shifted the
        /// text so the tracked range no longer holds the pretty date we expect.
        private func validateCollapsedRange(in currentText: String) {
            guard let collapsedRange, let collapsedDate else { return }
            guard collapsedRange.upperBound <= currentText.endIndex else {
                self.collapsedRange = nil
                self.collapsedDate = nil
                return
            }
            let expected = Helper.shared.prettyDateMarkerText(date: collapsedDate, hasTime: collapsedHasTime)
            if currentText[collapsedRange] != expected {
                self.collapsedRange = nil
                self.collapsedDate = nil
            }
        }

        private func scheduleCollapseCheck(for snapshot: String) {
            collapseTask?.cancel()
            collapseTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, displayText == snapshot else { return }
                collapseDateMarkerIfNeeded()
            }
        }

        private func collapseDateMarkerIfNeeded() {
            guard collapsedRange == nil, let match = Helper.shared.findDateMarker(in: displayText) else { return }

            let pretty = Helper.shared.prettyDateMarkerText(date: match.date, hasTime: match.hasTime)
            displayText.replaceSubrange(match.range, with: pretty)

            let newEnd = displayText.index(match.range.lowerBound, offsetBy: pretty.count)
            collapsedRange = match.range.lowerBound..<newEnd
            collapsedDate = match.date
            collapsedHasTime = match.hasTime
            selection = TextSelection(insertionPoint: newEnd)
        }

        private func expandIfNeeded(newSelection: TextSelection?) {
            validateCollapsedRange(in: displayText)
            guard let collapsedRange, let collapsedDate else { return }
            guard let newSelection, selectionTouches(collapsedRange, newSelection) else { return }

            let raw = Helper.shared.rawDateMarkerText(date: collapsedDate, hasTime: collapsedHasTime)
            displayText.replaceSubrange(collapsedRange, with: raw)

            let newCursor = displayText.index(collapsedRange.lowerBound, offsetBy: raw.count)
            self.collapsedRange = nil
            self.collapsedDate = nil
            selection = TextSelection(insertionPoint: newCursor)
        }

        /// True when the cursor sits strictly inside the collapsed pretty-date text
        /// (not merely at its edges, so placing the cursor right after typing it doesn't
        /// immediately re-expand it).
        private func selectionTouches(_ range: Range<String.Index>, _ selection: TextSelection) -> Bool {
            func inside(_ point: String.Index) -> Bool {
                range.lowerBound < point && point < range.upperBound
            }
            switch selection.indices {
            case .selection(let r):
                return inside(r.lowerBound) || inside(r.upperBound)
            case .multiSelection(let rangeSet):
                return rangeSet.ranges.contains { inside($0.lowerBound) || inside($0.upperBound) }
            }
        }
    }
}


