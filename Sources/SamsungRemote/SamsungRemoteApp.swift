import SwiftUI

@main
struct SamsungRemoteApp: App {
    @StateObject private var tv = TVClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tv)
                .frame(width: 300)
        }
        .windowResizability(.contentSize)
    }
}
