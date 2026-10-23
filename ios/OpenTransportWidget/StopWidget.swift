import WidgetKit
import SwiftUI
import AppIntents
import OpenTransportCore

// Home-screen widget with the next arrivals at one EMT stop (port of
// StopWidgetProvider.kt / WidgetConfigureActivity.kt).

/// EMT stops from the bundled stops.json, searchable by name or number.
struct StopEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Stop"
    static var defaultQuery = StopQuery()

    let id: Int
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name) (\(id))") }
}

struct StopQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [StopEntity] {
        let stops = WidgetData.stops
        return identifiers.compactMap { id in stops.first { $0.id == id }.map { StopEntity(id: $0.id, name: $0.cleanName) } }
    }

    func entities(matching string: String) async throws -> [StopEntity] {
        TransitSearch.stops(WidgetData.stops, query: string).map { StopEntity(id: $0.id, name: $0.cleanName) }
    }

    func suggestedEntities() async throws -> [StopEntity] {
        Array(WidgetData.stops.prefix(20)).map { StopEntity(id: $0.id, name: $0.cleanName) }
    }
}

struct SelectStopIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Stop"
    static var description = IntentDescription("Next arrivals at an EMT stop.")

    @Parameter(title: "Stop")
    var stop: StopEntity?
}

/// The refresh button (Android's widget refresh action).
struct RefreshStopIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh"

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: StopWidget.kind)
        return .result()
    }
}

enum WidgetData {
    static let stops: [Stop] = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("assets/stops.json"),
              let data = try? Data(contentsOf: url),
              let transit = try? TransitDataLoader.load(stopsOnly: data) else { return [] }
        return transit
    }()
}

struct StopEntry: TimelineEntry {
    let date: Date
    let stop: StopEntity?
    /// (line, destination, minutes at `date`), at most 4.
    let rows: [(String, String, Int)]
    let failed: Bool
}

struct StopProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StopEntry {
        StopEntry(date: .now, stop: StopEntity(id: 7, name: "Doctor J.J. Dòmine"),
                  rows: [("19", "Malva-rosa", 3), ("92", "Pl. Ajuntament", 8), ("95", "Natzaret", 12)], failed: false)
    }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> StopEntry {
        context.isPreview ? placeholder(in: context) : await entry(for: configuration.stop)
    }

    func timeline(for configuration: SelectStopIntent, in context: Context) async -> Timeline<StopEntry> {
        let first = await entry(for: configuration.stop)
        // Count the minutes down locally for 5 minutes, then fetch again.
        let entries = (0..<5).map { offset in
            StopEntry(date: first.date.addingTimeInterval(Double(offset) * 60), stop: first.stop,
                      rows: first.rows.map { ($0.0, $0.1, max(0, $0.2 - offset)) }, failed: first.failed)
        }
        return Timeline(entries: entries, policy: .after(first.date.addingTimeInterval(5 * 60)))
    }

    private func entry(for stop: StopEntity?) async -> StopEntry {
        guard let stop else { return StopEntry(date: .now, stop: nil, rows: [], failed: false) }
        let client = EmtClient(data: TransitData(stops: [], stopsById: [:], routes: [:]))
        let now = Date()
        let arrivals = await client.estimations(stopId: stop.id)
        let rows = arrivals
            .map { ($0.line, $0.destination, EmtClient.etaMinutes($0, now: now)) }
            .filter { $0.2 != Int.max }
            .sorted { $0.2 < $1.2 }
            .prefix(4)
        return StopEntry(date: now, stop: stop, rows: Array(rows), failed: arrivals.isEmpty)
    }
}

struct StopWidgetView: View {
    let entry: StopEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.stop?.name ?? WidgetText.chooseStop)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
                if entry.stop != nil {
                    Button(intent: RefreshStopIntent()) {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            if entry.stop != nil {
                if entry.rows.isEmpty {
                    Spacer()
                    Text(WidgetText.noBuses).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(Array(entry.rows.prefix(family == .systemSmall ? 3 : 4).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 6) {
                            Text(row.0)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 28, minHeight: 18)
                                .background(widgetLineColor(row.0), in: RoundedRectangle(cornerRadius: 4))
                            if family != .systemSmall {
                                Text(row.1).font(.caption).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text(row.2 == 0 ? "<1 min" : "\(row.2) min")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(entry.stop.map { URL(string: "opentransport://stop/\($0.id)")! })
    }
}

struct StopWidget: Widget {
    static let kind = "StopWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectStopIntent.self, provider: StopProvider()) { entry in
            StopWidgetView(entry: entry)
        }
        .configurationDisplayName("OpenTransport")
        .description(WidgetText.description)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct OpenTransportWidgets: WidgetBundle {
    var body: some Widget {
        StopWidget()
    }
}

/// Same palette and hash as the app's `stableLineColor` (Android's LINE_PALETTE).
func widgetLineColor(_ line: String) -> Color {
    let palette = [0xF97316, 0x0EA5E9, 0xE11D48, 0x8B5CF6, 0x14B8A6, 0xF43F5E,
                   0x6366F1, 0x22C55E, 0xF59E0B, 0x06B6D4, 0xA855F7, 0x84CC16]
    var hash: Int32 = 0
    for unit in line.utf16 { hash = hash &* 31 &+ Int32(unit) }
    let hex = palette[Int(abs(Int64(hash)) % Int64(palette.count))]
    return Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

/// The widget can't read the app's language setting: follow the device.
enum WidgetText {
    private static var strings: Strings {
        let code = Locale.preferredLanguages.first?.lowercased() ?? ""
        return Strings(code.hasPrefix("ca") ? .va : code.hasPrefix("es") ? .es : .en)
    }

    static var noBuses: String { strings.noUpcomingBuses }
    static var chooseStop: String { strings.searchStop }
    static var description: String { strings.nextDepartures }
}
