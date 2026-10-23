import SwiftUI
import OpenTransportCore

struct SavedTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s

    var body: some View {
        NavigationStack {
            Group {
                let stops = model.favorites.compactMap { model.transit?.stopsById[String($0)] }
                if stops.isEmpty {
                    ContentUnavailableView(s.starToSave, systemImage: "star")
                } else {
                    List(stops) { stop in
                        Button {
                            model.openStop(stop.id)
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
    }
}

struct AlertsTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL
    @State private var service: Network?

    var body: some View {
        let shown = model.incidents?.filter { service == nil || $0.network == service }
        NavigationStack {
            VStack(spacing: 0) {
                // Valenbisi publishes no alerts, so it has no filter.
                ServiceFilter(selected: $service, exclude: [.valenbisi])
                Group {
                    if let shown {
                        if shown.isEmpty {
                            ContentUnavailableView(s.noServiceUpdates, systemImage: "checkmark.circle")
                        } else {
                            List(shown, id: \.self) { incident in
                                // Only notices with a document (Metrobús PDFs) are tappable.
                                if let url = URL(string: incident.url), !incident.url.isEmpty {
                                    Button { openURL(url) } label: { IncidentRow(incident: incident) }
                                        .tint(.primary)
                                } else {
                                    IncidentRow(incident: incident)
                                }
                            }
                            .listStyle(.plain)
                        }
                    } else {
                        ProgressView(s.loading).frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle(s.serviceUpdates)
            .refreshable { await model.refreshIncidents(force: true) }
        }
    }
}

private struct IncidentRow: View {
    let incident: Incident

    @Environment(\.strings) private var s

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ServiceLogo(network: incident.network, size: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(incident.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if !incident.detail.isEmpty {
                    Text(incident.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
                if !incident.date.isEmpty {
                    Text(incident.date).font(.caption).foregroundStyle(.secondary)
                }
                if !incident.lines.isEmpty {
                    // Metro alerts carry bare line numbers; show them as Metro badges.
                    LineBadges(lines: incident.lines
                        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                        .map { incident.network == .metro ? "M\($0)" : $0 })
                }
            }
            Spacer(minLength: 0)
            if !incident.url.isEmpty {
                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                    .accessibilityLabel(s.openNotice)
            }
        }
        .padding(.vertical, 4)
    }
}

/// "All" plus one chip per network (Android's `ServiceFilterRow`).
struct ServiceFilter: View {
    @Binding var selected: Network?
    var exclude: Set<Network> = []

    @Environment(\.strings) private var s

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(s.all, logo: nil, isOn: selected == nil) { selected = nil }
                ForEach(Network.allCases.filter { !exclude.contains($0) }, id: \.self) { network in
                    chip(network.label, logo: network, isOn: selected == network) {
                        selected = selected == network ? nil : network
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, logo: Network?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let logo { ServiceLogo(network: logo, size: 16) }
                Text(title).font(.subheadline)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isOn ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
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
    @AppStorage(MapPreferences.styleKey) private var mapStyle = MapStyle.auto.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        if let logo = BundledAsset.image("OpenTransport_logo.png") {
                            Image(uiImage: logo).resizable().scaledToFit().frame(height: 72)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Picker(s.languageTitle, selection: $languageCode) {
                    ForEach(Language.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker(s.appearance, selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.label(s)).tag($0.rawValue) }
                }
                Picker(s.mapStyle, selection: $mapStyle) {
                    ForEach(MapStyle.allCases) { Text($0.label(s)).tag($0.rawValue) }
                }
                Section(s.aboutSources) {
                    Text(s.aboutUnofficial).font(.footnote).foregroundStyle(.secondary)
                    Text(s.aboutData).font(.footnote).foregroundStyle(.secondary)
                    Text(s.aboutWarranty).font(.footnote).foregroundStyle(.secondary)
                    Text("© 2026 OpenTransport Valencia").font(.footnote)
                }
            }
            .navigationTitle(s.settings)
        }
    }
}
