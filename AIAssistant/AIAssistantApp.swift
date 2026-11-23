import SwiftUI

@main
struct AIAssistantApp: App {
    @StateObject private var engine = AssistantEngine()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(engine)

                if showSplash {
                    SplashView {
                        withAnimation(.easeOut(duration: 0.45)) {
                            showSplash = false
                        }
                        engine.warmUp()
                    }
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
