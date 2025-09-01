//
//  Notes.swift
//  morethantasks
//
//  Created by Toprak Birben on 25/08/2025.
//

import Foundation
import GRDB


struct Notes: Identifiable, Codable {
    let id: UUID
    let title: String
    let body: String
    let parentId: UUID?
    var children: [Notes] = []
    var lastUpdated: Date
    var createdByUserId: String
    
    static let databaseTableName = "notes"
}
