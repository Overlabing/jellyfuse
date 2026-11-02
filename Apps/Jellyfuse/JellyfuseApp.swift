import SwiftUI

@main
struct JellyfuseApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup { RootView(model: model) }
    }
}
