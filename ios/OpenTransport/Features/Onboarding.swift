import SwiftUI
import OpenTransportCore

/// First-launch onboarding (port of Onboarding.kt): one page per topic, then
/// the map layers, map style, language and theme.
struct Onboarding: View {
    var onDone: () -> Void

    @Environment(\.strings) private var s
    @AppStorage("language") private var languageCode = AppModel.defaultLanguage.rawValue
    @AppStorage("theme") private var theme = AppTheme.system.rawValue
    @AppStorage(MapPreferences.styleKey) private var mapStyle = MapStyle.auto.rawValue
    @AppStorage(MapPreferences.networksKey) private var networks = MapPreferences.defaultNetworks
    @State private var page = 0

    private let pages = 6

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                features(s.onboardFeatures, [("bus.fill", s.featureBus), ("tram.fill", s.featureMetro)]).tag(1)
                features(s.onboardMore, [("train.side.front.car", s.featureRodalies), ("bicycle", s.featureBikes)]).tag(2)
                features(s.onboardMore, [("bell.fill", s.featureFavs), ("point.topleft.down.to.point.bottomright.curvepath", s.featurePlan),
                                         ("exclamationmark.triangle.fill", s.featureAlerts)]).tag(3)
                mapPage.tag(4)
                appearancePage.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            HStack {
                Button(s.previous) { withAnimation { page -= 1 } }
                    .disabled(page == 0)
                Spacer()
                if page < pages - 1 {
                    Button(s.next) { withAnimation { page += 1 } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(s.start, action: onDone)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            if let logo = BundledAsset.image("OpenTransport_logo.png") {
                Image(uiImage: logo).resizable().scaledToFit().frame(height: 140)
            }
            Text(s.appName).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
            Text(s.welcome).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(24)
    }

    private func features(_ title: String, _ items: [(String, String)]) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: items.first?.0 ?? "map")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 8)
            Text(title).font(.title.weight(.bold)).multilineTextAlignment(.center)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 14) {
                    Image(systemName: item.0).font(.title2).foregroundStyle(Color.accentColor).frame(width: 36)
                    Text(item.1).font(.body)
                    Spacer()
                }
                .padding(16)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Spacer()
            Spacer()
        }
        .padding(24)
    }

    private var mapPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(s.onboardMap).font(.title2.weight(.bold)).padding(.top, 40)
                ForEach(Network.allCases, id: \.self) { network in
                    Toggle(isOn: networkBinding(network)) {
                        HStack(spacing: 12) {
                            ServiceLogo(network: network, size: 26)
                            Text(network.label).font(.headline)
                        }
                    }
                }
                Text(s.mapStyle).font(.headline).padding(.top, 12)
                Picker(s.mapStyle, selection: $mapStyle) {
                    ForEach(MapStyle.allCases) { Text($0.label(s)).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            .padding(24)
            .padding(.bottom, 40)
        }
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(s.appearance).font(.title2.weight(.bold)).padding(.top, 40)
            Text(s.languageTitle).font(.headline)
            Picker(s.languageTitle, selection: $languageCode) {
                ForEach(Language.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Text(s.appearance).font(.headline).padding(.top, 12)
            Picker(s.appearance, selection: $theme) {
                ForEach(AppTheme.allCases) { Text($0.label(s)).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Spacer()
        }
        .padding(24)
    }

    private func networkBinding(_ network: Network) -> Binding<Bool> {
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
