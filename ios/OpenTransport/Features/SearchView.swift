import SwiftUI
import OpenTransportCore

/// Full-screen search over stops (by name or number) and lines, like the
/// expanded search of the Android map tab.
struct SearchView: View {
    var onPickStop: (Int) -> Void
    var onPickLine: (String) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var byLine = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(byLine ? s.searchLine : s.searchStop, text: $query)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel(s.close)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color(.secondarySystemBackground), in: Capsule())
                Button(s.close) { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Picker("", selection: $byLine) {
                Text(s.stops).tag(false)
                Text(s.lines).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(16)

            results
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var results: some View {
        let transit = model.transit
        let stops = transit.map { TransitSearch.stops($0.stops, query: query) } ?? []
        let lines = transit.map { TransitSearch.lines($0, query: query) } ?? []
        let empty = byLine ? lines.isEmpty : stops.isEmpty

        if empty {
            ContentUnavailableView(query.isEmpty ? s.typeToSearch : s.noMatches, systemImage: "magnifyingglass")
        } else {
            List {
                if byLine {
                    ForEach(lines, id: \.self) { line in
                        Button {
                            onPickLine(line)
                        } label: {
                            HStack(spacing: 12) {
                                LineBadge(line: line)
                                Text(s.lineTitle(line))
                            }
                        }
                        .tint(.primary)
                    }
                } else {
                    ForEach(stops) { stop in
                        Button {
                            onPickStop(stop.id)
                        } label: {
                            HStack(spacing: 12) {
                                ServiceLogo(network: .emt, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.cleanName).lineLimit(1)
                                    Text("\(stop.id) · \(stop.lines.joined(separator: " · "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
        }
    }
}
