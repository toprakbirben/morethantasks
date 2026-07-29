//
//  SharedTagsViewModel.swift
//  morethantasks
//
//  Backs the "Shared Tags" section: tags other people have shared with this
//  user. Deliberately reads from the server on demand rather than the local
//  SQLite store (DatabaseManager) -- these notes aren't this device's own and
//  must stay out of its local tag groupings (see PostgresDatabase.swift's
//  pull-scope comment).

import Foundation

@MainActor
final class SharedTagsViewModel: ObservableObject {
    @Published private(set) var sharedTags: [SharedTag] = []
    @Published private(set) var notesByTag: [String: [Notes]] = [:]
    @Published var errorMessage: String?

    private let tagSharing: TagSharingService
    private let postgres: PostgresDatabase
    init(tagSharing: TagSharingService? = nil, postgres: PostgresDatabase? = nil) {
        self.tagSharing = tagSharing ?? .shared
        self.postgres = postgres ?? PostgresDatabase()
    }

    func loadSharedTags() async {
        do {
            sharedTags = try await tagSharing.fetchSharedTags()
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription ?? "Something went wrong."
        }
    }

    func loadNotes(forTag tagId: String) async {
        do {
            notesByTag[tagId] = try await tagSharing.fetchNotes(forTag: tagId)
        } catch {
            errorMessage = (error as? SharingError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// Root notes (with children attached) for an already-loaded tag. A note
    /// whose parentId points outside this tag's fetched set is its own root.
    func rootNotes(forTag tagId: String) -> [Notes] {
        let all = notesByTag[tagId] ?? []
        let ids = Set(all.map(\.id))
        var byParent: [UUID: [Notes]] = [:]
        for note in all {
            if let pid = note.parentId, ids.contains(pid) {
                byParent[pid, default: []].append(note)
            }
        }
        func attach(_ node: Notes) -> Notes {
            var copy = node
            copy.children = (byParent[node.id] ?? []).map(attach)
            return copy
        }
        return all
            .filter { $0.parentId == nil || !ids.contains($0.parentId!) }
            .map(attach)
    }

    /// Pushes title/body/tag edits straight to the server -- bypassing
    /// DatabaseManager, since this note isn't (and shouldn't become) part of
    /// this device's own local store.
    func updateNoteMetadata(_ note: Notes) async {
        do {
            try await postgres.update(
                noteId: note.id.uuidString,
                title: note.title,
                noteParent: nil,
                noteColor: note.colorHex,
                tag: note.tag
            )
        } catch {
            errorMessage = "Something went wrong."
        }
    }
}
