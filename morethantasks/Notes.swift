//
//  Notes.swift
//  morethantasks
//
//  Created by Toprak Birben on 25/08/2025.
//

import Foundation

struct Notes: Identifiable, Codable {
    let id: UUID
    var title: String
    var body: String
    var parentId: UUID?
    var children: [Notes] = []
    var lastUpdated: Date
    var createdByUserId: String
    var colorHex: String?
    var tag: String?
    
    static let databaseTableName = "notes"
}
