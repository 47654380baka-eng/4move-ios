import Foundation
import UIKit

@MainActor
final class ActionExecutor {
    weak var engine: AssistantEngine?

    private let openVerbs = [
        "открой", "открыть", "откроешь", "откроется", "открылась", "открыть бы",
        "запусти", "запустить", "запускай", "запуск", "стартуй", "launch", "start "
    ]
    private let downloadVerbs = [
        "скачай", "скачать", "скачивай", "скачивать", "загрузи", "загрузить",
        "качай", "download"
    ]
    private let targetHints = [
        "папка загрузок", "папку загрузок", "загрузки", "downloads",
        "блокнот", "notepad", "калькулятор", "проводник", "explorer",
        "comfyui", "комфи", "assistant", "4move", "microsoft edge", "edge",
        "хром", "chrome", "firefox", "файрфокс", "discord", "дискорд",
        "телеграм", "telegram", "steam", "стим", "qbittorrent", "кьюбитторрент",
        "настройки", "камера", "фото", "файлы", "почта", "карты", "сообщения"
    ]

    func parse(_ raw: String) -> AiActions {
        var runs: [String] = []
        var downloads: [String] = []
        var images: [String] = []

        var text = strip(
            #"\[\[\s*(?:RUN|OPEN|ЗАПУСТИ|ОТКРОЙ)\s*:\s*(.+?)\s*\]\]"#,
            in: raw,
            into: &runs
        )
        text = strip(
            #"\[\[\s*(?:DOWNLOAD|СКАЧАЙ|ЗАГРУЗИ)\s*:\s*(.+?)\s*\]\]"#,
            in: text,
            into: &downloads
        )
        text = strip(
            #"\[\[\s*(?:IMAGE|ФОТО|ЗОБРАЖЕНИЕ|PICTURE)\s*:\s*(.+?)\s*\]\]"#,
            in: text,
            into: &images
        )
        if let regex = try? NSRegularExpression(pattern: #"\[\[[^\]]{0,400}\]\]"#, options: []) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        return AiActions(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            runs: runs,
            downloads: downloads,
            images: images
        )
    }

    private func strip(_ pattern: String, in text: String, into bucket: inout [String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let value = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && bucket.count < 3 { bucket.append(value) }
            mutable.replaceCharacters(in: match.range, with: "")
        }
        return mutable as String
    }

    func detectUserAction(_ text: String) -> (kind: String, arg: String)? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = raw.lowercased()
        guard !raw.isEmpty else { return nil }
        if low.hasPrefix("как ") || low.hasPrefix("что ") || low.hasPrefix("почему ") ||
            low.contains("как открыть") || low.contains("как запустить") || low.contains("как скачать") {
            return nil
        }

        let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s<>"']+"#, options: .caseInsensitive)
        let ns = raw as NSString
        let urlRange = NSRange(location: 0, length: ns.length)
        let urlMatch = urlRegex?.firstMatch(in: raw, options: [], range: urlRange)

