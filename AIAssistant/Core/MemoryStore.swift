import Foundation

struct MemoryFact: Codable {
    var text: String
    var time: String
}

struct TranscriptLine: Codable {
    var time: String
    var role: String
    var content: String
}

final class MemoryStore {
    private let lock = NSLock()
    private var facts: [MemoryFact] = []
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    init() {
        if let data = try? Data(contentsOf: Paths.memoryFile),
           let saved = try? JSONDecoder().decode([MemoryFact].self, from: data) {
            facts = saved
        }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return facts.count
    }

    func addFacts(_ items: [String]) {
        lock.lock()
        defer { lock.unlock() }

        for raw in items {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".;, \r\n"))
            if s.count < 2 { continue }
            if facts.contains(where: { $0.text.caseInsensitiveCompare(s) == .orderedSame }) { continue }
            facts.append(MemoryFact(text: s, time: dateFormatter.string(from: Date())))
        }
        save()
    }

    func clear() {
        lock.lock()
        facts.removeAll()
        save()
        lock.unlock()
    }

    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !facts.isEmpty else { return "" }
        return facts.map { "- " + $0.text }.joined(separator: "\n")
    }

    func appendTranscript(role: String, content: String) {
        let line = TranscriptLine(
            time: ISO8601DateFormatter().string(from: Date()),
            role: role,
            content: content
        )
        guard let data = try? JSONEncoder().encode(line) else { return }

        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: Paths.transcriptFile) {
            handle.seekToEndOfFile()
            handle.write(Data("\n".utf8))
            handle.write(data)
            try? handle.close()
        } else {
            try? Data("".utf8).write(to: Paths.transcriptFile)
            try? data.write(to: Paths.transcriptFile)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(facts) else { return }
        try? data.write(to: Paths.memoryFile, options: .atomic)
    }
}
