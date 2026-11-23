import SwiftUI
import UIKit

struct RemoteEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let isDir: Bool
    let line: String
}

struct FilesView: View {
    @EnvironmentObject var engine: AssistantEngine
    @State private var path: String = "W:\\AI-Assistant"
    @State private var pathInput: String = "W:\\AI-Assistant"
    @State private var entries: [RemoteEntry] = []
    @State private var editorPath: String = ""
    @State private var editorText: String = ""
    @State private var editorOpen = false
    @State private var newFilePath: String = ""
    @State private var newFileOpen = false
    @State private var showShare = false

    private var client: BridgeClient {
        BridgeClient(config: BridgeConfig(
            base: engine.settings.settings.bridgeBase,
            token: engine.settings.settings.bridgeToken
        ))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("путь на ПК", text: $pathInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(9)
                    .onSubmit { load() }

                Button(action: load) {
                    Image(systemName: "arrow.clockwise").foregroundColor(Theme.cyan)
                }
                Button {
                    newFileOpen = true
                    newFilePath = path + "\\new-file.txt"
                } label: {
                    Image(systemName: "plus.circle").foregroundColor(Theme.magenta)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)

            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 38)).foregroundColor(Theme.muted)
                    Text("Папка пуста или нет связи с мостом")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.muted)
                    Button("Проверить мост") { Task { await engine.testBridge() } }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.cyan)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    HStack {
                        Image(systemName: entry.isDir ? "folder.fill" : "doc.text.fill")
                            .foregroundColor(entry.isDir ? Theme.magenta : Theme.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Theme.text)
                            Text(entry.line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Theme.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        if !entry.isDir {
                            Button {
                                Task { await openEditor(combine(path, entry.name)) }
                            } label: {
                                Image(systemName: "pencil").foregroundColor(Theme.magenta)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if entry.isDir {
                            path = combine(path, entry.name)
                            pathInput = path
                            load()
                        } else {
                            Task { await openEditor(combine(path, entry.name)) }
                        }
                    }
                    .listRowBackground(Theme.panel)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            HStack(spacing: 8) {
                Button("НАВЕРХ") {
                    let parent = (path as NSString).deletingLastPathComponent
                    guard parent != path else { return }
                    path = parent
                    pathInput = parent
                    load()
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.muted)

                Button("КОРНИ") {
                    Task {
                        do {
                            let roots = try await client.roots()
                            engine.note("Корни моста:\n" + roots.joined(separator: "\n"), .info)
                        } catch {
                            engine.note("Ошибка моста: \(error.localizedDescription)", .error)
                        }
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.cyan)
            }
            .padding(.bottom, 8)
        }
        .onAppear { load() }
        .sheet(isPresented: $editorOpen) {
            NavigationStack {
                TextEditor(text: $editorText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background())
                    .navigationTitle((editorPath as NSString).lastPathComponent)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") { editorOpen = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Сохранить") {
                                let target = editorPath
                                let content = editorText
                                engine.askConfirmation(
                                    title: "Записать файл на ПК",
                                    message: "Перезаписать \(target)? Действие попадёт в аудит.",
                                    onConfirm: {
                                        Task {
                                            do {
                                                if let backup = try? await client.backup(target) {
                                                    engine.note(backup, .info)
                                                }
                                                let result = try await client.write(target, content: content)
                                                engine.note(result, .success)
                                                engine.audit("ios-write", target)
                                                editorOpen = false
                                            } catch {
                                                engine.note("Ошибка записи: \(error.localizedDescription)", .error)
                                            }
                                        }
                                    }
                                )
                            }
                            .foregroundColor(Theme.cyan)
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $newFileOpen) {
            NavigationStack {
                Form {
                    TextField("Полный путь на ПК", text: $newFilePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 12, design: .monospaced))
                }
                .navigationTitle("Новый файл")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { newFileOpen = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Создать") {
                            let target = newFilePath
                            newFileOpen = false
                            engine.askConfirmation(
                                title: "Создать файл на ПК",
                                message: "Создать \(target)?",
                                onConfirm: {
                                    Task {
                                        do {
                                            let result = try await client.write(target, content: "")
                                            engine.note(result, .success)
                                            engine.audit("ios-create", target)
                                            load()
                                        } catch {
                                            engine.note("Ошибка создания: \(error.localizedDescription)", .error)
                                        }
                                    }
                                }
                            )
                        }
                        .foregroundColor(Theme.cyan)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func load() {
        let target = pathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        path = target
        Task {
            do {
                let output = try await client.list(target)
                var result: [RemoteEntry] = []
                for line in output.split(whereSeparator: { $0.isNewline }) {
                    let text = String(line)
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("ПАПКА"), !trimmed.hasPrefix("ФАЙЛ") else { continue }
                    let isDir = trimmed.hasPrefix("[DIR]")
                    let name = isDir ? String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                                     : (trimmed as NSString).deletingPathExtension
                    let display = isDir ? name : (trimmed as NSString).lastPathComponent
                    let cleanDisplay = display.components(separatedBy: "  (").first ?? display
                    result.append(RemoteEntry(name: cleanDisplay, isDir: isDir, line: text))
                }
                entries = result
                if result.isEmpty { engine.note("Папка пуста: \(target)", .info) }
            } catch {
                entries = []
                engine.note("Ошибка моста: \(error.localizedDescription)", .error)
            }
        }
    }

    private func openEditor(_ target: String) async {
        do {
            let output = try await client.read(target)
            let body = output.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
            editorPath = target
            editorText = body.isEmpty ? output : body
            editorOpen = true
            engine.audit("ios-read", target)
        } catch {
            engine.note("Ошибка чтения: \(error.localizedDescription)", .error)
        }
    }

    private func combine(_ base: String, _ name: String) -> String {
        if base.hasSuffix("\\") || base.hasSuffix("/") { return base + name }
        return base + "\\" + name
    }
}
