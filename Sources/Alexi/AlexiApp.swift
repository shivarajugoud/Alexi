import SwiftUI

@main
struct AlexiApp: App {
    @State private var memoryStore = MemoryStore()
    @State private var activityStore = ActivityStore()
    @State private var workspaceStore = WorkspaceStore()
    @State private var modelSettings = ModelSettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(memoryStore)
                .environment(activityStore)
                .environment(workspaceStore)
                .environment(modelSettings)
        }
    }
}
