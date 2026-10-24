import SwiftUI
import OpenTransportCore

/// Latest request to each service with its HTTP status, size or error, to
/// see on a real device which source fails (Settings → Network diagnostics).
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @State private var entries = NetworkLog.entries

    var body: some View {
        List {
            Section {
                LabeledContent("EMT", value: "\(model.transit?.stops.count ?? 0)")
                ForEach(Network.allCases.filter { $0 != .emt }, id: \.self) { network in
                    LabeledContent(network.label, value: "\(model.places.filter { $0.network == network }.count)")
                }
                LabeledContent(s.alerts, value: "\(model.incidents?.count ?? 0)")
            } header: {
                Text(s.loadedPoints)
            }
            Section(s.requests) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: entry.error == nil && (200..<300).contains(entry.status)
                                  ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(entry.error == nil && (200..<300).contains(entry.status) ? Color.green : Color.red)
                            Text("\(entry.method) \(entry.endpoint)").font(.caption.monospaced()).lineLimit(2)
                        }
                        Text(summary(entry)).font(.caption).foregroundStyle(.secondary)
                        if !entry.preview.isEmpty {
                            Text(entry.preview).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
            }
        }
        .navigationTitle(s.diagnostics)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: report()) { Image(systemName: "square.and.arrow.up") }
                Button {
                    entries = NetworkLog.entries
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable { entries = NetworkLog.entries }
    }

    private func summary(_ entry: NetworkLog.Entry) -> String {
        let outcome = entry.error ?? "HTTP \(entry.status) · \(entry.bytes) B"
        let time = entry.date.formatted(date: .omitted, time: .standard)
        return "\(time) · \(outcome) · ✓\(entry.successes) ✗\(entry.failures)"
    }

    private func report() -> String {
        entries.map { "\($0.method) \($0.endpoint)\n  \(summary($0))\n  \($0.preview)" }.joined(separator: "\n\n")
    }
}
