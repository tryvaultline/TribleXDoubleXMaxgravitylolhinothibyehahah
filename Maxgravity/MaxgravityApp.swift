import SwiftUI

@main
struct MaxgravityApp: App {
    @State private var appModel = MGAppModel()

    var body: some Scene {
        WindowGroup {
            MGRootView()
                .environment(appModel)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
