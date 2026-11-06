import Foundation

struct OllamaModel: Decodable, Identifiable, Hashable {
    let name: String

    var id: String { name }
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
}

enum OllamaService {
    static func installedModels(endpoint: String) async throws -> [OllamaModel] {
        guard var components = URLComponents(string: endpoint) else {
            throw OllamaServiceError.invalidEndpoint
        }
        components.path = "/api/tags"
        components.query = nil
        guard let tagsURL = components.url else {
            throw OllamaServiceError.invalidEndpoint
        }

        let (data, response) = try await URLSession.shared.data(from: tagsURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaServiceError.unavailable
        }
        let payload = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return payload.models.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum OllamaServiceError: LocalizedError {
    case invalidEndpoint
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The Ollama endpoint is not a valid URL."
        case .unavailable:
            "Alexi could not reach Ollama. Start Ollama and try again."
        }
    }
}
