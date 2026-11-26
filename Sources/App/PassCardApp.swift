import SwiftUI

@main
struct PassCardApp: App {
    @StateObject private var store = PassStore()

    var body: some Scene {
        WindowGroup {
            PassListView()
                .environmentObject(store)
        }
    }
}
