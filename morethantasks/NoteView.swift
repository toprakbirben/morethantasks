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
    @State private var searchText: String = ""
    
    @StateObject var db = DatabaseManager.shared
    
    
    var body: some View {
        NavigationStack {
            ZStack {
                GeometryReader { geometry in
                    VStack {
                        UIComponents.SearchBar(searchText: $searchText)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            RecentNoteView(database: db)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        
                        NoteListView(notes: $db.notesArray, existingTags: $db.tagsArray)
                        .padding()
                    }
                    NoteAdd()
                        .frame(width: 80, height: 80).position(x: geometry.size.width - 60, y: geometry.size.height - 60)
                }
            }
        }
        .onAppear {
            print(db.tagsArray)
        }

    }
}

// MARK: - Recent Notes Horizontal View
struct RecentNoteView: View {
    @StateObject var database: DatabaseManager
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "clock").imageScale(.small)
                Text("Recenten").font(.headline)
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(database.notesArray, id: \.id) { note in
                        NavigationLink(
                            destination: NoteDetailView(note: note, tagsArray: $database.tagsArray) { updatedTitle, updatedText, updatedTag in
                                var updatedNote = note
                                updatedNote.title = updatedTitle
                                updatedNote.body = updatedText
                                updatedNote.tag = updatedTag
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
    @Binding var existingTags: [String]
    
    @State var showModal: Bool = false
    @State var selectedNote: Notes? = nil
    
    var body: some View {
        List {
            ForEach(existingTags, id: \.self) { tag in
                let filteredNotes = notes.filter { note in
                    let currentTag = (note.tag?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? "None" : note.tag!
                    return currentTag == tag
                }
                Section(tag) {
                    ForEach(filteredNotes) { note in
                        NoteRowView(note: note, existingTags: $existingTags, showModal: $showModal, selectedNote: $selectedNote)
                    }
                }
            }
        }
        .listStyle(.plain)
        .sheet(item: $selectedNote) { noteItem in
            if let index = notes.firstIndex(where: { $0.id == noteItem.id }) {
                ModalPreference(note: $notes[index], allNotes: notes, existingTags: DatabaseManager.shared.getTags())
                    .presentationDetents([.medium])
            } else {
                EmptyView()
            }
        }
    }
}


struct NoteRowView : View {
    let note: Notes
    @Binding var existingTags: [String]
    @Binding var showModal: Bool
    @Binding var selectedNote: Notes?
    
    var body: some View {
        NavigationLink(
            destination: NoteDetailView(note: note, tagsArray: $existingTags) { updatedTitle, updatedText, updatedTag in
                var updatedNote = note
                updatedNote.title = updatedTitle
                updatedNote.body = updatedText
                updatedNote.tag = updatedTag
                DatabaseManager.shared.update(note: updatedNote)
            }
        ) {
            UIComponents.NoteCell(note: note)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                DatabaseManager.shared.delete(noteId: note.id)
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

// MARK: - Modal Preferences
struct ModalPreference: View {
    @Binding var note: Notes
    let allNotes: [Notes]
    let existingTags: [String]
    
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
                TagPreference(existingTags: existingTags, note: $note)
            }
            .navigationTitle("Preferences")
        }
    }
}

struct TagPreference: View {
    let existingTags: [String]
    @Binding var note : Notes
    
    var body: some View {
        Section("Tag") {
            Picker("Node", selection: Binding(
                get: {note.tag ?? ""},
                set: {newTag in
                    note.tag = newTag
                    DatabaseManager.shared.update(note: note)
                }
            )) {
                Text("None").tag("")
                ForEach(existingTags, id: \.self) { tag in
                    Text(tag).tag(tag)
                }
            }
        }
    }
}

// MARK: - Note Detail View
struct NoteDetailView: View {
    let note: Notes
    @Binding var tagsArray: [String]
    
    @State var title: String
    @State var text: String
    @State var tag: String = ""

    
    var onSave: ((String, String, String) -> Void)?

    init(note: Notes, tagsArray: Binding<[String]>, onSave: ((String, String, String) -> Void)? = nil) {
        self.note = note
        self._tagsArray = tagsArray
        _title = State(initialValue: note.title)
        _text = State(initialValue: note.body)
        _tag = State(initialValue: note.tag ?? "")
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                    .font(.largeTitle)
                    .textInputAutocapitalization(.never)
                    .onChange(of: title) { oldValue, newValue in
                        onSave?(newValue, text, tag)
                    }
                    .bold()
                
                Divider()
                
                TagSelection(existingTags: tagsArray, tag: $tag)
                    .onChange(of: tag) { oldValue, newValue in
                        onSave?(title, text, newValue)
                    }
                
                TextEditor(text: $text)
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 500)
                    .padding()
                    .onChange(of: text) { oldValue, newValue in
                        onSave?(title, newValue, tag)
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
                NoteCreationView(
                    onSave: { title, body, tag in
                        let note = Notes(
                            id: UUID(),
                            title: title,
                            body: body,
                            parentId: nil,
                            children: [],
                            lastUpdated: Date(),
                            createdByUserId: "toprak",
                            colorHex: "#007BFF",
                            tag: tag
                        )
                        DatabaseManager.shared.insert(note: note)
                        onNoteAdded?()
                    },
                    existingTags: DatabaseManager.shared.getTags()
                )
            }
        }
    }
}

// MARK: - Note Creation View
struct NoteCreationView: View {
    @Environment(\.dismiss) var dismiss
    @State var text: String = ""
    @State var tag: String = ""
    var onSave: (String, String, String) -> Void
    var existingTags : [String]
    @State private var showDropdown = false

    
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    if text.isEmpty { dismiss(); return }
                    let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                    let title = lines.first.map(String.init) ?? ""
                    let body = lines.count > 1 ? String(lines[1]) : ""
                    
                    onSave(title, body, tag)
                    dismiss()
                }) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline)
                }
                Spacer()
            }
            .padding()
            
            TagSelection(existingTags: existingTags, tag: $tag)

            
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

struct TagSelection: View {
    var existingTags : [String]
    @State var showDropdown = false
    @Binding var tag: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(
                isExpanded: $showDropdown,
                content: {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(existingTags, id: \.self) { existingTags in
                            Button(existingTags) {
                                tag = existingTags
                                showDropdown = false
                            }
                            .padding(.vertical, 2)
                        }
                        
                        Divider()
                        TextField("New tag...", text: $tag)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.vertical, 2)
                    }
                    .padding()
                },
                label: {
                    HStack {
                        Text(tag.isEmpty ? "Tag..." : tag)
                            .foregroundColor(tag.isEmpty ? .secondary : .primary)
                        
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
            )
        }
    }
}

struct NoteView_Previews: PreviewProvider {
    static var previews: some View {
        NoteView(selectedTab: .constant(.notes))
    }
}
