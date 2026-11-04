import Foundation
import Observation

struct ActivityEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let category: String
    let action: String
    let destination: String

    init(id: UUID = UUID(), date: Date = .now, category: String, action: String, destination: String) {
        self.id = id
        self.date = date
        self.category = category
        self.action = action
        self.destination = destination
    }
}

@MainActor
@Observable
final class ActivityStore {
    private(set) var entries: [ActivityEntry] = []
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alexi", isDirectory: true)
        try? fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        fileURL = supportDirectory.appendingPathComponent("activity.encrypted")
        entries = (try? SecureStore.load([ActivityEntry].self, from: fileURL, keyName: "activity")) ?? []
    }

    func record(category: String, action: String, destination: String) {
        entries.insert(ActivityEntry(category: category, action: action, destination: destination), at: 0)
        entries = Array(entries.prefix(500))
        try? SecureStore.save(entries, to: fileURL, keyName: "activity")
    }

    func clear() {
        entries = []
        try? SecureStore.save(entries, to: fileURL, keyName: "activity")
    }
}
