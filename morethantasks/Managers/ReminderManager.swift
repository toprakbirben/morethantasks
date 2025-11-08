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
    private let pattern = #"\\@(\d{2}-\d{2}-\d{4})"#
    private var cancellables = Set<AnyCancellable>()

    @Published var remindersArray : [Reminder] = []
    private var db = DatabaseManager.shared
    
    func createReminders(noteArray: [Notes]) {
        for note in noteArray {
            if remindersArray.contains(where: { $0.id == note.id }) {continue}
            guard let date = Helper.shared.extractDate(from: note.body) else {
                continue
            }
            let body = Helper.shared.extractTitle(from: note.body)

            
            let reminder = Reminder(id: note.id, body: body, dueDate: date, isCompleted: false)
            remindersArray.append(reminder)
        }
    }
    
}
