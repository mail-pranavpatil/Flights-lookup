import SwiftUI

@main
struct WhereIsThatPlaneApp: App {
    #if DEBUG
    init() { FunFactsSelfCheck.run() }
    #endif

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
