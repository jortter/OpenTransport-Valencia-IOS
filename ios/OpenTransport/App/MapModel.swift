import Foundation
import Observation
import OpenTransportCore

/// What the bottom sheet over the map is showing. Only one at a time, like
/// the panes stacked over the map in EmtApp.kt.
enum MapSheet: Identifiable, Hashable {
    case stop(Int)
    case line(String)
    case bus(Int)

    var id: String {
        switch self {
        case .stop(let id): return "stop-\(id)"
        case .line(let line): return "line-\(line)"
        case .bus(let number): return "bus-\(number)"
        }
    }
}

/// A one-shot camera move; `id` changes on every request so the map view can
/// tell a new request from a re-render.
struct CameraRequest: Equatable {
    enum Kind: Equatable {
        case center(LonLat, zoom: Double)
        case fit(LngLatBounds)
    }

    let id: Int
    let kind: Kind
}

/// Map selection state: selected stop, focused line, followed bus.
@MainActor
@Observable
final class MapModel {
    var sheet: MapSheet?
    private(set) var currentLine: String?
    private(set) var cameraRequest: CameraRequest?
    let live = LiveBuses()

    @ObservationIgnored private var transit: TransitData?

    func configure(transit: TransitData, client: EmtClient) {
        self.transit = transit
        live.configure(transit: transit, client: client)
    }

    var selectedStopId: Int? {
        if case .stop(let id) = sheet { return id }
        return nil
    }

    var followedBus: Int? {
        if case .bus(let number) = sheet { return number }
        return nil
    }

    func selectStop(_ id: Int) {
        guard let stop = transit?.stopsById[String(id)] else { return }
        currentLine = nil
        live.track(line: nil)
        sheet = .stop(id)
        move(.center(LonLat(lon: stop.lon, lat: stop.lat), zoom: 16.5))
    }

    func selectLine(_ line: String) {
        guard let route = transit?.routes[line] else { return }
        if currentLine != line { live.track(line: line) }
        currentLine = line
        sheet = .line(line)
        if let bounds = route.bounds { move(.fit(bounds)) }
    }

    /// Called when the sheet goes away (swiped down or closed).
    func sheetDismissed() {
        guard sheet == nil else { return }
        currentLine = nil
        live.track(line: nil)
    }

    func close() {
        sheet = nil
        sheetDismissed()
    }

    func move(_ kind: CameraRequest.Kind) {
        cameraRequest = CameraRequest(id: (cameraRequest?.id ?? 0) + 1, kind: kind)
    }
}

/// Polls EMT for the focused line's buses and feeds the tracker. The map reads
/// `tracker` every animation frame; sheets observe `buses`, refreshed per poll.
@MainActor
@Observable
final class LiveBuses {
    private(set) var buses: [BusPosition] = []
    private(set) var line: String?

    @ObservationIgnored private(set) var tracker: BusTracker?
    @ObservationIgnored private var client: EmtClient?
    @ObservationIgnored private var task: Task<Void, Never>?

    static let pollInterval: Duration = .seconds(1)

    func configure(transit: TransitData, client: EmtClient) {
        tracker = BusTracker(transit: transit)
        self.client = client
    }

    func track(line: String?) {
        task?.cancel()
        task = nil
        // Drop the previous line's buses at once so a stale one can't be tapped.
        tracker?.clear()
        buses = []
        self.line = line
        guard let line, let tracker, let client else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                if let fixes = try? await client.fetchBuses(line: line), !Task.isCancelled {
                    tracker.merge(fixes)
                    self?.buses = tracker.buses
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }
}
