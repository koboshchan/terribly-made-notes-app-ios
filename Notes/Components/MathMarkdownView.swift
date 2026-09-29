import SwiftUI
import WebKit
import WKMarkdownView

/// A high-performance Markdown view with LaTeX math rendering support (inline $...$ and block $$...$$).
public struct MathMarkdownView: View {
    private let rawMarkdown: String
    private let normalizedMarkdown: String
    private let isCentered: Bool
    private let fontSize: CGFloat?
    private let customPadding: String?
    private let allowsInteraction: Bool
    private let showLoadingPlaceholder: Bool
    @State private var contentHeight: CGFloat
    @State private var hasRendered = false

    public init(
        _ markdown: String,
        isCentered: Bool = false,
        fontSize: CGFloat? = nil,
        customPadding: String? = nil,
        allowsInteraction: Bool = true,
        showLoadingPlaceholder: Bool = true,
        initialHeight: CGFloat = 120
    ) {
        self.rawMarkdown = markdown
        self.normalizedMarkdown = MarkdownNormalizer.normalize(markdown)
        self.isCentered = isCentered
        self.fontSize = fontSize
        self.customPadding = customPadding
        self.allowsInteraction = allowsInteraction
        self.showLoadingPlaceholder = showLoadingPlaceholder
        _contentHeight = State(initialValue: initialHeight)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            MathMarkdownWebView(
                markdown: normalizedMarkdown,
                isCentered: isCentered,
                fontSize: fontSize,
                customPadding: customPadding,
                allowsInteraction: allowsInteraction,
                contentHeight: $contentHeight,
                hasRendered: $hasRendered
            )
            .frame(height: max(contentHeight, 36))
            .opacity(hasRendered ? 1 : 0)

            if !hasRendered && showLoadingPlaceholder {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Rendering notes & math...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .animation(.easeOut(duration: 0.15), value: hasRendered)
    }
}

private struct MathMarkdownWebView: UIViewRepresentable {
    let markdown: String
    let isCentered: Bool
    let fontSize: CGFloat?
    let customPadding: String?
    let allowsInteraction: Bool
    @Binding var contentHeight: CGFloat
    @Binding var hasRendered: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKMarkdownView {
        let configuration = WKWebViewConfiguration()
        let webView = WKMarkdownView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.isUserInteractionEnabled = allowsInteraction
        context.coordinator.setup(webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKMarkdownView, context: Context) {
        webView.isUserInteractionEnabled = allowsInteraction
        guard context.coordinator.lastRenderedMarkdown != markdown else { return }
        context.coordinator.lastRenderedMarkdown = markdown

        Task { @MainActor in
            do {
                try await webView.updateMarkdown(markdown)
                if isCentered {
                    _ = try? await webView.evaluateJavaScript("document.body.style.textAlign = 'center';")
                }
                if let fontSize = fontSize {
                    _ = try? await webView.evaluateJavaScript("document.body.style.fontSize = '\(fontSize)px';")
                }
                if let customPadding = customPadding {
                    _ = try? await webView.evaluateJavaScript("const c = document.getElementById('markdown-content'); if (c) c.style.padding = '\(customPadding)';")
                }
                var height = try await webView.contentHeight()
                if height <= 0 {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    height = try await webView.contentHeight()
                }
                if height > 0 {
                    self.contentHeight = CGFloat(height)
                }
                self.hasRendered = true
            } catch {
                print("MathMarkdownView rendering error: \(error)")
                self.hasRendered = true
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MathMarkdownWebView
        var lastRenderedMarkdown: String?
        weak var webView: WKMarkdownView?

        init(_ parent: MathMarkdownWebView) {
            self.parent = parent
        }

        func setup(webView: WKMarkdownView) {
            self.webView = webView
        }

        // Open external links in Safari
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}
