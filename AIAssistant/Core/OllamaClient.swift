import Foundation

struct OllamaClient {
    enum ClientError: LocalizedError {
        case badStatus(Int)
        case badBase
        case empty

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "Сервер Ollama вернул ошибку \(code)"
            case .badBase: return "Неверный адрес сервера. Пример: http://192.168.1.50:11435"
            case .empty: return "Модель вернула пустой ответ"
            }
        }
    }

    private struct TagsResponse: Decodable {
        let models: [TagItem]?
    }

    private struct TagItem: Decodable {
        let name: String?
    }

    let base: String

    private var root: String {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: root + path) else { throw ClientError.badBase }
        return url
    }

    func chat(
        model: String,
        system: String,
        messages: [ChatMessageDTO],
        maxTokens: Int = 140,
        onChunk: @MainActor (String) -> Void
    ) async throws -> String {
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": system]
        ]
        for m in messages {
            var item: [String: Any] = ["role": m.role, "content": m.content]
            if let images = m.images, !images.isEmpty { item["images"] = images }
            apiMessages.append(item)
        }

        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "keep_alive": "1h",
            "messages": apiMessages,
            "options": [
                "temperature": 0.3,
                "num_predict": maxTokens,
                "num_ctx": 4096
            ]
        ]

        var request = URLRequest(url: try endpoint("/api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.badStatus(0) }
        guard (200..<300).contains(http.statusCode) else { throw ClientError.badStatus(http.statusCode) }

        var full = ""
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(OllamaChatChunk.self, from: data) else { continue }
            if let error = chunk.error, !error.isEmpty {
                throw NSError(domain: "Ollama", code: 2, userInfo: [NSLocalizedDescriptionKey: error])
            }
            if let piece = chunk.message?.content, !piece.isEmpty {
                full += piece
                await onChunk(piece)
            }
            if chunk.done == true { break }
        }
        return full
    }

    func warmUp(model: String) async {
        let payload: [String: Any] = [
            "model": model,
            "prompt": "hi",
            "stream": false,
            "keep_alive": "1h",
            "options": ["num_predict": 1]
        ]
        var request = URLRequest(url: (try? endpoint("/api/generate")) ?? URL(fileURLWithPath: "/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        _ = try? await URLSession.shared.data(for: request)
    }

    func models() async throws -> [String] {
        let (data, response) = try await URLSession.shared.data(from: try endpoint("/api/tags"))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClientError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return (decoded.models ?? []).compactMap { $0.name }.sorted()
    }

    func ping() async throws -> String {
        let names = try await models()
        return names.isEmpty ? "Сервер доступен, но моделей нет" : "Сервер доступен. Модели: " + names.joined(separator: ", ")
    }
}
