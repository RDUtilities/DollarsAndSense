import SwiftData
import SwiftUI


@main
struct DollarsAndSenseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Transaction.self)
    }
}
