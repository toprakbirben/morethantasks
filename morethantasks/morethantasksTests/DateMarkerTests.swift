//  DateMarkerTests.swift
import Testing
import Foundation
@testable import morethantasks

struct DateMarkerTests {
    @Test func dateOnlyMarkerIsAllDay() {
        let result = Helper.shared.parseDateMarker(from: "Pay rent /date 25-12-2026")
        #expect(result != nil)
        #expect(result?.hasTime == false)

        var components = DateComponents()
        components.day = 25
        components.month = 12
        components.year = 2026
        #expect(Calendar.current.isDate(result!.date, inSameDayAs: Calendar.current.date(from: components)!))
    }

    @Test func dateWithTimeMarkerHasTime() {
        let result = Helper.shared.parseDateMarker(from: "Dentist /date 25-12-2026 14:30")
        #expect(result != nil)
        #expect(result?.hasTime == true)

        let hour = Calendar.current.component(.hour, from: result!.date)
        let minute = Calendar.current.component(.minute, from: result!.date)
        #expect(hour == 14)
        #expect(minute == 30)
    }

    @Test func noMarkerReturnsNil() {
        #expect(Helper.shared.parseDateMarker(from: "Just a normal note") == nil)
    }

    @Test func malformedMarkerReturnsNil() {
        #expect(Helper.shared.parseDateMarker(from: "/date 2025-13-99") == nil)
    }

    @Test func extractTitleStripsMarker() {
        let title = Helper.shared.extractTitle(from: "Buy milk /date 25-12-2026")
        #expect(!title.contains("date"))
    }

    @MainActor
    @Test func eventFromNoteWithTimeIsNotAllDay() {
        let note = Notes(
            id: UUID(),
            title: "Meeting",
            body: "Team sync /date 25-12-2026 09:00",
            parentId: nil,
            children: [],
            lastUpdated: Date(),
            userID: 0,
            colorHex: "#007BFF",
            tag: ""
        )
        let event = EventManager.shared.parseEvent(note: note)
        #expect(event != nil)
        #expect(event?.allDay == false)
    }

    @MainActor
    @Test func reminderFromNoteWithMarker() {
        let note = Notes(
            id: UUID(),
            title: "Errand",
            body: "Pick up package /date 25-12-2026",
            parentId: nil,
            children: [],
            lastUpdated: Date(),
            userID: 0,
            colorHex: "#007BFF",
            tag: ""
        )
        ReminderManager.shared.remindersArray.removeAll { $0.id == note.id }
        ReminderManager.shared.createReminders(noteArray: [note])
        #expect(ReminderManager.shared.remindersArray.contains { $0.id == note.id })
    }
}
