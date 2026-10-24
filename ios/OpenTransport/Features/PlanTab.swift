import SwiftUI
import OpenTransportCore

/// A trip end: a stop/station, or the user's position.
struct PlanPoint: Equatable {
    let name: String
    let point: LonLat
}

/// Port of `PlanTab` in EmtApp.kt (beta, like on Android): pick a start and a
/// destination, plan, and open an option on the map.
struct PlanTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @State private var from: PlanPoint?
    @State private var to: PlanPoint?
    @State private var options: [JourneyOption]?
    @State private var planning = false
    @State private var picking: Target?

    private enum Target: String, Identifiable {
        case from, to
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    endpointRow(from?.name ?? s.chooseStart, systemImage: "smallcircle.filled.circle", placeholder: from == nil) {
                        picking = .from
                    }
                    .swipeActions {
                        Button(s.myLocation) { useLocation() }.tint(.blue)
                    }
                    endpointRow(to?.name ?? s.chooseDestination, systemImage: "flag.fill", placeholder: to == nil) {
                        picking = .to
                    }
                    Button {
                        useLocation()
                    } label: {
                        Label(s.myLocation, systemImage: "location.fill")
                    }
                    .disabled(model.location.location == nil)
                }
                Section {
                    Button {
                        Task { await plan() }
                    } label: {
                        HStack {
                            Spacer()
                            if planning { ProgressView().padding(.trailing, 6) }
                            Text(planning ? s.planning : s.plan).font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(from == nil || to == nil || planning)
                }
                if let options {
                    if options.isEmpty {
                        Text(s.noRoutes).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                            Section {
                                Button {
                                    open(option)
                                } label: {
                                    JourneyOptionView(option: option)
                                }
                                .tint(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(s.planTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(s.beta)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
            .sheet(item: $picking) { target in
                StopPicker { stop in
                    let point = PlanPoint(name: stop.cleanName, point: LonLat(lon: stop.lon, lat: stop.lat))
                    if target == .from { from = point } else { to = point }
                    options = nil
                    picking = nil
                }
            }
            .task { await runDemoPlan() }
        }
    }

    /// `-demoPlan 7,686` plans between two stop ids (used by CI screenshots).
    private func runDemoPlan() async {
        guard let ids = UserDefaults.standard.string(forKey: "demoPlan")?.split(separator: ",").compactMap({ Int($0) }),
              ids.count == 2 else { return }
        // The planner is created once the network has loaded.
        while model.planner == nil { try? await Task.sleep(for: .milliseconds(200)) }
        guard let transit = model.transit, let a = transit.stopsById[String(ids[0])], let b = transit.stopsById[String(ids[1])] else { return }
        from = PlanPoint(name: a.cleanName, point: LonLat(lon: a.lon, lat: a.lat))
        to = PlanPoint(name: b.cleanName, point: LonLat(lon: b.lon, lat: b.lat))
        await plan()
    }

    private func endpointRow(_ title: String, systemImage: String, placeholder: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title).foregroundStyle(placeholder ? Color.secondary : Color.primary)
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    private func useLocation() {
        guard let here = model.location.location else { return }
        from = PlanPoint(name: s.myLocation, point: here)
        options = nil
    }

    private func plan() async {
        guard let from, let to, let planner = model.planner else { return }
        planning = true
        options = await planner.plan(from: from.point, to: to.point)
        planning = false
    }

    private func open(_ option: JourneyOption) {
        guard let transit = model.transit else { return }
        model.tab = .map
        model.map.showJourney(PlannedJourney(option: option, transit: transit, origin: from?.point, destination: to?.point))
    }
}

/// One option: total time, transfers and its legs (Android's `JourneyOptionCard`).
struct JourneyOptionView: View {
    let option: JourneyOption

    @Environment(\.strings) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(option.totalMinutes) min").font(.title2.weight(.bold))
                Spacer()
                Text(option.transfers == 0 ? s.direct : s.transfers(option.transfers))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            Text(s.walkTotal(option.walkMeters)).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(option.legs.enumerated()), id: \.offset) { _, leg in
                HStack(spacing: 10) {
                    if leg.walk {
                        Image(systemName: "figure.walk").frame(width: 34).foregroundStyle(.secondary)
                        Text(s.walkLeg(leg.minutes, leg.meters)).font(.subheadline)
                        Spacer()
                    } else {
                        LineBadge(line: leg.line ?? "")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.towards(cleanStopName(leg.towards ?? ""))).font(.subheadline).lineLimit(1)
                            Text(s.rideLeg(board: cleanStopName(leg.boardStop ?? ""), stops: leg.stops, minutes: leg.minutes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(leg.waitMinutes) min").font(.subheadline).foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The planned trip over the map; closing it clears the trip (Android's `JourneySheet`).
struct JourneySheet: View {
    let option: JourneyOption

    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                JourneyOptionView(option: option)
            }
            .navigationTitle(s.trip)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(s.close) { dismiss() }
                }
            }
        }
    }
}

/// Search for a stop or station as a trip end (Android's `StopPickerSheet`).
struct StopPicker: View {
    var onPick: (Stop) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let stops = model.transit.map { TransitSearch.stops($0.stops, query: query, includeMetro: true) } ?? []
            List(stops) { stop in
                Button {
                    onPick(stop)
                } label: {
                    HStack(spacing: 12) {
                        ServiceLogo(network: stop.metro ? .metro : .emt, size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.cleanName).lineLimit(1)
                            Text(stop.lines.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .tint(.primary)
            }
            .overlay {
                if stops.isEmpty {
                    ContentUnavailableView(query.isEmpty ? s.typeToSearch : s.noMatches, systemImage: "magnifyingglass")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: s.searchStop)
            .navigationTitle(s.planTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
