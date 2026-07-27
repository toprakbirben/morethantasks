//  CRDTStoreTests.swift
import Testing
import Foundation
@testable import morethantasks

struct CRDTStoreTests {
    private func makeStore() -> CRDTStore { CRDTStore(dbPath: ":memory:") }

    private func site() -> (UInt64) -> CharID {
        let s = UUID()
        return { lamport in CharID(lamport: lamport, siteId: s) }
    }

    @Test func newNoteHasNoOps() {
        let store = makeStore()
        #expect(store.hasOps(forNote: UUID()) == false)
    }

    @Test func appendThenFetchReturnsTheSameOps() {
        let store = makeStore()
        let noteId = UUID()
        let id = site()
        let a = id(1)
        let op = RGAOp(type: .insert, id: a, parentId: nil, char: "x")

        store.appendLocalOps([op], noteId: noteId)

        #expect(store.hasOps(forNote: noteId) == true)
        #expect(store.fetchOps(forNote: noteId) == [op])
    }

    @Test func appendingTheSameOpTwiceDoesNotDuplicateIt() {
        let store = makeStore()
        let noteId = UUID()
        let id = site()
        let op = RGAOp(type: .insert, id: id(1), parentId: nil, char: "x")

        store.appendLocalOps([op], noteId: noteId)
        store.appendLocalOps([op], noteId: noteId)

        #expect(store.fetchOps(forNote: noteId).count == 1)
    }

    @Test func opsFromDifferentNotesDoNotLeakIntoEachOther() {
        let store = makeStore()
        let noteA = UUID()
        let noteB = UUID()
        let id = site()
        store.appendLocalOps([RGAOp(type: .insert, id: id(1), parentId: nil, char: "a")], noteId: noteA)

        #expect(store.fetchOps(forNote: noteA).count == 1)
        #expect(store.fetchOps(forNote: noteB).isEmpty)
    }

    @Test func fetchOpsOrdersByLamportAscending() {
        let store = makeStore()
        let noteId = UUID()
        let id = site()
        let a = id(1); let b = id(2); let c = id(3)
        // Insert out of lamport order to prove fetch re-sorts, not just echoes insert order.
        store.appendLocalOps([
            RGAOp(type: .insert, id: c, parentId: b, char: "c"),
            RGAOp(type: .insert, id: a, parentId: nil, char: "a"),
            RGAOp(type: .insert, id: b, parentId: a, char: "b"),
        ], noteId: noteId)

        #expect(store.fetchOps(forNote: noteId).map(\.id.lamport) == [1, 2, 3])
    }

    @Test func deleteOpRoundTripsWithNilCharAndNilParent() {
        let store = makeStore()
        let noteId = UUID()
        let id = site()
        let del = RGAOp(type: .delete, id: id(5), parentId: nil, char: nil)

        store.appendLocalOps([del], noteId: noteId)

        #expect(store.fetchOps(forNote: noteId) == [del])
    }

    @Test func applyRemoteOpsWritesToTheAppliedLog() {
        let store = makeStore()
        let noteId = UUID()
        let op = RGAOp(type: .insert, id: site()(1), parentId: nil, char: "r")

        store.applyRemoteOps([op], noteId: noteId)

        #expect(store.fetchOps(forNote: noteId) == [op])
    }

    @Test func appendLocalOpsAlsoLandsInTheOutbox() {
        let store = makeStore()
        let noteId = UUID()
        let op = RGAOp(type: .insert, id: site()(1), parentId: nil, char: "x")

        store.appendLocalOps([op], noteId: noteId)

        #expect(store.fetchOutboxOps(forNote: noteId) == [op])
    }

    @Test func removeFromOutboxDropsOnlyThoseOpsFromTheOutboxNotTheAppliedLog() {
        let store = makeStore()
        let noteId = UUID()
        let id = site()
        let a = RGAOp(type: .insert, id: id(1), parentId: nil, char: "a")
        let b = RGAOp(type: .insert, id: id(2), parentId: id(1), char: "b")
        store.appendLocalOps([a, b], noteId: noteId)

        store.removeFromOutbox([a], noteId: noteId)

        #expect(store.fetchOutboxOps(forNote: noteId) == [b])
        #expect(store.fetchOps(forNote: noteId) == [a, b])
    }

    @Test func applyRemoteOpsNeverLandsInTheOutbox() {
        let store = makeStore()
        let noteId = UUID()
        let op = RGAOp(type: .insert, id: site()(1), parentId: nil, char: "r")

        store.applyRemoteOps([op], noteId: noteId)

        #expect(store.fetchOps(forNote: noteId) == [op])
        #expect(store.fetchOutboxOps(forNote: noteId).isEmpty)
    }
}
