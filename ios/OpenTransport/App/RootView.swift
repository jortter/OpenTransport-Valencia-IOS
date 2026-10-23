import SwiftUI
import OpenTransportCore

enum AppTab: String, Hashable {
    case map, saved, alerts, plan, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            MapTab()
                .tabItem { Label(s.map, systemImage: "map") }
                .tag(AppTab.map)
            SavedTab()
                .tabItem { Label(s.saved, systemImage: "star") }
                .tag(AppTab.saved)
            AlertsTab()
                .tabItem { Label(s.alerts, systemImage: "exclamationmark.triangle") }
                .tag(AppTab.alerts)
            PlanTab()
                .tabItem { Label(s.plan, systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(AppTab.plan)
            SettingsTab()
                .tabItem { Label(s.settings, systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
