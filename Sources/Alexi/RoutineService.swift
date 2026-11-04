import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class RoutineService {
    private var center: UNUserNotificationCenter?
    private let morningIdentifier = "com.alexi.routine.morning"
    private let eveningIdentifier = "com.alexi.routine.evening"

    var morningHour = 9
    var eveningHour = 20
    var statusMessage: String?

    func enableDailyRoutines() async {
        do {
            guard let center = notificationCenter() else { return }
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                statusMessage = "Notifications were not enabled. You can change this in System Settings."
                return
            }

            center.removePendingNotificationRequests(withIdentifiers: [morningIdentifier, eveningIdentifier])
            try await center.add(morningRequest())
            try await center.add(eveningRequest())
            statusMessage = "Morning and evening Alexi check-ins are enabled."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func disableDailyRoutines() {
        guard let center = notificationCenter() else { return }
        center.removePendingNotificationRequests(withIdentifiers: [morningIdentifier, eveningIdentifier])
        statusMessage = "Daily check-ins are disabled."
    }

    private func notificationCenter() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            statusMessage = "Daily notifications require the packaged Alexi.app. Run Scripts/launch-app.sh instead of the raw build executable."
            return nil
        }
        if let center { return center }
        let newCenter = UNUserNotificationCenter.current()
        center = newCenter
        return newCenter
    }

    private func morningRequest() -> UNNotificationRequest {
        notificationRequest(identifier: morningIdentifier, title: "Good morning", body: "Ready for a quick check-in, your priorities, and a DSA goal?", hour: morningHour)
    }

    private func eveningRequest() -> UNNotificationRequest {
        notificationRequest(identifier: eveningIdentifier, title: "Evening reflection", body: "Want to reflect on today and set up tomorrow?", hour: eveningHour)
    }

    private func notificationRequest(identifier: String, title: String, body: String, hour: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var components = DateComponents()
        components.hour = hour
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}
