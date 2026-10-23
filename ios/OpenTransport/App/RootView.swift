import SwiftUI
import OpenTransportCore

enum AppTab: String, Hashable {
    case map, saved, alerts, plan, settings
}

struct RootView: View {
    @Environment(\.strings) private var s
    // `-initialTab settings` as a launch argument opens that tab (used by CI screenshots).
    @State private var tab = AppTab(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .map

    var body: some View {
        TabView(selection: $tab) {
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
