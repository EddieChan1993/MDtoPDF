import SwiftUI

@main
struct MDtoPDFApp: App {
    var body: some Scene {
        WindowGroup("GrapePress") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
