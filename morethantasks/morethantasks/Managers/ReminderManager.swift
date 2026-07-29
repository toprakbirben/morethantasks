//
//  ReminderManager.swift
//  morethantasks
//
//  Created by Toprak Birben on 23/09/2025.
//
import Foundation
import Combine
import NaturalLanguage
import SwiftUI


struct Reminder: Identifiable {
    let id: UUID
    var body: String
    var dueDate: Date
    var isCompleted: Bool = false
    
    
    init(
        id: UUID = UUID(),
        body: String,
        dueDate: Date,
        isCompleted: Bool
    ) {
        self.id = id
        self.body = body
        self.dueDate = dueDate
        self.isCompleted = isCompleted
    }
}

@MainActor
class ReminderManager: ObservableObject {
    static let shared = ReminderManager()
    private var cancellables = Set<AnyCancellable>()

    @Published var remindersArray : [Reminder] = []
    private var db = DatabaseManager.shared

    func createReminders(noteArray: [Notes]) {
        for note in noteArray {
            if remindersArray.contains(where: { $0.id == note.id }) {continue}
            guard let parsed = Helper.shared.parseDateMarker(from: note.body) else {
                continue
            }
            let cleanedBody = Helper.shared.extractTitle(from: note.body)
            let body = cleanedBody.isEmpty ? note.title : cleanedBody

            let reminder = Reminder(id: note.id, body: body, dueDate: parsed.date, isCompleted: false)
            remindersArray.append(reminder)
        }
    }
    
}
