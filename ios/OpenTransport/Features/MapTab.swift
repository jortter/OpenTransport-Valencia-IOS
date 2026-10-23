import SwiftUI
import OpenTransportCore

struct SelectedStop: Identifiable, Hashable {
    let id: Int
}

struct MapTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: SelectedStop?

    var body: some View {
        ZStack {
            if let transit = model.transit {
                TransitMapView(stops: transit.stops, dark: colorScheme == .dark) { id in
                    selected = SelectedStop(id: id)
                }
                .ignoresSafeArea(edges: .top)
            } else if let error = model.loadError {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView(s.loading)
            }
        }
        .sheet(item: $selected) { stop in
            StopSheet(stopId: stop.id)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .task(id: model.transit == nil) {
            // `-demoStop 7` as a launch argument opens that stop (used by CI screenshots).
            let demo = UserDefaults.standard.integer(forKey: "demoStop")
            if model.transit != nil, demo > 0, selected == nil {
                selected = SelectedStop(id: demo)
            }
        }
    }
}
