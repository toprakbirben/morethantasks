//  RGAOp.swift
//  One CRDT operation. insert: a new element `id` placed after `parentId`
//  (nil = document start) carrying `char`. delete: tombstone the element `id`
//  (parentId/char are nil for deletes). Codable — this is the sync wire format.
import Foundation

enum RGAOpType: String, Codable {
    case insert
    case delete
}

struct RGAOp: Codable, Hashable {
    let type: RGAOpType
    let id: CharID
    let parentId: CharID?
    let char: String?   // single character; non-nil only for inserts
}
