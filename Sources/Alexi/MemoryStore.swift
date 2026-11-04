import Foundation
import Observation

@Observable
final class MemoryStore {
    private(set) var memories: [Memory] = []
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alexi", isDirectory: true)
        fileURL = supportDirectory.appendingPathComponent("memories.encrypted")

        try? fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        load()
    }

    func add(_ content: String) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        memories.insert(Memory(content: trimmedContent), at: 0)
        save()
    }

    func delete(_ memory: Memory) {
        memories.removeAll { $0.id == memory.id }
        save()
    }

    func update(id: UUID, content: String) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty,
              let index = memories.firstIndex(where: { $0.id == id }) else { return }

        memories[index].content = trimmedContent
        save()
    }

    var context: String {
        memories.map(\.content).joined(separator: "\n")
    }

    private func load() {
        if let savedMemories = try? SecureStore.load([Memory].self, from: fileURL, keyName: "memories") {
            memories = savedMemories
            return
        }

        let legacyURL = fileURL.deletingLastPathComponent().appendingPathComponent("memories.json")
        if let data = try? Data(contentsOf: legacyURL),
           let savedMemories = try? JSONDecoder().decode([Memory].self, from: data) {
            memories = savedMemories
            if save() {
                try? FileManager.default.removeItem(at: legacyURL)
            }
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try SecureStore.save(memories, to: fileURL, keyName: "memories")
            return true
        } catch {
            return false
        }
    }
}
