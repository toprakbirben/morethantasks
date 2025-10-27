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
}

@MainActor
class ReminderManager: ObservableObject {
    static let shared = ReminderManager()
    private let pattern = #"\\@(\d{2}-\d{2}-\d{4})"#
    private var cancellables = Set<AnyCancellable>()

    @Published var remindersArray : [Reminder] = []
    private let db = DatabaseManager.shared
    
    init() {
        db.$notesArray
            .sink { [weak self] notes in
                guard let self = self else { return }
                self.createReminders(noteArray: notes)
            }
            .store(in: &cancellables)
        createReminders(noteArray: db.notesArray)
    }
    
    func createReminders(noteArray: [Notes]) {
        for note in noteArray {
            if remindersArray.contains(where: { $0.id == note.id }) {continue}
            guard let date = Helper.shared.extractDate(from: note.body) else {
                continue
            }
            let body = Helper.shared.extractTitle(from: note.body)

            
            let reminder = Reminder(id: note.id, body: body, dueDate: date)
            remindersArray.append(reminder)
        }
    }
    
}
