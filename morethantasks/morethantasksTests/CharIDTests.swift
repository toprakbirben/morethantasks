//  CharIDTests.swift
import Testing
import Foundation
@testable import morethantasks

struct CharIDTests {
    // A lower Lamport clock always sorts earlier, regardless of site.
    @Test func lowerLamportSortsFirst() {
        let a = CharID(lamport: 1, siteId: UUID())
        let b = CharID(lamport: 2, siteId: UUID())
        #expect(a < b)
    }

    // Equal Lamport clocks tie-break deterministically on siteId string.
    @Test func equalLamportTieBreaksOnSite() {
        let lo = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let hi = UUID(uuidString: "FF000000-0000-0000-0000-000000000000")!
        let a = CharID(lamport: 5, siteId: lo)
        let b = CharID(lamport: 5, siteId: hi)
        #expect(a < b)
        #expect(!(b < a))
    }

    // Total order: the tie-break makes any two distinct ids comparable.
    @Test func distinctIdsAreOrdered() {
        let a = CharID(lamport: 5, siteId: UUID())
        let b = CharID(lamport: 5, siteId: UUID())
        #expect((a < b) || (b < a))
    }
}
