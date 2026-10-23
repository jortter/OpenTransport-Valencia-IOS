import SwiftUI
import OpenTransportCore

/// Map style and which networks are drawn (Android's `LayersSheet`), stored
/// between launches. Defaults match Android: EMT, Metro and Valenbisi.
enum MapPreferences {
    static let networksKey = "map_networks"
    static let styleKey = "maptype"
    static let defaultNetworks = "Emt,Metro,Valenbisi"

    static func networks(_ stored: String) -> Set<Network> {
        Set(stored.split(separator: ",").compactMap { Network(rawValue: String($0)) })
    }

    static func store(_ networks: Set<Network>) -> String {
        Network.allCases.filter(networks.contains).map(\.rawValue).joined(separator: ",")
    }
}

enum MapStyle: String, CaseIterable, Identifiable {
    case auto = "default", light, dark

    var id: String { rawValue }

    func isDark(system: ColorScheme) -> Bool {
        switch self {
        case .auto: return system == .dark
        case .light: return false
        case .dark: return true
        }
    }

    func label(_ s: Strings) -> String {
        switch self {
        case .auto: return s.auto
        case .light: return s.light
        case .dark: return s.dark
        }
    }
}

struct LayersSheet: View {
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MapPreferences.networksKey) private var networks = MapPreferences.defaultNetworks
    @AppStorage(MapPreferences.styleKey) private var style = MapStyle.auto.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section(s.mapStyle) {
                    Picker(s.mapStyle, selection: $style) {
                        ForEach(MapStyle.allCases) { Text($0.label(s)).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                Section(s.layersTitle) {
                    ForEach(Network.allCases, id: \.self) { network in
                        Toggle(isOn: binding(network)) {
                            HStack(spacing: 12) {
                                ServiceLogo(network: network, size: 24)
                                Text(network.label)
                            }
                        }
                    }
                }
            }
            .navigationTitle(s.mapLayers)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(s.close) { dismiss() }
                }
            }
        }
    }

    private func binding(_ network: Network) -> Binding<Bool> {
        Binding(
            get: { MapPreferences.networks(networks).contains(network) },
            set: { on in
                var set = MapPreferences.networks(networks)
                if on { set.insert(network) } else { set.remove(network) }
                networks = MapPreferences.store(set)
            }
        )
    }
}
