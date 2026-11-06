import Foundation

struct ModelReplyContext {
    let memoryContext: String
    let companionContext: String
    let workspaceContext: String
}

protocol ModelClient {
    func reply(
        to prompt: String,
        mode: CompanionMode,
        context: ModelReplyContext
    ) async throws -> String

    func draftPatch(
        instruction: String,
        selectedFilePath: String,
        selectedFileContents: String,
        workspaceContext: String
    ) async throws -> String
}

struct LocalModelClient: ModelClient {
    let endpoint: URL
    let model: String

    func reply(
        to prompt: String,
        mode: CompanionMode,
        context: ModelReplyContext
    ) async throws -> String {
        let request = ModelRequest(
            model: model,
            prompt: prompt,
            mode: mode,
            context: context
        )
        return try await ModelRouter.sendOllama(request, endpoint: endpoint)
    }

    func draftPatch(
        instruction: String,
        selectedFilePath: String,
        selectedFileContents: String,
        workspaceContext: String
    ) async throws -> String {
        let prompt = """
        You are Alexi, helping draft a safe text-file edit.
        Return a concise patch plan with:
        1. summary
        2. exact file target
        3. intended change
        4. risk notes
        Do not claim to apply the change.

        Instruction:
        \(instruction)

        File:
        \(selectedFilePath)

        File preview:
        \(selectedFileContents.prefix(4000))

        Workspace context:
        \(workspaceContext)
        """
        let request = ModelRequest(
            model: model,
            prompt: prompt,
            mode: .friend,
            context: ModelReplyContext(memoryContext: "", companionContext: "", workspaceContext: workspaceContext)
        )
        return try await ModelRouter.sendOllama(request, endpoint: endpoint)
    }
}

struct RemoteModelClient: ModelClient {
    let endpoint: URL
    let model: String
    let apiKey: String

    func reply(
        to prompt: String,
        mode: CompanionMode,
        context: ModelReplyContext
    ) async throws -> String {
        let request = ChatCompletionsRequest(
            model: model,
            messages: [
                .system(content: systemPrompt(for: mode, context: context)),
                .user(content: prompt)
            ]
        )
        return try await ModelRouter.sendChatCompletions(request, endpoint: endpoint, apiKey: apiKey)
    }

    func draftPatch(
        instruction: String,
        selectedFilePath: String,
        selectedFileContents: String,
        workspaceContext: String
    ) async throws -> String {
        let prompt = """
        You are Alexi, helping draft a safe text-file edit.
        Return a concise patch plan with:
        1. summary
        2. exact file target
        3. intended change
        4. risk notes
        Do not claim to apply the change.

        Instruction:
        \(instruction)

        File:
        \(selectedFilePath)

        File preview:
        \(selectedFileContents.prefix(4000))

        Workspace context:
        \(workspaceContext)
        """
        let request = ChatCompletionsRequest(
            model: model,
            messages: [
                .system(content: systemPrompt(for: .friend, context: ModelReplyContext(memoryContext: "", companionContext: "", workspaceContext: workspaceContext))),
                .user(content: prompt)
            ]
        )
        return try await ModelRouter.sendChatCompletions(request, endpoint: endpoint, apiKey: apiKey)
    }
}

enum ModelRouter {
    static func reply(
        to prompt: String,
        mode: CompanionMode,
        context: ModelReplyContext,
        settings: ModelSettingsSnapshot
    ) async throws -> String {
        switch settings.backend {
        case .localOllama:
            return try await localClient(settings: settings).reply(to: prompt, mode: mode, context: context)
        case .remoteOpenAICompatible:
            guard let endpoint = URL(string: settings.remoteEndpoint), !settings.apiKey.isEmpty else {
                throw LocalModelError.unavailable
            }
            return try await RemoteModelClient(endpoint: endpoint, model: settings.remoteModel, apiKey: settings.apiKey)
                .reply(to: prompt, mode: mode, context: context)
        }
    }

    static func draftPatch(
        instruction: String,
        selectedFilePath: String,
        selectedFileContents: String,
        workspaceContext: String,
        settings: ModelSettingsSnapshot
    ) async throws -> String {
        switch settings.backend {
        case .localOllama:
            return try await localClient(settings: settings).draftPatch(
                instruction: instruction,
                selectedFilePath: selectedFilePath,
                selectedFileContents: selectedFileContents,
                workspaceContext: workspaceContext
            )
        case .remoteOpenAICompatible:
            guard let endpoint = URL(string: settings.remoteEndpoint), !settings.apiKey.isEmpty else {
                throw LocalModelError.unavailable
            }
            return try await RemoteModelClient(endpoint: endpoint, model: settings.remoteModel, apiKey: settings.apiKey)
                .draftPatch(
                    instruction: instruction,
                    selectedFilePath: selectedFilePath,
                    selectedFileContents: selectedFileContents,
                    workspaceContext: workspaceContext
                )
        }
    }

    private static func localClient(settings: ModelSettingsSnapshot) throws -> LocalModelClient {
        guard let endpoint = URL(string: settings.localEndpoint) else {
            throw LocalModelError.unavailable
        }
        return LocalModelClient(endpoint: endpoint, model: settings.localModel)
    }

    static func sendOllama(_ request: ModelRequest, endpoint: URL) async throws -> String {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LocalModelError.unavailable
        }
        return try JSONDecoder().decode(OllamaResponse.self, from: data).response
    }

    static func sendChatCompletions(_ request: ChatCompletionsRequest, endpoint: URL, apiKey: String) async throws -> String {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LocalModelError.unavailable
        }
        let payload = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        return payload.choices.first?.message.content ?? ""
    }
}

struct ModelRequest: Encodable {
    let model: String
    let prompt: String
    let stream = false
    let system: String

    init(model: String, prompt: String, mode: CompanionMode, context: ModelReplyContext) {
        self.model = model
        self.prompt = prompt
        self.system = systemPrompt(for: mode, context: context)
    }
}

struct OllamaResponse: Decodable {
    let response: String
}

struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [ChatCompletionMessage]
    let stream = false
}

struct ChatCompletionsResponse: Decodable {
    let choices: [ChatCompletionChoice]
}

struct ChatCompletionChoice: Decodable {
    let message: ChatCompletionMessage
}

struct ChatCompletionMessage: Codable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String

    static func system(content: String) -> ChatCompletionMessage {
        ChatCompletionMessage(role: .system, content: content)
    }

    static func user(content: String) -> ChatCompletionMessage {
        ChatCompletionMessage(role: .user, content: content)
    }
}

fileprivate func systemPrompt(for mode: CompanionMode, context: ModelReplyContext) -> String {
    """
    You are Alexi, a concise, trustworthy personal assistant running locally on the user's Mac.
    Treat personal memory as private context. Never claim you completed an action you did not perform.
    Current mode guidance: \(mode.guidance)
    Personal memory:
    \(context.memoryContext.isEmpty ? "No saved memories." : context.memoryContext)
    Current companion context:
    \(context.companionContext)
    Workspace context:
    \(context.workspaceContext.isEmpty ? "No workspace has been selected." : context.workspaceContext)
    When the user asks for coding help, answer like a local workspace copilot: inspect the available files conceptually, explain the next step, and avoid pretending to edit files unless the app has actually done so.
    """
}

enum LocalModelError: LocalizedError {
    case unavailable

    var errorDescription: String {
        "I can't reach the selected model backend. Check the endpoint, model name, and API key."
    }
}
