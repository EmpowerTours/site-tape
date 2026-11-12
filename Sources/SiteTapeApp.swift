import SwiftUI

@main
struct SiteTapeApp: App {
    @StateObject private var store = SurveyStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(.dark)
        }
    }
}
