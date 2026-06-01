//
//  Calendar.swift
//  morethantasks
//
//  Created by Toprak Birben on 06/05/2025.
//
import SwiftUI
import Foundation

struct CalendarPage: View {
    @Binding var selectedTab: UIComponents.Tab
    @StateObject private var db = DatabaseManager.shared
    @StateObject private var em = EventManager.shared
    
    var body: some View {
        VStack {
            HStack {
                CalendarView(events: em.eventList)
            }
            Spacer()
            addEventButton()
        }
        .onAppear {
            em.createEvents(notes: db.notesArray)
            em.eventList = EventManager.shared.getEvents()
        }
    }
}

// MARK: - CalendarView

struct CalendarView: View {
    @State private var selectedDate: Date = Date()
    @State private var swipeDirection: Edge = .trailing
    let events: [Event]
    
    private var groupedEvents: [Date: [Event]] {
        Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startDate) }
    }
    
    var body: some View {
        NavigationStack
        {
            VStack {
                MonthHeaderView(selectedDate: $selectedDate, swipeDirection: $swipeDirection)
                WeekdayHeaderView()
                
                DaysGridView(selectedDate: $selectedDate, events: groupedEvents)
                    .padding(.bottom, 10)
                
                Divider().padding(.vertical, 4)
                
                EventListView(selectedDate: selectedDate, events: groupedEvents)
            }
                .id(monthIdentifier(for: selectedDate))
                .transition(.move(edge: swipeDirection).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.5), value: monthIdentifier(for: selectedDate))
        }
    }
    
    private func monthIdentifier(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(comps.year!)-\(comps.month!)"
    }
}

// MARK: - Subviews

struct MonthHeaderView: View {
    @Binding var selectedDate: Date
    @Binding var swipeDirection: Edge
    
    var body: some View {
        Text(Helper.shared.monthYearString(for: selectedDate))
            .font(.system(size: 24, weight: .heavy))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.width < 0 {
                            if let newDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) {
                                selectedDate = newDate
                                swipeDirection = .trailing
                            }
                        } else if value.translation.width > 0 {
                            if let newDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) {
                                selectedDate = newDate
                                swipeDirection = .leading
                            }
                        }
                    }
            )
    }
}



struct WeekdayHeaderView: View {
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
    
    var body: some View {
        LazyVGrid(columns: columns) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }
}

struct DaysGridView: View {
    @Binding var selectedDate: Date
    let events: [Date: [Event]]

    
    var body: some View {
        let days = Helper.shared.generateDays(for: selectedDate)
        
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
            ForEach(days, id: \.self) { date in
                if let date = date {
                    VStack(spacing: 4) {
                        ZStack {
                            if Helper.shared.isSameDay(date, selectedDate) {
                                Circle()
                                    .fill(Color("primary-blue"))
                                    .frame(width: 32, height: 32)
                            } else if Helper.shared.isSameDay(date, Date()) {
                                Circle()
                                    .stroke(Color.green, lineWidth: 2)
                                    .frame(width: 32, height: 32)
                            }
                            
                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(foregroundColor(for: date))
                        }
                        .frame(height: 32)
                        .onTapGesture {
                            selectedDate = date
                        }
                        
                        if let dayEvents = events[Calendar.current.startOfDay(for: date)], !dayEvents.isEmpty {
                            Circle()
                                .fill(.primary)
                                .frame(width: 6, height: 6)
                        } else {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }
    //this function modifies the circle around the numbers
    func backgroundColor(for date: Date) -> Color {
        if Helper.shared.isSameDay(date, selectedDate) {
            return Color("primary-blue")
        } else if Helper.shared.isSameDay(date, Date()) {
            return Color.clear
        }
        return .clear
        
    }
    
    //this function modifies the numbers' color
    private func foregroundColor(for date: Date) -> Color {
        if Helper.shared.isSameDay(date, selectedDate) {
            return Color("primary-white")
        } else if Helper.shared.isSameDay(date, Date()) {
            return Color.green
        }
        return .primary
    }
}

struct EventListView: View {
    let selectedDate: Date
    let events: [Date: [Event]]

    
    var body: some View {
        ScrollView {
            if let todaysEvents = events[Calendar.current.startOfDay(for: selectedDate)] {
                VStack(spacing: 12) {
                    ForEach(todaysEvents) { event in
                        
                        NavigationLink(destination: EventDetailView(event: event)) {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hex: event.colorHex ?? "#89CFF0"), lineWidth: 3)
                                .frame(height: 60)
                                .overlay(
                                    VStack(alignment: .leading) {
                                        Text(event.title)
                                            .font(.headline)
                                            .foregroundColor(.black)
                                            
                                        Text(event.allDay ? "All day" : "Time TBD")
                                            .font(.caption)
                                            .foregroundColor(.black.opacity(0.8))
                                            
                                    }
                                    .padding(.leading, 20),
                                    alignment: .leading
                                    
                                )
                        }
                        
                    }
                }
                .padding(.horizontal)
            } else {
                Text("No events today")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.gray)
                    .padding()
            }
        }
    }
}

struct EventDetailView : View {
    let event: Event
    var body: some View {
        VStack(alignment: .leading)
        {
            Text("Details")
                .font(.title)
                .padding(.leading, 32)
            Divider()
                .padding(.leading, 24)
            Text(event.title)
                .font(.title2)
                .padding(.leading, 32)
            Spacer()
        }
        VStack {
            
        }
    }
}

struct addEventButton: View {
    @State private var presentNextView = false
    @State private var viewStack: ViewStack?
    
    @State private var showAddEvent = false
    var onNoteAdded: (() -> Void)?

    var body: some View {
        VStack {
            Button {
                showAddEvent.toggle()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))
            }
            .fullScreenCover(isPresented: $showAddEvent) {
                addEvent()
            }
        }
    }
}

struct addEvent: View {
    var body: some View {
        Text("Hello")
    }
}



// MARK: - Preview

struct Calendar_Previews: PreviewProvider {
    static var previews: some View {
        CalendarPage(selectedTab: .constant(.calendar))
    }
}

