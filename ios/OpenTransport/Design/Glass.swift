import SwiftUI

extension View {
    /// Liquid Glass on iOS 26+, a material with a soft shadow before it.
    /// Used by the controls floating over the map.
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            materialBackground(in: shape)
        }
        #else
        materialBackground(in: shape)
        #endif
    }

    private func materialBackground<S: Shape>(in shape: S) -> some View {
        background(.regularMaterial, in: shape)
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

/// Groups glass controls so they blend into each other on iOS 26+.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
