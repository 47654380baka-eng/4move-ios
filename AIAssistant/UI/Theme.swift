import SwiftUI

enum Theme {
    static let backgroundTop = Color(red: 0.06, green: 0.02, blue: 0.12)
    static let backgroundBottom = Color(red: 0.02, green: 0.01, blue: 0.06)
    static let panel = Color(red: 0.09, green: 0.04, blue: 0.16)
    static let cyan = Color(red: 0.00, green: 0.94, blue: 1.00)
    static let magenta = Color(red: 1.00, green: 0.28, blue: 0.88)
    static let text = Color(red: 0.91, green: 0.87, blue: 1.00)
    static let muted = Color(red: 0.62, green: 0.54, blue: 0.76)
    static let success = Color(red: 0.35, green: 1.00, blue: 0.68)
    static let error = Color(red: 1.00, green: 0.42, blue: 0.42)

    static func background() -> LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}
