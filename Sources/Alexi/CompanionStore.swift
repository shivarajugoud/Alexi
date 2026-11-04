import Foundation
import Observation

enum CompanionMode: String, CaseIterable, Identifiable {
    case friend = "Friend"
    case dsaCoach = "DSA Coach"
    case wellbeing = "Wellbeing"

    var id: String { rawValue }

    var guidance: String {
        switch self {
        case .friend:
            "Be warm, curious, and grounded. Remember the user's context, but do not claim consciousness, emotions, or experiences."
        case .dsaCoach:
            "Act as an adaptive data-structures and algorithms coach. Ask a clarifying question, teach with small hints, and do not reveal a full solution unless the user requests it."
        case .wellbeing:
            "Offer empathetic, non-judgmental wellbeing support. Do not diagnose or present yourself as a therapist. Encourage professional or emergency help when the user may be in immediate danger."
        }
    }
}

struct DailyCheckIn: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let mood: Int
    let note: String
    let focus: String

    init(id: UUID = UUID(), date: Date = .now, mood: Int, note: String, focus: String) {
        self.id = id
        self.date = date
        self.mood = mood
        self.note = note
        self.focus = focus
    }
}

struct DSAProfile: Codable, Sendable {
    var currentTopic = "Arrays & Hashing"
    var confidence = 3
    var weeklyGoal = 5
    var solvedThisWeek = 0
}

struct DSAPracticeSession: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let problem: String
    let topic: String
    let notes: String
    let minutes: Int
    let solved: Bool

    init(id: UUID = UUID(), date: Date = .now, problem: String, topic: String, notes: String, minutes: Int, solved: Bool) {
        self.id = id
        self.date = date
        self.problem = problem
        self.topic = topic
        self.notes = notes
        self.minutes = minutes
        self.solved = solved
    }
}

@MainActor
@Observable
final class CompanionStore {
    var selectedMode: CompanionMode = .friend
    private(set) var checkIns: [DailyCheckIn] = []
    private(set) var practiceSessions: [DSAPracticeSession] = []
    var dsaProfile = DSAProfile() {
        didSet { saveProfile() }
    }

    private let checkInsURL: URL
    private let profileURL: URL
    private let practiceURL: URL

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alexi", isDirectory: true)
        try? fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        checkInsURL = supportDirectory.appendingPathComponent("check-ins.encrypted")
        profileURL = supportDirectory.appendingPathComponent("dsa-profile.encrypted")
        practiceURL = supportDirectory.appendingPathComponent("dsa-practice.encrypted")
        checkIns = (try? SecureStore.load([DailyCheckIn].self, from: checkInsURL, keyName: "check-ins")) ?? []
        dsaProfile = (try? SecureStore.load(DSAProfile.self, from: profileURL, keyName: "dsa-profile")) ?? DSAProfile()
        practiceSessions = (try? SecureStore.load([DSAPracticeSession].self, from: practiceURL, keyName: "dsa-practice")) ?? []
    }

    func addCheckIn(mood: Int, note: String, focus: String) {
        checkIns.insert(DailyCheckIn(mood: mood, note: note, focus: focus), at: 0)
        try? SecureStore.save(checkIns, to: checkInsURL, keyName: "check-ins")
    }

    func recordSolvedProblem() {
        dsaProfile.solvedThisWeek += 1
    }

    func recordPractice(problem: String, topic: String, notes: String, minutes: Int, solved: Bool) {
        practiceSessions.insert(DSAPracticeSession(problem: problem, topic: topic, notes: notes, minutes: minutes, solved: solved), at: 0)
        try? SecureStore.save(practiceSessions, to: practiceURL, keyName: "dsa-practice")
        if solved {
            recordSolvedProblem()
        }
    }

    var context: String {
        let latestCheckIn = checkIns.first.map { "Latest check-in: mood \($0.mood)/5; note: \($0.note); focus: \($0.focus)." } ?? "No daily check-in yet."
        let coachingContext = "DSA plan: topic \(dsaProfile.currentTopic), confidence \(dsaProfile.confidence)/5, \(dsaProfile.solvedThisWeek)/\(dsaProfile.weeklyGoal) problems completed this week."
        return "\(latestCheckIn)\n\(coachingContext)"
    }

    private func saveProfile() {
        try? SecureStore.save(dsaProfile, to: profileURL, keyName: "dsa-profile")
    }
}
