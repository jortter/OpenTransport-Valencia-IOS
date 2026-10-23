import SwiftUI
import OpenTransportCore

struct MapTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.colorScheme) private var colorScheme
    @State private var recenterRequest = 0
    @State private var showSearch = false

    var body: some View {
        @Bindable var map = model.map
        ZStack {
            if let transit = model.transit {
                TransitMapView(
                    scene: scene(transit),
                    routes: transit.routes,
                    live: map.live,
                    dark: colorScheme == .dark,
                    cameraRequest: map.cameraRequest,
                    followedBus: map.followedBus,
                    follow3D: map.follow3D,
                    recenterRequest: recenterRequest,
                    onSelectStop: { map.selectStop($0) },
                    onSelectBus: { map.followBus($0) }
                )
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .top) { searchButton }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        recenterRequest += 1
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    }
                    .accessibilityLabel(s.myLocation)
                    .padding(.trailing, 16)
                    .padding(.bottom, 40) // clear of MapLibre's attribution button
                }
            } else if let error = model.loadError {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView(s.loading)
            }
        }
        .sheet(item: $map.sheet, onDismiss: { map.sheetDismissed() }) { sheet in
            Group {
                switch sheet {
                case .stop(let id): StopSheet(stopId: id)
                case .line(let line): LineSheet(line: line)
                case .bus(let number): FollowSheet(number: number)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView(
                onPickStop: { id in pick { map.selectStop(id) } },
                onPickLine: { line in pick { map.selectLine(line) } }
            )
        }
    }

    private var searchButton: some View {
        Button {
            // Only one presentation at a time: close the open sheet first.
            if model.map.sheet != nil {
                model.map.close()
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    showSearch = true
                }
            } else {
                showSearch = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(s.searchStop)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Dismisses the search, then selects once the cover has gone (presenting
    /// the sheet while the cover is still animating out would be dropped).
    private func pick(_ select: @escaping () -> Void) {
        showSearch = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            select()
        }
    }

    /// Which stops and routes the map shows, mirroring `visibleStops` and
    /// `contextLines` in EmtApp.kt: a focused line shows only its stops, a
    /// selected stop only itself plus the routes of its lines.
    private func scene(_ transit: TransitData) -> MapScene {
        let map = model.map
        if let line = map.currentLine {
            return MapScene(stopsKey: "line:\(line)",
                            stops: transit.stops.filter { !$0.metro && $0.lines.contains(line) },
                            mainLine: line, contextLines: [], sheetVisible: map.sheet != nil)
        }
        if let id = map.selectedStopId, let stop = transit.stopsById[String(id)] {
            return MapScene(stopsKey: "stop:\(id)", stops: [stop], mainLine: nil,
                            contextLines: stop.lines.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } },
                            sheetVisible: true)
        }
        return MapScene(stopsKey: "all", stops: transit.stops.filter { !$0.metro }, mainLine: nil,
                        contextLines: [], sheetVisible: map.sheet != nil)
    }
}
