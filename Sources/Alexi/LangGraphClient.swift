import Foundation

struct LangGraphPatchPlanRequest: Encodable {
    let instruction: String
    let selectedFilePath: String
    let selectedFileContents: String
    let workspaceContext: String
    let model: String
}

struct LangGraphPatchPlanResponse: Decodable {
    let plan: String
    let events: [String]
    let reviewRequired: Bool

    enum CodingKeys: String, CodingKey {
        case plan
        case events
        case reviewRequired = "review_required"
    }
}

enum LangGraphClientError: LocalizedError {
    case invalidEndpoint
    case unavailable
    case remoteModelsUnsupported

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The LangGraph sidecar endpoint is invalid. Use a localhost URL."
        case .unavailable:
            "I can't reach the LangGraph sidecar. Run Scripts/run-langgraph-sidecar.sh, then try again."
        case .remoteModelsUnsupported:
            "The local LangGraph sidecar only works with Local Ollama. Select Local Ollama or use the built-in safe loop."
        }
    }
}

enum LangGraphClient {
    static func health(endpoint: String) async throws -> String {
        let url = try url(for: endpoint, path: "/health")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let payload = try? JSONDecoder().decode(LangGraphHealthResponse.self, from: data) else {
            throw LangGraphClientError.unavailable
        }
        return payload.status == "ok" ? "Ready: local LangGraph sidecar is reachable." : payload.status
    }

    static func draftPatch(
        endpoint: String,
        instruction: String,
        selectedFilePath: String,
        selectedFileContents: String,
        workspaceContext: String,
        model: String
    ) async throws -> String {
        let url = try url(for: endpoint, path: "/plan")
        let request = LangGraphPatchPlanRequest(
            instruction: instruction,
            selectedFilePath: selectedFilePath,
            selectedFileContents: String(selectedFileContents.prefix(4_000)),
            workspaceContext: String(workspaceContext.prefix(4_000)),
            model: model
        )
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let payload = try? JSONDecoder().decode(LangGraphPatchPlanResponse.self, from: data),
              payload.reviewRequired else {
            throw LangGraphClientError.unavailable
        }
        return payload.plan
    }

    private static func url(for endpoint: String, path: String) throws -> URL {
        guard var components = URLComponents(string: endpoint),
              let host = components.host?.lowercased(),
              ["localhost", "127.0.0.1", "::1"].contains(host) else {
            throw LangGraphClientError.invalidEndpoint
        }
        components.path = path
        components.query = nil
        guard let url = components.url else { throw LangGraphClientError.invalidEndpoint }
        return url
    }
}

private struct LangGraphHealthResponse: Decodable {
    let status: String
}