        if let verb = firstFound(downloadVerbs, in: low) {
            if let urlMatch {
                let value = ns.substring(with: urlMatch.range)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,)]}"))
                return ("download", value)
            }
            if let pos = low.range(of: verb)?.upperBound {
                let arg = String(raw[pos...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\".,!?"))
                if !arg.isEmpty { return ("download", arg) }
            }
            return nil
        }

        guard firstFound(openVerbs, in: low) != nil else { return nil }
        if let hint = firstFound(targetHints, in: low) {
            return ("open", hint)
        }
        let pathRegex = try? NSRegularExpression(pattern: #"[A-Za-z]:\\[^\\s<>"']+"#, options: [])
        if let pathMatch = pathRegex?.firstMatch(in: raw, options: [], range: urlRange) {
            return ("open", ns.substring(with: pathMatch.range))
        }
        if let verb = firstFound(openVerbs, in: low), let pos = low.range(of: verb)?.upperBound {
            let arg = String(raw[pos...]).trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\".,!?"))
            if !arg.isEmpty { return ("open", arg) }
        }
        return nil
    }

    private func firstFound(_ parts: [String], in text: String) -> String? {
        for part in parts where text.contains(part) { return part }
        return nil
    }

    func imagePrompt(from text: String) -> String? {
        let low = text.lowercased()
        let prefixes = ["сгенерируй фото ", "сгенерируй изображение ", "создай фото ", "generate image "]
        for prefix in prefixes where low.hasPrefix(prefix) {
            let value = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    func execute(_ actions: AiActions) {
        guard let engine else { return }
        guard engine.owner.isOwner else {
            engine.note("Действия ИИ доступны только владельцу.", .error)
            engine.audit("ai-action-denied", "not owner")
            return
        }
        for target in actions.runs {
            engine.note("ИИ открывает: \(target)", .info)
            engine.audit("ai-action-run", target)
            openTarget(target)
        }
        for target in actions.downloads {
            engine.note("ИИ скачивает: \(target)", .info)
            engine.audit("ai-action-download", target)
            download(target)
        }
        for prompt in actions.images {
            engine.note("Медиа отключено в этом режиме. Запрос: \(prompt)", .info)
            engine.audit("ai-action-image-disabled", prompt)
        }
    }

    func handleUserAction(kind: String, arg: String) {
        guard let engine else { return }
        guard engine.owner.isOwner else {
            engine.note("Действия доступны только владельцу устройства.", .error)
            engine.audit("action-denied", "not owner")
            return
        }
        if kind == "download" {
            download(arg)
        } else {
            engine.note("Открываю: \(arg)", .info)
            engine.audit("action-open", arg)
            openTarget(arg)
        }
    }

    private func openTarget(_ target: String) {
        guard let engine else { return }
        let low = target.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " \".,!?"))

        let alias: String?
        switch low {
        case "настройки", "settings", "params": alias = UIApplication.openSettingsURLString
        case "телефон", "phone", "звонки": alias = "tel://"
        case "сообщения", "messages", "sms": alias = "sms://"
        case "почта", "mail", "email": alias = "mailto:"
        case "карты", "maps": alias = "maps://"
        case "app store", "апп стор": alias = "itms-apps://"
        case "telegram", "телеграм": alias = "tg://"
        case "whatsapp", "ватсап": alias = "whatsapp://"
        case "youtube", "ютуб": alias = "youtube://"
        case "сафари", "safari": alias = "https://"
        case "папка загрузок", "папку загрузок", "загрузки", "downloads", "файлы", "files":
            alias = "shareddocuments://"
        default: alias = nil
        }

        var url: URL?
        if let alias { url = URL(string: alias) }
        else if let parsed = URL(string: target), parsed.scheme != nil { url = parsed }

        guard let url else {
            engine.note("На iPhone нельзя запустить «\(target)». Доступны iOS-приложения и ссылки.", .error)
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            Task { @MainActor in
                if !success {
                    engine.note("Не удалось открыть «\(target)». Проверь, установлено ли приложение.", .error)
                }
            }
        }
    }

    private func download(_ target: String) {
        guard let engine else { return }
        guard let url = URL(string: target), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            engine.note("Нужна прямая http/https-ссылка для загрузки.", .error)
            return
        }
        let name = (url.lastPathComponent.isEmpty ? "4move-download" : url.lastPathComponent)
        engine.askConfirmation(
            title: "Подтвердить загрузку",
            message: "Скачать «\(name)» из \(url.host ?? "неизвестного источника") в Файлы → 4MOVE → Downloads?",
            onConfirm: { [weak self] in
                guard let self else { return }
                Task { @MainActor in await self.performDownload(url: url) }
            }
        )
    }

    private func performDownload(url: URL) async {
        guard let engine else { return }
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            var name = response.suggestedFilename
            if name.isEmpty { name = url.lastPathComponent }
            if name.isEmpty { name = "4move-download" }
            let safe = (name as NSString).lastPathComponent
            let destination = uniqueURL(in: Paths.downloads, name: safe)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            engine.note("Скачано: \(destination.lastPathComponent)", .success)
            engine.audit("download-approved", destination.lastPathComponent)
        } catch {
            engine.note("Ошибка загрузки: \(error.localizedDescription)", .error)
            engine.audit("download-failed", error.localizedDescription)
        }
    }

    private func uniqueURL(in directory: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = directory.appendingPathComponent(next)
            index += 1
        }
        return candidate
    }
}
