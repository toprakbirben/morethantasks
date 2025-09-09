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
    @State private var tree: [Notes] = []
    @State private var notes: [Notes] = []

    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    UIComponents.SearchBar()
                    ScrollView(.horizontal, showsIndicators: false) {
                        RecentNoteView(notes: notes)
                    }.fixedSize(horizontal: false, vertical: true)
                    NoteListView(notes: $notes, onRefresh: refreshNotes)
                    HStack {
                        Spacer()
                        NoteAdd() {
                            refreshNotes()
                        }.background(.regularMaterial)
                    }.padding()
                }
                
            }
            .onAppear {
                refreshNotes()
            }
        }
        
    }
    
    private func refreshNotes() {
        notes = PostgresDatabase.shared.fetchNotes()
        tree = PostgresDatabase.buildNoteTree(from: notes)
        //tree = PostgresDatabase.buildTreeHierarchy(from: notes)
    }
}

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
                            destination: NoteDetailView(note: note) { updatedText, updatedTitle in editNote(
                                noteId: note.id.uuidString,
                                title: updatedTitle,
                                noteBody: updatedText,
                                noteParent: note.parentId?.uuidString ?? nil,
                                noteColor: note.colorHex
                            ) {
                                print("Note updated")
                            }
                            })
                        {
                            UIComponents.RecentNotes(
                                note: note,
                                widthOfNote: 100,
                                heightOfNote: 100)
                        }.buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

struct NoteListView: View {
    @Binding var notes: [Notes]
    @State var showModal: Bool = false
    @State private var selectedNote: Notes? = nil

    var onRefresh: (() -> Void)?

    var body: some View {
        List {
            ForEach(notes) { note in
                NavigationLink(
                    destination: NoteDetailView(note: note) { updatedText, updatedTitle in editNote(
                        noteId: note.id.uuidString,
                        title: updatedTitle,
                        noteBody: updatedText,
                        noteParent: note.parentId?.uuidString ?? nil,
                        noteColor: note.colorHex
                    ) {
                    }
                    }
                ) {
                    UIComponents.NoteCell(note: note)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteNote(noteId: note.id.uuidString) {
                            onRefresh?()
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button
                    {
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


struct NoteRow: View {
    var body: some View {
    }
}


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
                            DispatchQueue.main.async {
                                editNote(
                                    noteId: note.id.uuidString,
                                    title: note.title,
                                    noteBody: note.body,
                                    noteParent: note.parentId?.uuidString,
                                    noteColor: newColor
                                ) { print("✅ note color updated")
                                    print("color \(newColor)")}
                            }
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
                            DispatchQueue.main.async {
                                editNote(
                                    noteId: note.id.uuidString,
                                    title: note.title,
                                    noteBody: note.body,
                                    noteParent: newParentId?.uuidString,
                                    noteColor: note.colorHex
                                ) { print("✅ parent updated") }
                            }
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


///
///It becomes lowercase when caps lock is on I dont know why it behaves like that
///as of 9/9/2025 this no longer is the case 
///

struct NoteDetailView: View {
    let note: Notes
    @State var title: String
    @State var text: String
    @State private var didAppear = false
    
    private let originalTitle: String
    private let originalText: String
    var onSave: ((String, String) -> Void)?

    init(note: Notes, onSave: ((String, String) -> Void)? = nil) {
        self.note = note
        _title = State(initialValue: note.title)
        _text = State(initialValue: note.body)
        self.originalTitle = note.title
        self.originalText = note.body
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                    .font(.largeTitle)
                    .textInputAutocapitalization(.never)
                    .onChange(of: title) {oldValue, newValue in
                        if !newValue.isEmpty {
                            editNote(noteId: note.id.uuidString, title: newValue, noteBody: text, noteParent: note.parentId?.uuidString, noteColor: note.colorHex) {
                            }
                        }
                    }
                    .bold()
                Divider()
                HStack{
                }
                TextEditor(text: $text)
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 500) //should stay as it is right now
                    .fixedSize(horizontal: false, vertical: false)
                    .padding()
                    .onChange(of: text) {oldValue, newValue in
                        if !newValue.isEmpty {
                            editNote(noteId: note.id.uuidString, title: title, noteBody: newValue, noteParent: note.parentId?.uuidString, noteColor: note.colorHex) {
                            }
                        }
                        
                    }
            }
            .padding()
        }
        .navigationTitle(title.isEmpty ? "Untitled" : title)
        .navigationBarTitleDisplayMode(.inline)
    }

}


struct NoteAdd: View {
    @State private var showNoteCreation = false
    var onNoteAdded: (() -> Void)?

    var body: some View {
        VStack {
            Button {
                showNoteCreation = true
            } label: {
                Image(systemName: "plus.app.fill")
                    .font(.system(size: 40))
            }
            .fullScreenCover(isPresented: $showNoteCreation) {
                NoteCreationView { title, body in
                    addNote(title: title, noteBody: body) {
                        onNoteAdded?()
                    }
                }
                    
            }
        }
    }
}

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


func deleteNote(noteId: String, completion: @escaping () -> Void) {
    guard let url = URL(string: "http://192.168.178.187:8000/remove_note") else { return }
    
    let noteData: [String: Any] = ["note_id": noteId]
    
    guard let jsonData = try? JSONSerialization.data(withJSONObject: noteData) else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("Error deleting note:", error)
            return
        }
        
        if let data = data {
            if let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("Delete response:", responseJSON)
            }
        }
        
        DispatchQueue.main.async {
            completion()
        }
    }.resume()
}

func addNote(title: String, noteBody: String, completion: @escaping () -> Void) {
    guard let url = URL(string: "http://192.168.178.187:8000/add_note") else { return }
    
    let noteData: [String: Any] = [
        "title": title,
        "body": noteBody,
        "created_by_user_id": "toprak"
    ]
    
    guard let jsonData = try? JSONSerialization.data(withJSONObject: noteData) else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("Error adding note:", error)
        } else {
            print("Note added successfully")
            DispatchQueue.main.async {
                completion()
            }
        }
    }.resume()
}

func editNote(noteId: String, title: String?, noteBody: String?, noteParent: String?, noteColor: String?, completion: @escaping () -> Void) {
    guard let url = URL(string: "http://192.168.178.187:8000/edit_note") else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "PATCH"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var body: [String: Any] = ["note_id": noteId]
    if let title = title {
        body["title"] = title
    }
    if let noteBody = noteBody {
        body["body"] = noteBody
    }
    if let noteParent = noteParent {
        body["parent_id"] = noteParent
    }
    if let noteColor = noteColor {
        body["color"] = noteColor
    }
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: request) { _, response, error in
        if let error = error {
            print("Error editing note: \(error.localizedDescription)")
            return
        }

        DispatchQueue.main.async {
            completion()
        }
    }.resume()
}


struct NoteView_Previews: PreviewProvider {
    static var previews: some View {
        NoteView(selectedTab: .constant(.notes))
    }
}
