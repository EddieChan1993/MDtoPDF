import SwiftUI

@main
struct MDtoPDFApp: App {
    var body: some Scene {
        WindowGroup("GrapePress") {
            ContentView()
                .frame(width: 721, height: 440)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
