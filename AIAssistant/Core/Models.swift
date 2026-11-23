import Foundation
import UIKit

enum Paths {
    static let root: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("4MOVE", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func dir(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var downloads: URL { dir("Downloads") }
    static var generated: URL { dir("generated") }
    static var attachments: URL { dir("attachments") }
    static var settingsFile: URL { root.appendingPathComponent("settings.json") }
    static var historyFile: URL { root.appendingPathComponent("history.json") }
    static var memoryFile: URL { root.appendingPathComponent("memory.json") }
    static var transcriptFile: URL { root.appendingPathComponent("transcript.jsonl") }
    static var lexiconFile: URL { root.appendingPathComponent("lexicon.json") }
    static var auditFile: URL { root.appendingPathComponent("security-audit.log") }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    var role: String
    var content: String
    var images: [String]?

    init(id: UUID = UUID(), role: String, content: String, images: [String]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.images = images
    }
}

struct ChatMessageDTO: Codable {
    var role: String
    var content: String
    var images: [String]?
}

struct OllamaChatChunk: Decodable {
    let message: ChunkMessage?
    let done: Bool?
    let error: String?
}

struct ChunkMessage: Decodable {
    let role: String?
    let content: String?
}

struct OllamaGenerateChunk: Decodable {
    let response: String?
    let done: Bool?
    let error: String?
}

struct AppSettings: Codable {
    var serverBase: String = "http://192.168.1.100:11435"
    var bridgeBase: String = BridgeConfig.defaultBase
    var bridgeToken: String = ""
    var model: String = "qwen2.5:3b"
    var visionModel: String = "qwen2.5vl:3b"
    var prompt: String = HiddenPrompt.base
    var preferredName: String = ""
    var userGender: String = "auto"
    var userTone: String = "calm"
    var ownerMode: Bool = true
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    init() {
        if let data = try? Data(contentsOf: Paths.settingsFile),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
            save()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: Paths.settingsFile, options: .atomic)
    }
}

enum NoteKind {
    case info, success, error
}

struct Note: Identifiable {
    let id = UUID()
    let text: String
    let kind: NoteKind
}

struct PendingConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let onConfirm: () -> Void
}

struct AiActions {
    var text: String
    var runs: [String] = []
    var downloads: [String] = []
    var images: [String] = []

    var hasActions: Bool {
        !runs.isEmpty || !downloads.isEmpty || !images.isEmpty
    }
}
