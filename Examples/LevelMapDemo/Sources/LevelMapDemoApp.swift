import LevelMap
import LevelMapEditor
import SwiftUI

@main
struct LevelMapDemoApp: App {
    // `-editor` on launch opens the editor tab (handy for UI checks).
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-editor") ? 1 : 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                MapDemo()
                    .tabItem { Label("Map", systemImage: "map") }
                    .tag(0)
                LevelMapEditor(route: MapDemo.Sample.world.route, name: "Tidewater", themes: [
                    NamedTheme("meadow", .meadow),
                    NamedTheme("desert", .desert),
                    NamedTheme("snow", .snow),
                ])
                .tabItem { Label("Editor", systemImage: "slider.horizontal.3") }
                .tag(1)
            }
        }
    }
}
