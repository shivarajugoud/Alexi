import EventKit
import Foundation
import Observation

struct CalendarItem: Identifiable, Sendable {
    let id: String
    let title: String
    let startDate: Date
}

struct ReminderItem: Identifiable, Sendable {
    let id: String
    let title: String
    let dueDate: Date?
}

@MainActor
@Observable
final class OrganizerService {
    private let eventStore = EKEventStore()

    var todaysEvents: [CalendarItem] = []
    var incompleteReminders: [ReminderItem] = []
    var statusMessage: String?

    func refresh() async {
        do {
            guard try await requestCalendarAccess() else {
                statusMessage = "Calendar access was not granted."
                return
            }

            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: .now)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
            todaysEvents = eventStore.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .map { CalendarItem(id: $0.eventIdentifier, title: $0.title, startDate: $0.startDate) }

            guard try await requestReminderAccess() else {
                statusMessage = "Reminders access was not granted."
                return
            }
            incompleteReminders = try await ReminderFetcher.fetch()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createEvent(title: String, startDate: Date, endDate: Date) async throws {
        guard try await requestCalendarAccess() else {
            throw OrganizerError.accessDenied
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw OrganizerError.noCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        try eventStore.save(event, span: .thisEvent)
        await refresh()
    }

    func createReminder(title: String, dueDate: Date?) async throws {
        guard try await requestReminderAccess() else {
            throw OrganizerError.accessDenied
        }
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw OrganizerError.noReminderList
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        reminder.title = title
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        try eventStore.save(reminder, commit: true)
        await refresh()
    }

    private func requestCalendarAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    private func requestReminderAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

}

private enum ReminderFetcher {
    static func fetch() async throws -> [ReminderItem] {
        let eventStore = EKEventStore()
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map {
                    ReminderItem(id: $0.calendarItemIdentifier, title: $0.title, dueDate: $0.dueDateComponents?.date)
                }
                continuation.resume(returning: items)
            }
        }
    }
}

enum OrganizerError: LocalizedError {
    case accessDenied
    case noCalendar
    case noReminderList

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Alexi does not have permission to make that change."
        case .noCalendar:
            "No default calendar is configured in macOS."
        case .noReminderList:
            "No default reminders list is configured in macOS."
        }
    }
}
