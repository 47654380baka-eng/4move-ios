import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var engine: AssistantEngine
    @Environment(\.dismiss) private var dismiss

    @State private var server = ""
    @State private var bridge = ""
    @State private var token = ""
    @State private var model = ""
    @State private var diagnostics = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Локальная модель") {
                    TextField("Ollama http://192.168.1.50:11435", text: $server)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Модель", text: $model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Проверить Ollama") {
                        save()
                        Task { diagnostics = await engine.testConnection() }
                    }
                }

                Section("Мост файлов ПК") {
                    TextField("http://192.168.1.50:11436", text: $bridge)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Токен из bridge-token.txt", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Проверить мост") {
                        save()
                        Task { diagnostics = await engine.testBridge() }
                    }
                    Text("Токен берётся из W:\\AI-Assistant\\AppData\\bridge-token.txt на ПК. Порт 11436 должен быть открыт в файрволе.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.muted)
                }

                if !diagnostics.isEmpty {
                    Section("Диагностика") {
                        Text(diagnostics)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(diagnostics.hasPrefix("Нет связи") || diagnostics.hasPrefix("Ошибка") ? Theme.error : Theme.success)
                            .textSelection(.enabled)
                    }
                }

                Section("Владелец") {
                    Text(engine.owner.statusText())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.muted)
                    if engine.owner.isOwner {
                        Button("Ограничить доступ") { engine.lockOwner() }
                            .foregroundColor(Theme.error)
                    } else {
                        Button("Подтвердить владельца (Face ID)") { engine.unlockOwner() }
                            .foregroundColor(Theme.cyan)
                    }
                    Text("Запись файлов, команды и смена настроек требуют подтверждения владельца.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.muted)
                }

                Section("О приложении") {
                    HStack { Text("Версия"); Spacer(); Text(HiddenPrompt.version).foregroundColor(Theme.muted) }
                    Text("Только код и файлы. Модель и мост работают на локальном ПК по Wi‑Fi.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.muted)
                }
            }
            .navigationTitle("4MOVE · Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save(); dismiss() }
                }
            }
        }
        .onAppear {
            let s = engine.settings.settings
            server = s.serverBase
            bridge = s.bridgeBase
            token = s.bridgeToken
            model = s.model
        }
    }

    private func save() {
        var s = engine.settings.settings
        s.serverBase = server
        s.bridgeBase = bridge
        s.bridgeToken = token
        s.model = model
        engine.settings.settings = s
    }
}
