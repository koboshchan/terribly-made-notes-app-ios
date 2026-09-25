import Foundation

public enum MarkdownNormalizer {
    /// Normalizes raw markdown and LaTeX math formatting so KaTeX and Marked render accurately.
    public static func normalize(_ markdown: String) -> String {
        var text = markdown

        // 1. Strip zero-width characters that break parsing
        text = text.replacingOccurrences(
            of: "[\u{200B}-\u{200D}\u{FEFF}]",
            with: "",
            options: .regularExpression
        )

        // 2. Normalize escaped TeX delimiters
        // \[ and \] -> $$ (display math)
        text = text.replacingOccurrences(of: "\\\\[", with: "$$", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\\\]", with: "$$", options: .regularExpression)
        // \( and \) -> $ (inline math)
        text = text.replacingOccurrences(of: "\\\\(", with: "$", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\\\)", with: "$", options: .regularExpression)

        // 3. Trim accidental whitespace immediately inside $...$ delimiters
        // e.g. "$ \rightarrow y = 2\sqrt{x}$" -> "$\rightarrow y = 2\sqrt{x}$"
        text = text.replacingOccurrences(
            of: #"\$(\s+)(?=[^\$\s])"#,
            with: "$",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?<=[^\$\s])(\s+)\$"#,
            with: "$",
            options: .regularExpression
        )

        // 4. Clean up unmatched parentheses near dollar signs
        text = text.replacingOccurrences(of: #"\$\s*\)"#, with: "$)", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\(\s*\$"#, with: "($", options: .regularExpression)

        return text
    }
}
