import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: AssistantEngine
    @State private var tab: String = "code"
    @State private var settingsOpen = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Group {
                    if tab == "files" {
                        FilesView()
                    } else {
                        CodeView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                tabBar
            }
            .background(Theme.background().ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $settingsOpen) {
                SettingsView().environmentObject(engine)
            }
            .alert(item: $engine.pendingConfirmation) { confirmation in
                Alert(
                    title: Text(confirmation.title),
                    message: Text(confirmation.message),
                    primaryButton: .default(Text("Подтвердить")) {
                        engine.pendingConfirmation = nil
                        confirmation.onConfirm()
                    },
                    secondaryButton: .cancel {
                        engine.pendingConfirmation = nil
                    }
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("4MOVE")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .italic()
                .foregroundColor(Theme.cyan)

            Text(HiddenPrompt.version)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.magenta)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.magenta.opacity(0.12))
                .cornerRadius(5)

            Spacer()

            Circle()
                .fill(engine.busy ? Theme.magenta : Theme.success)
                .frame(width: 8, height: 8)
                .shadow(color: engine.busy ? Theme.magenta : Theme.success, radius: 5)

            Text(engine.status)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.muted)
                .lineLimit(1)

            Button {
                settingsOpen = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(Theme.magenta)
                    .frame(width: 34, height: 34)
                    .background(Theme.magenta.opacity(0.1))
                    .cornerRadius(9)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.panel.opacity(0.7))
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(key: "code", title: "КОД", icon: "chevron.left.forwardslash.chevron.right")
            tabButton(key: "files", title: "ФАЙЛЫ", icon: "folder.fill")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.panel.opacity(0.9))
    }

    private func tabButton(key: String, title: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { tab = key }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundColor(tab == key ? Theme.cyan : Theme.muted)
            .background(tab == key ? Theme.cyan.opacity(0.12) : Color.clear)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
