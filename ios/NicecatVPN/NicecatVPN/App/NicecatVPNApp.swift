import SwiftUI

@main
struct NicecatVPNApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.boot()
                }
        }
    }
}
