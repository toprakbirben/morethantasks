//  CRDTNoteBodyControllerTests.swift
import Testing
import Foundation
@testable import morethantasks

struct CRDTNoteBodyControllerTests {
    private func freshStore() -> CRDTStore { CRDTStore(dbPath: ":memory:") }

    @Test func firstOpenOfANewNoteSeedsOpsFromTheInitialBody() {
        let store = freshStore()
        let noteId = UUID()

        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "hello", store: store, siteId: UUID())

        #expect(controller.materializedText == "hello")
        #expect(store.hasOps(forNote: noteId) == true)
    }

    @Test func emptyInitialBodySeedsNoOps() {
        let store = freshStore()
        let noteId = UUID()

        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "", store: store, siteId: UUID())

        #expect(controller.materializedText == "")
        #expect(store.hasOps(forNote: noteId) == false)
    }

    @Test func applyLocalChangePersistsOpsAndReturnsTheMaterializedText() {
        let store = freshStore()
        let noteId = UUID()
        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "ab", store: store, siteId: UUID())

        let result = controller.applyLocalChange(from: "ab", to: "axb")

        #expect(result == "axb")
        // seed ops (a, b) + one insert op for x
        #expect(store.fetchOps(forNote: noteId).count == 3)
    }

    @Test func reopeningAnExistingNoteRehydratesFromStoredOpsWithoutReseeding() {
        let store = freshStore()
        let noteId = UUID()
        let first = CRDTNoteBodyController(noteId: noteId, initialBody: "hello", store: store, siteId: UUID())
        first.applyLocalChange(from: "hello", to: "hello world")
        let opCountAfterFirstSession = store.fetchOps(forNote: noteId).count

        // Simulate an app relaunch: a brand-new controller for the same note.
        let second = CRDTNoteBodyController(noteId: noteId, initialBody: "hello world", store: store, siteId: UUID())

        #expect(second.materializedText == "hello world")
        #expect(store.fetchOps(forNote: noteId).count == opCountAfterFirstSession)
    }

    @Test func noOpChangeAppendsNoOps() {
        let store = freshStore()
        let noteId = UUID()
        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "same", store: store, siteId: UUID())
        let opCountAfterSeed = store.fetchOps(forNote: noteId).count

        let result = controller.applyLocalChange(from: "same", to: "same")

        #expect(result == "same")
        #expect(store.fetchOps(forNote: noteId).count == opCountAfterSeed)
    }
}
