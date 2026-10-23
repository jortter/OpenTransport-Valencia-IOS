import SwiftUI
import OpenTransportCore

/// Port of `LineSheet` in EmtApp.kt: a focused line, its live buses and the
/// minutes to each stop along it.
struct LineSheet: View {
    let line: String

    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let buses = model.map.live.buses.filter { $0.line == line }
        let direction = buses.first?.direction ?? "ida"
        let stops = stopsAlong(direction)
        let etas = etas(buses)

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        LineBadge(line: line)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.lineTitle(line)).font(.headline)
                            Text("\(s.liveBuses(buses.count)) · \(s.directionLabel(direction))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(s.stops) {
                    // Circular lines can list a stop twice: key rows by position.
                    ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                        Button {
                            model.map.selectStop(stop.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stop.cleanName).foregroundStyle(.primary).lineLimit(1)
                                    LineBadges(lines: stop.lines)
                                }
                                Spacer()
                                if let eta = etas[stop.id] {
                                    Text("\(eta) min").foregroundStyle(.tint).monospacedDigit()
                                } else {
                                    Text("—").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(s.lineTitle(line))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(s.close) { dismiss() }
                }
            }
        }
    }

    private func stopsAlong(_ direction: String) -> [Stop] {
        guard let transit = model.transit, let route = transit.routes[line] else { return [] }
        return (direction == "vuelta" ? route.vuelta : route.ida).stops.compactMap { transit.stopsById[$0] }
    }

    /// Minutes for each stop along the line, from the live buses on it.
    private func etas(_ buses: [BusPosition]) -> [Int: Int] {
        guard let transit = model.transit else { return [:] }
        var result: [Int: Int] = [:]
        for bus in buses where bus.route != nil {
            let upcoming = TransitMotion.upcoming(transit.routes, stopsById: transit.stopsById, line: bus.line,
                                                  dir: bus.direction ?? "ida", next: bus.nextStop, position: bus.render)
            for item in upcoming {
                result[item.stop.id] = min(result[item.stop.id] ?? Int.max, item.minutes)
            }
        }
        return result
    }
}
