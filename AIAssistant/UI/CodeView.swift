import SwiftUI
import PhotosUI
import UIKit

struct CodeView: View {
    @EnvironmentObject var engine: AssistantEngine
    @State private var input = ""
    @State private var pickerItem: PhotosPickerItem?

    private let quick = [
        ("файл список W:\\AI-Assistant", "список"),
        ("проект W:\\AI-Assistant", "проект"),
        ("файл найди W:\\AI-Assistant обновление", "поиск"),
        ("команда git status", "git")
    ]

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(engine.notes) { note in
                            noteRow(note)
                        }
                        ForEach(engine.messages) { message in
                            messageRow(message).id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: engine.messages.count) { _ in
                    if let last = engine.messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quick, id: \.1) { command, title in
                        Button {
                            input = command
                        } label: {
                            Text(title)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.cyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.cyan.opacity(0.08))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 8) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.magenta)
                }
                .onChange(of: pickerItem) { item in
                    Task {
                        if let item,
                           let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data),
                           let jpeg = image.jpegData(compressionQuality: 0.7) {
                            engine.attachImage(jpeg.base64EncodedString())
                        }
                        pickerItem = nil
                    }
                }

                TextField("Код, файл, команда…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                    .submitLabel(.send)
                    .onSubmit { send() }

                Button(action: send) {
                    Text(engine.busy ? "…" : "▶")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 42, height: 40)
                        .background(engine.busy ? Theme.muted : Theme.cyan)
                        .cornerRadius(12)
                }
                .disabled(engine.busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func send() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        input = ""
        Task { await engine.send(value) }
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        let isUser = message.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .font(.system(size: 14))
                .foregroundColor(isUser ? Color(red: 0.05, green: 0.03, blue: 0.12) : Theme.text)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(isUser ? Theme.cyan.opacity(0.85) : Theme.panel)
                .cornerRadius(14)
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private func noteRow(_ note: Note) -> some View {
        let color: Color = note.kind == .error ? Theme.error : (note.kind == .success ? Theme.success : Theme.cyan)
        return HStack(alignment: .top, spacing: 6) {
            Rectangle().fill(color).frame(width: 2)
            Text(note.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(color.opacity(0.9))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
