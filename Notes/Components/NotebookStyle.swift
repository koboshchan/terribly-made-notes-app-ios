import SwiftUI

/// Quiet, adaptive surfaces. Native navigation and sheet gestures retain their physics.
enum NotebookStyle {
    static let accent = Color.indigo
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let paper = Color(uiColor: .secondarySystemGroupedBackground)
    static let corner: CGFloat = 24
    static func motion(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: 0.32, dampingFraction: 1)
    }
}

struct NotebookSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .background(NotebookStyle.paper, in: RoundedRectangle(cornerRadius: NotebookStyle.corner))
            .overlay {
                RoundedRectangle(cornerRadius: NotebookStyle.corner)
                    .stroke(Color.primary.opacity(contrast == .increased ? 0.35 : 0.06), lineWidth: 1)
            }
    }
}

extension View {
    func notebookSurface() -> some View { modifier(NotebookSurface()) }
}

/// Immediate touch-down feedback without delaying or blocking the action.
struct NotebookPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.98 : 1)
            .animation(NotebookStyle.motion(reduced: reducedMotion), value: configuration.isPressed)
    }
}
