import Foundation

struct ChatRequestMessage: Codable {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatRequestMessage]
    let temperature: Double
}

struct ChatCompletionChoice: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let index: Int
    let message: Message
}

struct ChatCompletionResponse: Codable {
    let choices: [ChatCompletionChoice]
}

enum OpenAIChatError: LocalizedError {
    case missingAPIKey
    case invalidResponse(statusCode: Int, message: String?)
    case emptyReply
    case apiError(message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not set."
        case .invalidResponse(let status, let message):
            if let message, !message.isEmpty {
                return "Could not parse OpenAI response. (HTTP \(status)) \(message)"
            }
            return "Could not parse OpenAI response. (HTTP \(status))"
        case .apiError(let message):
            return "OpenAI error: \(message)"
        case .emptyReply:
            return "어시스턴트의 응답이 비어 있어요."
        }
    }
}

private struct OpenAIErrorResponse: Codable {
    struct ErrorBody: Codable {
        let message: String
        let type: String?
        let code: String?
        let param: String?
    }

    let error: ErrorBody
}

struct OpenAIChatService {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(messages: [ChatRequestMessage], apiKey: String, model: String = "gpt-5-nano") async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIChatError.missingAPIKey
        }

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: messages,
            temperature: 1.0
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIChatError.invalidResponse(statusCode: -1, message: "HTTP 응답이 아닙니다.")
        }

        guard (200..<300).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIChatError.apiError(message: apiError.error.message)
            }
            let bodyPreview = String(data: data, encoding: .utf8)
            throw OpenAIChatError.invalidResponse(statusCode: http.statusCode, message: bodyPreview)
        }

        let decoder = JSONDecoder()
        let completion = try decoder.decode(ChatCompletionResponse.self, from: data)
        guard let message = completion.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty else {
            throw OpenAIChatError.emptyReply
        }

        return message
    }
}
