import SwiftUI

@main
struct WhereIsThatPlaneApp: App {
    #if DEBUG
    init() { FunFactsSelfCheck.run() }
    #endif

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup { ContentView() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { SkyAlerts.schedule() }
            }
            .backgroundTask(.appRefresh(SkyAlerts.taskID)) {
                await SkyAlerts.check()
                SkyAlerts.schedule()
            }
    }
}
