import SwiftUI
import WebKit
import WKMarkdownView

/// A high-performance Markdown view with LaTeX math rendering support (inline $...$ and block $$...$$).
public struct MathMarkdownView: View {
    private let rawMarkdown: String
    private let normalizedMarkdown: String
    @State private var contentHeight: CGFloat = 120
    @State private var hasRendered = false

    public init(_ markdown: String) {
        self.rawMarkdown = markdown
        self.normalizedMarkdown = MarkdownNormalizer.normalize(markdown)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            MathMarkdownWebView(
                markdown: normalizedMarkdown,
                contentHeight: $contentHeight,
                hasRendered: $hasRendered
            )
            .frame(height: max(contentHeight, 40))
            .opacity(hasRendered ? 1 : 0)

            if !hasRendered {
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
        context.coordinator.setup(webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKMarkdownView, context: Context) {
        guard context.coordinator.lastRenderedMarkdown != markdown else { return }
        context.coordinator.lastRenderedMarkdown = markdown

        Task { @MainActor in
            do {
                try await webView.updateMarkdown(markdown)
                let height = try await webView.contentHeight()
                if height > 0 {
                    self.contentHeight = CGFloat(height)
                    self.hasRendered = true
                }
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
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
