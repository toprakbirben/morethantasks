//
//  NoteView.swift
//  morethantasks
//
//  Created by Toprak Birben on 25/08/2025.
//

import SwiftUI
import Combine

struct NoteView: View {
    @Binding var selectedTab: UIComponents.Tab
    @State private var notes: [Notes] = []
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GeometryReader { geometry in
                    VStack {
                        UIComponents.SearchBar(searchText: $searchText)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            RecentNoteView(notes: notes)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        
                        NoteListView(notes: $notes, onRefresh: refreshNotes)
                        .padding()
                    }
                    .onAppear {
                        refreshNotes()
                    }
                    NoteAdd {
                        refreshNotes()
                    }.frame(width: 80, height: 80).position(x: geometry.size.width - 60, y: geometry.size.height - 60)
                }
            }
        }
    }
    
    private func refreshNotes() {
        DatabaseManager.shared.fetchNotes()
        notes = DatabaseManager.shared.getNotes()
    }
}

// MARK: - Recent Notes Horizontal View
struct RecentNoteView: View {
    let notes: [Notes]
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "clock").imageScale(.small)
                Text("Recenten").font(.headline)
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(notes, id: \.id) { note in
                        NavigationLink(
                            destination: NoteDetailView(note: note) { updatedTitle, updatedText in
                                var updatedNote = note
                                updatedNote.title = updatedTitle
                                updatedNote.body = updatedText
                                DatabaseManager.shared.update(note: updatedNote)
                            }
                        ) {
                            UIComponents.RecentNotes(
                                note: note,
                                widthOfNote: 100,
                                heightOfNote: 100
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

// MARK: - Note List View
struct NoteListView: View {
    @Binding var notes: [Notes]
    @State var showModal: Bool = false
    @State private var selectedNote: Notes? = nil
    var onRefresh: (() -> Void)?

    var body: some View {
        List {
            ForEach(notes) { note in
                NavigationLink(
                    destination: NoteDetailView(note: note) { updatedTitle, updatedText in
                        var updatedNote = note
                        updatedNote.title = updatedTitle
                        updatedNote.body = updatedText
                        DatabaseManager.shared.update(note: updatedNote)
                        onRefresh?()
                    }
                ) {
                    UIComponents.NoteCell(note: note)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        DatabaseManager.shared.delete(noteId: note.id)
                        onRefresh?()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        showModal = true
                        selectedNote = note
                    } label: {
                        Label("Preferences", systemImage: "wrench")
                    }
                }
            }
        }
        .listStyle(.plain)
        .sheet(item: $selectedNote) { noteItem in
            if let index = notes.firstIndex(where: { $0.id == noteItem.id }) {
                ModalPreference(note: $notes[index], allNotes: notes)
                    .presentationDetents([.medium])
            } else {
                EmptyView()
            }
        }
    }
}

// MARK: - Modal Preferences
struct ModalPreference: View {
    @Binding var note: Notes
    let allNotes: [Notes]
    
    private var possibleParents: [Notes] {
        allNotes.filter { $0.id != note.id }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Visualistics") {
                    Picker("Note Appearance", selection: Binding(
                        get: { note.colorHex ?? "#007BFF" },
                        set: { newColor in
                            note.colorHex = newColor
                            DatabaseManager.shared.update(note: note)
                        }
                    )) {
                        Text("Blue").tag("#007BFF")
                        Text("Red").tag("#DC3545")
                        Text("Green").tag("#28A745")
                        Text("Purple").tag("#6F42C1")
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Parent Note") {
                    Picker("Parent Node", selection: Binding(
                        get: { note.parentId },
                        set: { newParentId in
                            note.parentId = newParentId
                            DatabaseManager.shared.update(note: note)
                        }
                    )) {
                        Text("None").tag(UUID?.none)
                        ForEach(possibleParents) { parent in
                            Text(parent.title).tag(Optional(parent.id))
                        }
                    }
                }
            }
            .navigationTitle("Preferences")
        }
    }
}

// MARK: - Note Detail View
struct NoteDetailView: View {
    let note: Notes
    @State var title: String
    @State var text: String
    
    var onSave: ((String, String) -> Void)?

    init(note: Notes, onSave: ((String, String) -> Void)? = nil) {
        self.note = note
        _title = State(initialValue: note.title)
        _text = State(initialValue: note.body)
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                    .font(.largeTitle)
                    .textInputAutocapitalization(.never)
                    .onChange(of: title) { oldValue, newValue in
                        onSave?(newValue, text)
                    }
                    .bold()
                
                Divider()
                
                TextEditor(text: $text)
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 500)
                    .padding()
                    .onChange(of: text) { oldValue, newValue in
                        onSave?(title, newValue)
                    }
            }
            .padding()
        }
        .navigationTitle(title.isEmpty ? "Untitled" : title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Note Button
struct NoteAdd: View {
    @State private var showNoteCreation = false
    var onNoteAdded: (() -> Void)?

    var body: some View {
        VStack {
            Button {
                showNoteCreation = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
            }
            .fullScreenCover(isPresented: $showNoteCreation) {
                NoteCreationView { title, body in
                    let note = Notes(
                        id: UUID(),
                        title: title,
                        body: body,
                        parentId: nil,
                        children: [],
                        lastUpdated: Date(),
                        createdByUserId: "toprak",
                        colorHex: "#007BFF"
                    )
                    DatabaseManager.shared.insert(note: note)
                    onNoteAdded?()
                }
            }
        }
    }
}

// MARK: - Note Creation View
struct NoteCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    var onSave: (String, String) -> Void
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    if text.isEmpty { dismiss(); return }
                    let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                    let title = lines.first.map(String.init) ?? ""
                    let body = lines.count > 1 ? String(lines[1]) : ""
                    
                    onSave(title, body)
                    dismiss()
                }) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline)
                }
                Spacer()
            }
            .padding()
            
            TextEditor(text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct NoteView_Previews: PreviewProvider {
    static var previews: some View {
        NoteView(selectedTab: .constant(.notes))
    }
}
