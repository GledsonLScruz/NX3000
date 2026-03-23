import SwiftUI

enum AppTheme {
    static let primaryPink = Color(red: 0.91, green: 0.33, blue: 0.56)
    static let softPink = Color(red: 0.97, green: 0.86, blue: 0.90)
    static let blush = Color(red: 0.99, green: 0.93, blue: 0.96)
    static let mist = Color(red: 0.97, green: 0.95, blue: 0.99)
}

@main
struct NX3000App: App {
    @StateObject private var appModel = AppModel()

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 60 * 1024 * 1024,
            diskCapacity: 250 * 1024 * 1024,
            diskPath: "NX3000URLCache"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .tint(AppTheme.primaryPink)
        }
    }
}
