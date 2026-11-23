import SwiftUI

struct SplashView: View {
    let onDone: () -> Void
    @State private var progress: CGFloat = 0
    @State private var finished = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.10, blue: 0.58),
                    Color(red: 0.45, green: 0.04, blue: 0.40),
                    Color(red: 0.05, green: 0.02, blue: 0.16)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    ForEach(0..<48, id: \.self) { i in
                        let x = pseudo(Float(i) * 1.73) * w
                        let y = pseudo(Float(i) * 2.31) * h * 0.55
                        let twinkle = 0.35 + 0.65 * pseudo(Float(i) * 0.77)
                        Circle()
                            .fill(Color.white.opacity(Double(twinkle) * 0.7))
                            .frame(width: i % 7 == 0 ? 2 : 1, height: i % 7 == 0 ? 2 : 1)
                            .position(x: x, y: y)
                    }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.88, blue: 0.42),
                                    Color(red: 1.0, green: 0.17, blue: 0.55)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: min(w, h) * 0.46, height: min(w, h) * 0.46)
                        .position(x: w / 2, y: h * 0.42)
                        .shadow(color: Color(red: 1.0, green: 0.2, blue: 0.6).opacity(0.8), radius: 34)

                    VStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { row in
                            Rectangle()
                                .fill(Color.cyan.opacity(0.22))
                                .frame(height: 1)
                                .scaleEffect(x: 1.4, y: 1, anchor: .center)
                                .offset(y: CGFloat(row) * CGFloat(6 + row * 3))
                        }
                    }
                    .position(x: w / 2, y: h * 0.62)
                }
            }

            VStack(spacing: 8) {
                Text("4MOVE")
                    .font(.system(size: 76, weight: .black, design: .rounded))
                    .italic()
                    .foregroundColor(.white)
                    .shadow(color: Color(red: 1.0, green: 0.2, blue: 0.6), radius: 18)

                Text(HiddenPrompt.version)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.88, blue: 0.42))

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.cyan)
                    .frame(width: 180)
                    .padding(.top, 24)
            }
            .offset(y: -20)

            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 1)
                .overlay(
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: geo.size.height)
                            .offset(y: 3)
                    }
                )
                .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.linear(duration: 1.65)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                guard !finished else { return }
                finished = true
                onDone()
            }
        }
    }

    private func pseudo(_ x: Float) -> Float {
        let value = sin(x * 12.9898) * 43758.5453
        return value - floor(value)
    }
}
