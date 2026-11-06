import Foundation
import Observation
import Security

enum ModelBackend: String, CaseIterable, Identifiable, Codable {
    case localOllama = "Local Ollama"
    case remoteOpenAICompatible = "Remote OpenAI-Compatible"

    var id: String { rawValue }
}

enum OrchestrationBackend: String, CaseIterable, Identifiable, Codable {
    case nativeSafeLoop = "Built-in safe loop"
    case langGraphLocal = "LangGraph local sidecar"

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

    var orchestrationBackend: OrchestrationBackend = .nativeSafeLoop {
        didSet { save() }
    }

    var langGraphEndpoint: String = "http://127.0.0.1:8787" {
        didSet { save() }
    }

    var statusMessage: String = "Using local Ollama by default"
    var installedLocalModels: [OllamaModel] = []
    var isDiscoveringLocalModels = false
    var langGraphStatus: String = "Not checked"
    var isCheckingLangGraph = false

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

    var runtimeSummary: String {
        switch backend {
        case .localOllama:
            "Local-only inference • no hosted API charges"
        case .remoteOpenAICompatible:
            "Remote inference • provider charges may apply"
        }
    }

    var requestDestination: String {
        backend == .localOllama ? "Ollama on \(localEndpoint)" : remoteEndpoint
    }

    var orchestrationSummary: String {
        switch orchestrationBackend {
        case .nativeSafeLoop:
            "Built-in safe loop • every plan needs your review"
        case .langGraphLocal:
            "LangGraph local sidecar • plan-only • every change needs your review"
        }
    }

    var patchPlanDestination: String {
        orchestrationBackend == .langGraphLocal
            ? "LangGraph on \(langGraphEndpoint)"
            : requestDestination
    }

    var snapshot: ModelSettingsSnapshot {
        ModelSettingsSnapshot(
            backend: backend,
            localEndpoint: localEndpoint,
            localModel: localModel,
            remoteEndpoint: remoteEndpoint,
            remoteModel: remoteModel,
            apiKey: apiKey,
            orchestrationBackend: orchestrationBackend,
            langGraphEndpoint: langGraphEndpoint
        )
    }

    func discoverLocalModels() async {
        isDiscoveringLocalModels = true
        defer { isDiscoveringLocalModels = false }

        do {
            let models = try await OllamaService.installedModels(endpoint: localEndpoint)
            installedLocalModels = models
            if let firstModel = models.first, !models.contains(where: { $0.name == localModel }) {
                localModel = firstModel.name
            }
            statusMessage = models.isEmpty
                ? "Ollama is running, but no local models are installed."
                : "Found \(models.count) local model\(models.count == 1 ? "" : "s")."
        } catch {
            installedLocalModels = []
            statusMessage = error.localizedDescription
        }
    }

    func checkLangGraph() async {
        isCheckingLangGraph = true
        defer { isCheckingLangGraph = false }

        do {
            langGraphStatus = try await LangGraphClient.health(endpoint: langGraphEndpoint)
        } catch {
            langGraphStatus = error.localizedDescription
        }
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
        orchestrationBackend = saved.orchestrationBackend ?? .nativeSafeLoop
        langGraphEndpoint = saved.langGraphEndpoint ?? "http://127.0.0.1:8787"
        apiKey = loadAPIKey() ?? ""
    }

    private func save() {
        let saved = SavedSettings(
            backend: backend,
            localEndpoint: localEndpoint,
            localModel: localModel,
            remoteEndpoint: remoteEndpoint,
            remoteModel: remoteModel,
            orchestrationBackend: orchestrationBackend,
            langGraphEndpoint: langGraphEndpoint
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
    let orchestrationBackend: OrchestrationBackend?
    let langGraphEndpoint: String?
}

struct ModelSettingsSnapshot {
    let backend: ModelBackend
    let localEndpoint: String
    let localModel: String
    let remoteEndpoint: String
    let remoteModel: String
    let apiKey: String
    let orchestrationBackend: OrchestrationBackend
    let langGraphEndpoint: String
}
