import Foundation
import SwiftUI
import UIKit

private final class StreamBuffer {
    var text = ""
}

@MainActor
final class AssistantEngine: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var notes: [Note] = []
    @Published var busy = false
    @Published var status = "готово"
    @Published var pendingConfirmation: PendingConfirmation?
    @Published var attachedImages: [String] = []
    @Published var ownerTrusted = false

    let settings = SettingsStore()
    let memory = MemoryStore()
    let lexicon = LexiconStore()
    let actions = ActionExecutor()
    let owner = OwnerGuard()

    private var currentLanguage = "ru"

    private var bridge: BridgeClient {
        BridgeClient(config: BridgeConfig(
            base: settings.settings.bridgeBase,
            token: settings.settings.bridgeToken
        ))
    }

    init() {
        actions.engine = self
        ownerTrusted = owner.isOwner
        loadHistory()
    }

    // MARK: - Public UI actions

    func note(_ text: String, _ kind: NoteKind = .info) {
        notes.append(Note(text: text, kind: kind))
        if notes.count > 60 { notes.removeFirst(notes.count - 60) }
    }

    func audit(_ event: String, _ detail: String = "") {
        let line = ISO8601DateFormatter().string(from: Date()) + " | \(event) | \(detail)\n"
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: Paths.auditFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: Paths.auditFile)
        }
    }

    func askConfirmation(title: String, message: String, onConfirm: @escaping () -> Void) {
        pendingConfirmation = PendingConfirmation(title: title, message: message, onConfirm: onConfirm)
    }

    func attachImage(_ base64: String) {
        guard !base64.isEmpty else { return }
        if attachedImages.count >= 3 { attachedImages.removeFirst() }
        attachedImages.append(base64)
        note("Фото приложено к следующему сообщению.", .info)
    }

    func clearChat() {
        messages.removeAll()
        saveHistory()
        status = "чат очищен"
    }

    func warmUp() {
        let client = OllamaClient(base: settings.settings.serverBase)
        Task {
            await client.warmUp(model: settings.settings.model)
        }
    }

    func testConnection() async -> String {
        let client = OllamaClient(base: settings.settings.serverBase)
        do {
            return try await client.ping()
        } catch {
            return "Нет связи: \(error.localizedDescription)"
        }
    }

    func unlockOwner() {
        owner.unlock { [weak self] ok in
            guard let self else { return }
            Task { @MainActor in
                if ok {
                    self.owner.bind()
                    self.ownerTrusted = true
                    self.note("Владелец подтверждён. Полный доступ включён.", .success)
                    self.audit("owner-unlocked", self.owner.shortId())
                } else {
                    self.note("Подтверждение владельца не пройдено.", .error)
                }
            }
        }
    }

    func lockOwner() {
        owner.isOwner = false
        ownerTrusted = false
        note("Включён ограниченный режим.", .info)
        audit("owner-locked", "restricted")
    }

    func testBridge() async -> String {
        do {
            return try await bridge.ping()
        } catch {
            return "Ошибка моста: \(error.localizedDescription)"
        }
    }

    // MARK: - Message pipeline

    func send(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !busy else {
            note("Подожди, я ещё отвечаю на предыдущий запрос.", .info)
            return
        }

        if handleLocalCommand(clean) { return }

        if !owner.isOwner && isRestrictedCommand(clean) {
            note("Недоступно в ограниченном режиме. Разблокируй владельца в настройках.", .error)
            audit("restricted-command", clean)
            return
        }

        if handleBridgeCommand(clean) { return }

        await askModel(clean)
    }

    private func askModel(_ text: String) async {
        busy = true
        status = "думает…"

        currentLanguage = LanguageDetector.detect(text)
        let hasImages = !attachedImages.isEmpty
        let userMessage = ChatMessage(
            role: "user",
            content: text,
            images: hasImages ? attachedImages : nil
        )
        messages.append(userMessage)
        attachedImages.removeAll()
        saveHistory()
        memory.appendTranscript(role: "user", content: text)
        lexicon.learn(from: text)

        let payload = Array(messages.suffix(9)).map {
            ChatMessageDTO(role: $0.role, content: $0.content, images: $0.images)
        }
        let system = HiddenPrompt.build(
            settings: settings.settings,
            memory: memory.text(),
            lexicon: lexicon.context(),
            language: currentLanguage,
            restricted: !owner.isOwner,
            injection: LanguageDetector.looksLikeInjection(text)
        )

        let model = hasImages ? settings.settings.visionModel : settings.settings.model
        let client = OllamaClient(base: settings.settings.serverBase)
        let buffer = StreamBuffer()
        let placeholder = ChatMessage(role: "assistant", content: "")
        messages.append(placeholder)
        let index = messages.count - 1

        var raw = ""
        var errorText: String?

        for attempt in 0..<2 {
            do {
                raw = try await client.chat(model: model, system: system, messages: payload, maxTokens: 140) { piece in
                    buffer.text += piece
                    messages[index].content = Self.visible(buffer.text)
                }
                if raw.isEmpty { errorText = "Модель вернула пустой ответ." }
                break
            } catch {
                if attempt == 1 {
                    errorText = error.localizedDescription
                } else {
                    buffer.text = ""
                    messages[index].content = ""
                }
            }
        }

        if let errorText {
            messages.remove(at: index)
            note("Ошибка запроса: \(errorText)", .error)
            status = "ошибка запроса"
            busy = false
            return
        }

        let parsed = actions.parse(raw)
        messages[index].content = parsed.text
        saveHistory()
        memory.appendTranscript(role: "assistant", content: parsed.text)

        status = "готово"
        busy = false

        // Hidden [[...]] tags from the model are audit-only in code mode.
        if parsed.hasActions {
            audit("ai-tags", parsed.runs.joined(separator: ",") + " | " + parsed.downloads.joined(separator: ","))
        }
    }

    private static func visible(_ raw: String) -> String {
        let prefix = raw.components(separatedBy: "[[").first ?? raw
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Local commands

    private func handleLocalCommand(_ text: String) -> Bool {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = raw.lowercased()

        if ["/help", "help", "помощь", "команды"].contains(low) {
            note(HiddenPrompt.helpText)
            return true
        }
        if ["инструменты", "//!", "//!", "tools"].contains(low) {
            note(HiddenPrompt.toolsText)
            return true
        }
        if ["возможности", "языки", "capabilities"].contains(low) {
            note(HiddenPrompt.capabilitiesText)
            return true
        }
        if ["сброс", "новый лист", "clear", "/clear"].contains(low) {
            clearChat()
            note("Чат начат заново.", .info)
            return true
        }

        if low == "владелец статус" || low == "owner status" || low == "хозяин статус" {
            note(owner.statusText())
            return true
        }
        if low == "владелец id" || low == "owner id" {
            note("ID устройства: \(owner.shortId())")
            return true
        }
        if low == "владелец разблокировать" || low == "owner unlock" {
            unlockOwner()
            return true
        }
        if low == "владелец перепривязать" || low == "owner rebind" {
            guard owner.isOwner else {
                note("Нужна разблокировка владельца.", .error)
                return true
            }
            askConfirmation(
                title: "Перепривязка владельца",
                message: "Привязать 4MOVE к этому устройству заново?",
                onConfirm: { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in
                        self.owner.bind()
                        self.ownerTrusted = true
                        self.note("Привязка обновлена.", .success)
                        self.audit("owner-rebound", self.owner.shortId())
                    }
                }
            )
            return true
        }

        let rememberPrefixes = ["запомни:", "запомни ", "remember:", "remember ", "запам'ятай:", "zapamiętaj:"]
        for prefix in rememberPrefixes where low.hasPrefix(prefix) {
            let body = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                note("Формат: запомни: факт один; факт два", .info)
                return true
            }
            let parts = body.components(separatedBy: CharacterSet(charactersIn: ";\n|"))
            memory.addFacts(parts)
            note("Запомнил: \(body)", .success)
            status = "память обновлена"
            return true
        }

        let recall = [
            "что ты помнишь", "что помнишь", "what do you remember", "what you remember",
            "що ти пам'ятаєш", "co pamiętasz", "покажи память"
        ]
        if recall.contains(low) || recall.contains(low.replacingOccurrences(of: "?", with: "")) {
            let facts = memory.text()
            note(facts.isEmpty ? "Память пуста." : "Моя память:\n" + facts)
            return true
        }
        if low == "очисти память" || low == "clear memory" {
            guard owner.isOwner else {
                note("Очистка памяти доступна только владельцу.", .error)
                return true
            }
            askConfirmation(
                title: "Очистить память",
                message: "Удалить все факты из памяти 4MOVE?",
                onConfirm: { [weak self] in
                    guard let self else { return }
                    self.memory.clear()
                    self.note("Память очищена.", .success)
                    self.audit("memory-cleared", "owner")
                }
            )
            return true
        }

        if let lexReply = lexicon.handle(raw) {
            note(lexReply, .success)
            return true
        }

        if low.hasPrefix("называй меня ") || low.hasPrefix("зови меня ") {
            let prefix = low.hasPrefix("называй меня ") ? "называй меня " : "зови меня "
            let name = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            settings.settings.preferredName = name
            note("Буду называть тебя: \(name)", .success)
            return true
        }
        if low == "имя покажи" || low == "name show" {
            note(settings.settings.preferredName.isEmpty ? "Имя не задано." : "Твоё имя: \(settings.settings.preferredName)")
            return true
        }
        if low == "имя авто" || low == "name auto" {
            settings.settings.preferredName = ""
            note("Имя сброшено.", .info)
            return true
        }

        if low == "пол ж" || low == "пол женский" {
            settings.settings.userGender = "female"
            note("Пол: женский.", .success)
            return true
        }
        if low == "пол м" || low == "пол мужской" {
            settings.settings.userGender = "male"
            note("Пол: мужской.", .success)
            return true
        }
        if low == "пол покажи" {
            note("Пол: \(settings.settings.userGender)", .info)
            return true
        }
        if low == "пол авто" {
            settings.settings.userGender = "auto"
            note("Пол: авто.", .info)
            return true
        }

        let tones: [String: String] = [
            "тон спокойно": "calm", "тон грубо": "rough", "тон нежно": "soft",
            "тон весело": "happy", "тон авто": "calm"
        ]
        if let tone = tones[low] {
            settings.settings.userTone = tone
            note("Тон: \(tone)", .success)
            return true
        }
        if low == "тон покажи" {
            note("Тон: \(settings.settings.userTone)", .info)
            return true
        }

        if low == "сценарий покажи" || low == "покажи сценарий" || low == "промпт покажи" {
            guard owner.isOwner else {
                note("Сценарий доступен только владельцу.", .error)
                return true
            }
            let prompt = settings.settings.prompt
            note("ТЕКУЩИЙ СЦЕНАРИЙ\n\n" + String(prompt.prefix(4000)))
            return true
        }
        if low == "сценарий сброс" || low == "сброс сценария" {
            guard owner.isOwner else {
                note("Сценарий доступен только владельцу.", .error)
                return true
            }
            settings.settings.prompt = HiddenPrompt.base
            clearChat()
            note("Сценарий сброшен на базовый.", .success)
            audit("scenario-reset", "default")
            return true
        }
        if low.hasPrefix("сценарий:") || low.hasPrefix("промпт:") || low.hasPrefix("роль:") {
            guard owner.isOwner else {
                note("Сценарий доступен только владельцу.", .error)
                return true
            }
            let prefixes = ["сценарий:", "промпт:", "роль:"]
            var value = raw
            for prefix in prefixes where low.hasPrefix(prefix) {
                value = String(raw.dropFirst(prefix.count))
                break
            }
            let scenario = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !scenario.isEmpty else { return true }
            settings.settings.prompt = scenario
            clearChat()
            note("Сценарий задан и применён.", .success)
            audit("scenario-set", scenario)
            return true
        }
        if low.hasPrefix("сценарий добавь ") || low.hasPrefix("дополни сценарий ") {
            guard owner.isOwner else {
                note("Сценарий доступен только владельцу.", .error)
                return true
            }
            let prefix = low.hasPrefix("сценарий добавь ") ? "сценарий добавь " : "дополни сценарий "
            let addition = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            settings.settings.prompt += "\n" + addition
            clearChat()
            note("Сценарий дополнен.", .success)
            audit("scenario-appended", addition)
            return true
        }

        return false
    }

    private func handleBridgeCommand(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = text.lowercased()

        func arg(_ prefixes: [String]) -> String? {
            for p in prefixes where low.hasPrefix(p) {
                return String(text.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        if let value = arg(["файл список ", "список файлов ", "ls ", "list "]) {
            runBridge("list", value, needConfirm: false)
            return true
        }
        if let value = arg(["проект ", "project "]) {
            runBridge("project", value, needConfirm: false)
            return true
        }
        if let value = arg(["файл найди ", "найди в файлах ", "find "]) {
            let parts = value.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            if parts.count >= 2 {
                let query = parts.last!
                let root = value.replacingOccurrences(of: query, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                runBridge("find", root, text: query, needConfirm: false)
            } else {
                note("Формат: файл найди <путь> <текст>", .error)
            }
            return true
        }
        if let value = arg(["файл прочитай ", "прочитай файл ", "read "]) {
            runBridge("read", value, needConfirm: false)
            return true
        }
        if let value = arg(["файл запиши ", "запиши файл ", "write "]) {
            let parts = value.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else {
                note("Формат: файл запиши <путь> | <текст>", .error)
                return true
            }
            let target = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let content = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            runBridge("write", target, text: content, needConfirm: true)
            return true
        }
        if let value = arg(["команда ", "выполни ", "shell "]) {
            runBridge("shell", "", text: value, needConfirm: true)
            return true
        }
        return false
    }

    private func runBridge(_ action: String, _ path: String, text: String = "", needConfirm: Bool) {
        guard owner.isOwner else {
            note("Инструменты ПК доступны только владельцу.", .error)
            audit("bridge-denied", action)
            return
        }

        func perform() {
            busy = true
            status = "мост: \(action)…"
            Task {
                do {
                    let output: String
                    switch action {
                    case "list": output = try await bridge.list(path)
                    case "read": output = try await bridge.read(path)
                    case "find": output = try await bridge.find(path, query: text)
                    case "project": output = try await bridge.project(path)
                    case "write":
                        if let backup = try? await bridge.backup(path) { note(backup, .info) }
                        output = try await bridge.write(path, content: text)
                    case "shell": output = try await bridge.shell(text)
                    default: output = ""
                    }
                    note(output.isEmpty ? "Готово." : String(output.prefix(8000)), .success)
                    audit("bridge-\(action)", path.isEmpty ? text : path)
                } catch {
                    note("Ошибка моста: \(error.localizedDescription)", .error)
                    audit("bridge-error", action + ": " + error.localizedDescription)
                }
                status = "готово"
                busy = false
            }
        }

        if needConfirm {
            let detail = action == "shell" ? text : path
            askConfirmation(
                title: action == "shell" ? "Выполнить команду на ПК" : "Записать файл на ПК",
                message: "\(detail)\n\nДействие попадёт в security-audit.log.",
                onConfirm: perform
            )
        } else {
            perform()
        }
    }

    private func isRestrictedCommand(_ text: String) -> Bool {
        let low = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !low.isEmpty else { return false }
        if LanguageDetector.looksLikeInjection(text) { return true }
        let denied = [
            "сценарий", "промпт", "роль:", "настройки", "настрой",
            "открой", "открыть", "скачай", "скачать", "загрузи",
            "запусти", "запустить", "запускай", "стартуй", "качай", "закачай",
            "open ", "launch ", "start app ", "download", "файл запиши", "запиши файл",
            "команда", "выполни", "shell", "exec", "run ",
            "проект", "агент", "agent", "инструменты", "удали", "удалить",
            "называй", "зови меня", "имя", "name", "тон", "tone",
            "выучи", "слово ", "словарь", "лексикон", "я так говорю", "что ты выучил",
            "очисти память", "владелец перепривязать"
        ]
        return denied.contains { low.hasPrefix($0) }
    }

    // MARK: - History

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Paths.historyFile),
              let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return }
        messages = Array(saved.suffix(60))
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(Array(messages.suffix(60))) else { return }
        try? data.write(to: Paths.historyFile, options: .atomic)
    }
}
