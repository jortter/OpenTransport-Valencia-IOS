import SwiftUI
import OpenTransportCore

/// Port of `FollowSheet` in EmtApp.kt: one live bus, the camera behind it and
/// the minutes to its next stops.
struct FollowSheet: View {
    let number: Int

    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let bus = model.map.live.buses.first { $0.number == number }

        NavigationStack {
            List {
                if let bus {
                    Section {
                        HStack(spacing: 12) {
                            LineBadge(line: bus.line)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bus.destination.isEmpty ? s.lineTitle(bus.line) : bus.destination)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(s.directionLabel(bus.direction ?? "ida"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section(s.nextStops) {
                        ForEach(Array(upcoming(bus).enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill").foregroundStyle(.secondary)
                                Text(item.stop.cleanName).lineLimit(1)
                                Spacer()
                                Text("\(item.minutes) min").foregroundStyle(Color.accentColor).monospacedDigit()
                            }
                        }
                    }
                } else {
                    Text(s.busLeftMap).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(s.busTitle(number))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !model.map.followCameraLocked {
                        Button {
                            model.map.followCameraLocked = true
                        } label: {
                            Image(systemName: "scope")
                        }
                        .accessibilityLabel(s.centerOnBus)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.map.follow3D.toggle()
                    } label: {
                        Image(systemName: model.map.follow3D ? "cube.fill" : "cube")
                    }
                    .accessibilityLabel(s.view3D)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let bus {
                            Button {
                                model.togglePin(ArrivalAlerts.stopPin(bus.nextStop, bus.line))
                            } label: {
                                Label(s.alertAtNextStop, systemImage: "bell")
                            }
                            Button {
                                openInMaps(lat: bus.render.lat, lon: bus.render.lon, name: s.busTitle(number))
                            } label: {
                                Label(s.openPositionInMaps, systemImage: "map")
                            }
                        }
                        Button(role: .destructive) {
                            dismiss()
                        } label: {
                            Label(s.stopFollowing, systemImage: "xmark")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private func upcoming(_ bus: BusPosition) -> [UpcomingStop] {
        guard let transit = model.transit, bus.route != nil else { return [] }
        return TransitMotion.upcoming(transit.routes, stopsById: transit.stopsById, line: bus.line,
                                      dir: bus.direction ?? "ida", next: bus.nextStop, position: bus.render)
    }
}
