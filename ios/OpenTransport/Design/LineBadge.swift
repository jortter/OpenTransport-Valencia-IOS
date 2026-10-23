import SwiftUI

private let linePalette: [Color] = [
    0xF97316, 0x0EA5E9, 0xE11D48, 0x8B5CF6,
    0x14B8A6, 0xF43F5E, 0x6366F1, 0x22C55E,
    0xF59E0B, 0x06B6D4, 0xA855F7, 0x84CC16,
].map { Color(hex: $0) }

/// Same colour as Android's `stableLineColor`, which indexes by Java's `String.hashCode`.
func stableLineColor(_ line: String) -> Color {
    var hash: Int32 = 0
    for unit in line.utf16 { hash = hash &* 31 &+ Int32(unit) }
    return linePalette[Int(abs(Int64(hash)) % Int64(linePalette.count))]
}

extension Color {
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct LineBadge: View {
    let line: String

    var body: some View {
        Text(line)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minWidth: 32)
            .background(stableLineColor(line), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
