import SwiftUI
import OpenTransportCore

struct SavedTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @State private var selected: SelectedStop?

    var body: some View {
        NavigationStack {
            Group {
                let stops = model.favorites.compactMap { model.transit?.stopsById[String($0)] }
                if stops.isEmpty {
                    ContentUnavailableView(s.starToSave, systemImage: "star")
                } else {
                    List(stops) { stop in
                        Button {
                            selected = SelectedStop(id: stop.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(stop.cleanName).foregroundStyle(.primary)
                                LineBadges(lines: stop.lines)
                            }
                        }
                    }
                }
            }
            .navigationTitle(s.saved)
        }
        .sheet(item: $selected) { stop in
            StopSheet(stopId: stop.id).presentationDetents([.medium, .large])
        }
    }
}

struct AlertsTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @State private var incidents: [Incident]?

    var body: some View {
        NavigationStack {
            Group {
                if let incidents {
                    if incidents.isEmpty {
                        ContentUnavailableView(s.noServiceUpdates, systemImage: "checkmark.circle")
                    } else {
                        List(incidents, id: \.self) { incident in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(incident.title)
                                    .font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !incident.date.isEmpty {
                                    Text(incident.date).font(.caption).foregroundStyle(.secondary)
                                }
                                if !incident.lines.isEmpty {
                                    LineBadges(lines: incident.lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    ProgressView(s.loading)
                }
            }
            .navigationTitle(s.serviceUpdates)
            .refreshable { incidents = await model.client?.incidents(force: true) }
        }
        .task(id: model.client == nil) {
            guard let client = model.client else { return }
            incidents = await client.incidents()
        }
    }
}

struct PlanTab: View {
    @Environment(\.strings) private var s

    var body: some View {
        NavigationStack {
            ContentUnavailableView(s.planTitle, systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                   description: Text(s.comingSoon))
                .navigationTitle(s.plan)
        }
    }
}

struct SettingsTab: View {
    @Environment(\.strings) private var s
    @AppStorage("language") private var languageCode = AppModel.defaultLanguage.rawValue
    @AppStorage("theme") private var theme = AppTheme.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Picker(s.languageTitle, selection: $languageCode) {
                    ForEach(Language.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker(s.appearance, selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.label(s)).tag($0.rawValue) }
                }
                Section(s.aboutSources) {
                    Text("EMT València · Metrovalencia (FGV) · Valenbisi · Metrobús · Renfe Rodalies")
                    Text("© OpenStreetMap · CARTO")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(s.settings)
        }
    }
}
