import Foundation

struct Memory: Codable, Identifiable, Hashable {
    let id: UUID
    var content: String
    let createdAt: Date

    init(id: UUID = UUID(), content: String, createdAt: Date = .now) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}

struct ChatMessage: Identifiable, Hashable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let content: String
}
