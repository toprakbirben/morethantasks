//
//  ReminderManager.swift
//  morethantasks
//
//  Created by Toprak Birben on 23/09/2025.
//
import Foundation
import Combine
import NaturalLanguage


struct Reminder: Identifiable {
    let id: UUID
    var body: String
    var dueDate: Date
    var isCompleted: Bool = false
}

class ReminderManager {
    static let shared = ReminderManager()
    private let pattern = #"\\@(\d{2}-\d{2}-\d{4})"#
    private var reminders : [Reminder] = []
    
    func createReminders(noteArray: [Notes]) {
        for note in noteArray {
            if reminders.contains(where: { $0.id == note.id }) {continue}
            guard let date = Helper.shared.extractDate(from: note.body) else {
                continue
            }
            let body = Helper.shared.extractTitle(from: note.body)

            
            let reminder = Reminder(id: note.id, body: body, dueDate: date)
            reminders.append(reminder)
        }
    }
    
    func getReminders() -> [Reminder] {
        return reminders
    }
    
}
