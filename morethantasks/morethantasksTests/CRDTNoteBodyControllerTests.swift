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

    // MARK: - applyRemoteOps (Section 3 poll loop)
    //
    // Why it matters: remote ops must merge into the same document a
    // concurrent local edit is building, and must never re-enter the outbox
    // (that would echo a peer's edit straight back to the server as if it
    // were ours).

    @Test func applyRemoteOpsMergesIntoMaterializedText() {
        let store = freshStore()
        let noteId = UUID()
        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "", store: store, siteId: UUID())
        let remoteSite = UUID()
        let op = RGAOp(type: .insert, id: CharID(lamport: 1, siteId: remoteSite), parentId: nil, char: "r")

        let result = controller.applyRemoteOps([op])

        #expect(result == "r")
        #expect(controller.materializedText == "r")
    }

    @Test func applyRemoteOpsNeverLandInTheOutbox() {
        let store = freshStore()
        let noteId = UUID()
        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "", store: store, siteId: UUID())
        let remoteSite = UUID()
        let op = RGAOp(type: .insert, id: CharID(lamport: 1, siteId: remoteSite), parentId: nil, char: "r")

        controller.applyRemoteOps([op])

        #expect(store.fetchOps(forNote: noteId) == [op])
        #expect(store.fetchOutboxOps(forNote: noteId).isEmpty)
    }

    @Test func applyRemoteOpsAndLocalEditsConvergeInOneDocument() {
        let store = freshStore()
        let noteId = UUID()
        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "ab", store: store, siteId: UUID())
        let remoteSite = UUID()
        // Remote inserts "z" after the seeded "a".
        let seedOpsCount = store.fetchOps(forNote: noteId).count
        let firstSeedOpId = store.fetchOps(forNote: noteId).first?.id
        let remoteOp = RGAOp(type: .insert, id: CharID(lamport: 100, siteId: remoteSite), parentId: firstSeedOpId, char: "z")

        controller.applyRemoteOps([remoteOp])
        let afterRemote = controller.materializedText
        let afterLocal = controller.applyLocalChange(from: afterRemote, to: afterRemote + "!")

        #expect(afterRemote.contains("z"))
        #expect(afterLocal == afterRemote + "!")
        #expect(store.fetchOps(forNote: noteId).count == seedOpsCount + 2) // remote insert + local insert
    }

    @Test func applyRemoteOpsWithEmptyArrayIsANoOp() {
        let store = freshStore()
        let noteId = UUID()
        let controller = CRDTNoteBodyController(noteId: noteId, initialBody: "same", store: store, siteId: UUID())
        let opCountAfterSeed = store.fetchOps(forNote: noteId).count

        let result = controller.applyRemoteOps([])

        #expect(result == "same")
        #expect(store.fetchOps(forNote: noteId).count == opCountAfterSeed)
    }
}
