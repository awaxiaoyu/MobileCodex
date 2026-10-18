import SwiftUI

@main
struct MobileCodexApp: App {
  @StateObject private var bridge = NativeBridgeClient()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(bridge)
    }
  }
}
