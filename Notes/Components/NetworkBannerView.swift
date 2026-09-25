import SwiftUI

public struct NetworkBannerView: View {
    let message: String
    let onRetry: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        message: String = "Internet is not reachable",
        onRetry: (() -> Void)? = nil
    ) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 8)

            if let onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Retry connection")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). Tap retry to attempt refreshing.")
    }
}
