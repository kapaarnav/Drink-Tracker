import SwiftUI

@main struct DrinkTrackerApp: App {
    @State private var services = AppServices.shared
    var body: some Scene {
        WindowGroup { RootView(services: services) }
    }
}
