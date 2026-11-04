import Foundation
import Observation
import Security

enum ModelBackend: String, CaseIterable, Identifiable, Codable {
    case localOllama = "Local Ollama"
    case remoteOpenAICompatible = "Remote OpenAI-Compatible"

    var id: String { rawValue }
}

@MainActor
@Observable
final class ModelSettingsStore {
    var backend: ModelBackend = .localOllama {
        didSet { save() }
    }

    var localEndpoint: String = "http://localhost:11434/api/generate" {
        didSet { save() }
    }

    var localModel: String = "llama3.2" {
        didSet { save() }
    }

    var remoteEndpoint: String = "https://api.openai.com/v1/chat/completions" {
        didSet { save() }
    }

    var remoteModel: String = "gpt-4.1-mini" {
        didSet { save() }
    }

    var apiKey: String = "" {
        didSet { saveAPIKey() }
    }

    var statusMessage: String = "Using local Ollama by default"

    private let fileURL: URL
    private let keychainAccount = "model-api-key"

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Alexi", isDirectory: true)
        try? fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        fileURL = supportDirectory.appendingPathComponent("model-settings.json")
        load()
    }

    var activeModelName: String {
        switch backend {
        case .localOllama: localModel
        case .remoteOpenAICompatible: remoteModel
        }
    }

    var activeEndpoint: URL? {
        URL(string: backend == .localOllama ? localEndpoint : remoteEndpoint)
    }

    var snapshot: ModelSettingsSnapshot {
        ModelSettingsSnapshot(
            backend: backend,
            localEndpoint: localEndpoint,
            localModel: localModel,
            remoteEndpoint: remoteEndpoint,
            remoteModel: remoteModel,
            apiKey: apiKey
        )
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(SavedSettings.self, from: data) else {
            apiKey = loadAPIKey() ?? ""
            return
        }
        backend = saved.backend
        localEndpoint = saved.localEndpoint
        localModel = saved.localModel
        remoteEndpoint = saved.remoteEndpoint
        remoteModel = saved.remoteModel
        apiKey = loadAPIKey() ?? ""
    }

    private func save() {
        let saved = SavedSettings(
            backend: backend,
            localEndpoint: localEndpoint,
            localModel: localModel,
            remoteEndpoint: remoteEndpoint,
            remoteModel: remoteModel
        )
        try? JSONEncoder().encode(saved).write(to: fileURL, options: [.atomic])
    }

    private func saveAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.alexi.local",
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        guard !apiKey.isEmpty else { return }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.alexi.local",
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: Data(apiKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.alexi.local",
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct SavedSettings: Codable {
    let backend: ModelBackend
    let localEndpoint: String
    let localModel: String
    let remoteEndpoint: String
    let remoteModel: String
}

struct ModelSettingsSnapshot {
    let backend: ModelBackend
    let localEndpoint: String
    let localModel: String
    let remoteEndpoint: String
    let remoteModel: String
    let apiKey: String
}
