import Foundation

struct BridgeResponse: Decodable {
    let ok: Bool
    let output: String?
    let error: String?
}

enum BridgeError: LocalizedError {
    case badBase
    case emptyToken
    case denied(String)
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badBase: return "Неверный адрес моста. Пример: http://192.168.1.50:11436"
        case .emptyToken: return "Укажи токен моста в настройках"
        case .denied(let text): return text
        case .badStatus(let code): return "Мост вернул ошибку \(code)"
        }
    }
}

struct BridgeConfig {
    var base: String
    var token: String

    static let defaultBase = "http://192.168.1.50:11436"
}

final class BridgeClient {
    let config: BridgeConfig

    init(config: BridgeConfig) {
        self.config = config
    }

    private var root: String {
        var s = config.base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func call(action: String, path: String = "", text: String = "", confirmed: Bool = false) async throws -> String {
        guard !root.isEmpty, let _ = URL(string: root) else { throw BridgeError.badBase }
        let token = config.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw BridgeError.emptyToken }

        let payload: [String: Any] = [
            "token": token,
            "action": action,
            "path": path,
            "text": text,
            "confirmed": confirmed
        ]

        guard let url = URL(string: root + "/") else { throw BridgeError.badBase }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let decoded = try? JSONDecoder().decode(BridgeResponse.self, from: data)
            throw BridgeError.denied(decoded?.error ?? "Мост вернул \(http.statusCode)")
        }

        let decoded: BridgeResponse
        do {
            decoded = try JSONDecoder().decode(BridgeResponse.self, from: data)
        } catch {
            throw BridgeError.denied("Мост вернул некорректный ответ")
        }
        guard decoded.ok else { throw BridgeError.denied(decoded.error ?? "Ошибка моста") }
        return decoded.output ?? ""
    }

    func ping() async throws -> String {
        try await call(action: "ping")
    }

    func roots() async throws -> [String] {
        let text = try await call(action: "roots")
        return text.split(whereSeparator: { $0.isNewline }).map(String.init).filter { !$0.isEmpty }
    }

    func list(_ path: String) async throws -> String {
        try await call(action: "list", path: path)
    }

    func read(_ path: String) async throws -> String {
        try await call(action: "read", path: path)
    }

    func find(_ path: String, query: String) async throws -> String {
        try await call(action: "find", path: path, text: query)
    }

    func project(_ path: String) async throws -> String {
        try await call(action: "project", path: path)
    }

    func backup(_ path: String) async throws -> String {
        try await call(action: "backup", path: path)
    }

    func write(_ path: String, content: String) async throws -> String {
        try await call(action: "write", path: path, text: content, confirmed: true)
    }

    func shell(_ command: String) async throws -> String {
        try await call(action: "shell", text: command, confirmed: true)
    }
}
