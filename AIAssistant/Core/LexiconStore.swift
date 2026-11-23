import Foundation

struct LexiconEntry: Codable {
    var word: String
    var meaning: String
    var kind: String
    var count: Int
}

final class LexiconStore {
    private var entries: [LexiconEntry] = []

    private let stopWords: Set<String> = [
        "это", "как", "что", "для", "при", "если", "или", "или", "очень", "вот",
        "уже", "еще", "ещё", "было", "будет", "меня", "тебя", "его", "ее", "её",
        "этот", "эта", "эти", "тот", "та", "те", "быть", "можно", "нужно",
        "сделай", "сделать", "пожалуйста", "пока", "привет", "дякую", "спасибо",
        "i", "the", "and", "you", "for", "that", "this", "with", "how", "what"
    ]

    private let profanity: [String: [String]] = [
        "дурак": ["Сам такой. Давай по делу.", "Без ярлыков — уточни мысль."],
        "тупой": ["Тогда объясни подробнее — так будет понятнее.", "Давай без ярлыков."],
        "хуй": ["Язык крепкий. Давай сформулируем задачу.", "Без мата объясни, что нужно."],
        "бля": ["Без мата объясни, что нужно.", "Давай по делу."]
    ]

    init() {
        if let data = try? Data(contentsOf: Paths.lexiconFile),
           let saved = try? JSONDecoder().decode([LexiconEntry].self, from: data) {
            entries = saved
        }
    }

    func context(prefix: Int = 120) -> String {
        guard !entries.isEmpty else { return "" }
        let words = entries.filter { $0.kind == "word" }.prefix(prefix)
        let phrases = entries.filter { $0.kind == "phrase" }.prefix(30)
        var parts: [String] = []
        if !words.isEmpty {
            parts.append("Слова: " + words.map { "\($0.word) = \($0.meaning)" }.joined(separator: "; "))
        }
        if !phrases.isEmpty {
            parts.append("Фразы: " + phrases.map { $0.meaning }.joined(separator: " | "))
        }
        return parts.joined(separator: "\n")
    }

    var count: Int { entries.count }

    func handle(_ text: String) -> String? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = raw.lowercased()

        if low == "словарь статус" {
            return "Слов в словаре: \(entries.filter { $0.kind == "word" }.count). Фраз: \(entries.filter { $0.kind == "phrase" }.count)."
        }

        if low == "словарь покажи" || low.hasPrefix("словарь покажи ") {
            let filter = low.replacingOccurrences(of: "словарь покажи", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = entries.filter { filter.isEmpty || $0.word.contains(filter) || $0.meaning.contains(filter) }
            if shown.isEmpty { return "Словарь пуст или ничего не найдено." }
            return "Словарь:\n" + shown.prefix(80).map { "\($0.word) = \($0.meaning) (\($0.count))" }.joined(separator: "\n")
        }

        if low == "что ты выучил" {
            return handle("словарь покажи")
        }

        if low.hasPrefix("выучи фразу ") {
            let phrase = String(raw.dropFirst("выучи фразу ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { return "Формат: выучи фразу <текст>" }
            add(phrase, meaning: phrase, kind: "phrase")
            return "Запомнил фразу: \(phrase)"
        }

        if low.hasPrefix("выучи слово ") {
            let body = String(raw.dropFirst("выучи слово ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = body.components(separatedBy: "=")
            guard parts.count >= 2 else { return "Формат: выучи слово <слово> = <значение>" }
            let word = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let meaning = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, !meaning.isEmpty else { return "Формат: выучи слово <слово> = <значение>" }
            add(word, meaning: meaning, kind: "word")
            return "Запомнил: \(word) = \(meaning)"
        }

        let fast = low.components(separatedBy: " значит ")
        if fast.count == 2 {
            let word = fast[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let meaning = fast[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty && !meaning.isEmpty {
                add(word, meaning: meaning, kind: "word")
                return "Запомнил: \(word) = \(meaning)"
            }
        }

        return nil
    }

    func retort(for text: String) -> String? {
        let low = text.lowercased()
        for (key, replies) in profanity {
            if low.contains(key) { return replies.randomElement() }
        }
        return nil
    }

    func learn(from text: String) {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && $0.count <= 24 && !stopWords.contains($0) && !$0.allSatisfy({ $0.isNumber }) }

        for word in cleaned.prefix(24) {
            if let index = entries.firstIndex(where: { $0.word == word }) {
                entries[index].count += 1
            } else {
                entries.append(LexiconEntry(word: word, meaning: word, kind: "word", count: 1))
            }
        }
        if entries.count > 600 {
            entries = Array(entries.suffix(600))
        }
        save()
    }

    private func add(_ word: String, meaning: String, kind: String) {
        if let index = entries.firstIndex(where: { $0.word.lowercased() == word.lowercased() }) {
            entries[index].meaning = meaning
            entries[index].count += 1
        } else {
            entries.append(LexiconEntry(word: word, meaning: meaning, kind: kind, count: 1))
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Paths.lexiconFile, options: .atomic)
    }
}
