//  CharID.swift
//  Globally-unique, totally-ordered identity for a single character element.
//  lamport: logical clock (see RGADocument). siteId: stable per-installation id.
import Foundation

struct CharID: Comparable, Hashable, Codable {
    let lamport: UInt64
    let siteId: UUID

    static func < (lhs: CharID, rhs: CharID) -> Bool {
        if lhs.lamport != rhs.lamport { return lhs.lamport < rhs.lamport }
        return lhs.siteId.uuidString < rhs.siteId.uuidString
    }
}
