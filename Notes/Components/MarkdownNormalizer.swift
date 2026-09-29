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

        // 2. Normalize escaped TeX delimiters (both single-escaped and double-escaped literal strings)
        // \[ and \] -> $$ (display math)
        text = text.replacingOccurrences(of: "\\\\[", with: "$$")
        text = text.replacingOccurrences(of: "\\\\]", with: "$$")
        text = text.replacingOccurrences(of: "\\[", with: "$$")
        text = text.replacingOccurrences(of: "\\]", with: "$$")
        // \( and \) -> $ (inline math)
        text = text.replacingOccurrences(of: "\\\\(", with: "$")
        text = text.replacingOccurrences(of: "\\\\)", with: "$")
        text = text.replacingOccurrences(of: "\\(", with: "$")
        text = text.replacingOccurrences(of: "\\)", with: "$")

        // Helper to process only non-math segments so we never alter already-valid math blocks
        func processNonMathSegments(in input: String, process: (String) -> String) -> String {
            let mathDelimPattern = #"(\$\$[\s\S]*?\$\$|\$[^\$\n]+?\$)"#
            guard let mathRegex = try? NSRegularExpression(pattern: mathDelimPattern) else {
                return process(input)
            }

            let nsText = input as NSString
            let matches = mathRegex.matches(in: input, range: NSRange(location: 0, length: nsText.length))

            var result = ""
            var lastIdx = 0

            for match in matches {
                if match.range.location > lastIdx {
                    let nonMath = nsText.substring(with: NSRange(location: lastIdx, length: match.range.location - lastIdx))
                    result += process(nonMath)
                }
                let math = nsText.substring(with: match.range)
                result += math
                lastIdx = match.range.location + match.range.length
            }
            if lastIdx < nsText.length {
                let remaining = nsText.substring(with: NSRange(location: lastIdx, length: nsText.length - lastIdx))
                result += process(remaining)
            }

            return result
        }

        // 3. Wrap bare equations with = e.g. "y = \sqrt{x}" or "f(x) = x^2" or "KE = 1/2mv2"
        let eqPattern = #"(?<!\w)([A-Za-z](?:\([A-Za-z0-9, ]+\))?\s*=\s*(?:[A-Za-z0-9.^_+\*/()\\-]|(?:\{[^}]*\}))+)(?=[^A-Za-z0-9.^_+\*/\\{]|$)"#
        if let eqRegex = try? NSRegularExpression(pattern: eqPattern) {
            text = processNonMathSegments(in: text) { nonMath in
                let nsSeg = nonMath as NSString
                let eqMatches = eqRegex.matches(in: nonMath, range: NSRange(location: 0, length: nsSeg.length))
                var processedSeg = ""
                var segLastIdx = 0
                for eqMatch in eqMatches {
                    if eqMatch.range.location > segLastIdx {
                        processedSeg += nsSeg.substring(with: NSRange(location: segLastIdx, length: eqMatch.range.location - segLastIdx))
                    }
                    var eq = nsSeg.substring(with: eqMatch.range)
                    eq = eq.replacingOccurrences(of: #"\b1\s*/\s*2\b"#, with: #"\frac{1}{2}"#, options: .regularExpression)
                           .replacingOccurrences(of: #"([A-Za-z])2\b"#, with: #"$1^2"#, options: .regularExpression)
                    processedSeg += "$" + eq.trimmingCharacters(in: .whitespaces) + "$"
                    segLastIdx = eqMatch.range.location + eqMatch.range.length
                }
                if segLastIdx < nsSeg.length {
                    processedSeg += nsSeg.substring(with: NSRange(location: segLastIdx, length: nsSeg.length - segLastIdx))
                }
                return processedSeg
            }
        }

        // 4. Standalone bare LaTeX commands in remaining non-math segments: e.g. "\sqrt{25}" or "\frac{a}{b}"
        let bareLatexPattern = #"(\\(?:sqrt|frac|pm|times|cdot|approx|leq|geq|neq|sum|int|alpha|beta|theta|pi|infty)(?:\[[^\]]*\])?(?:\{[^\}]*\})*)"#
        if let bareRegex = try? NSRegularExpression(pattern: bareLatexPattern) {
            text = processNonMathSegments(in: text) { nonMath in
                let nsSeg = nonMath as NSString
                let bareMatches = bareRegex.matches(in: nonMath, range: NSRange(location: 0, length: nsSeg.length))
                var processedSeg = ""
                var segLastIdx = 0
                for bMatch in bareMatches {
                    if bMatch.range.location > segLastIdx {
                        processedSeg += nsSeg.substring(with: NSRange(location: segLastIdx, length: bMatch.range.location - segLastIdx))
                    }
                    let latex = nsSeg.substring(with: bMatch.range)
                    processedSeg += "$" + latex.trimmingCharacters(in: .whitespaces) + "$"
                    segLastIdx = bMatch.range.location + bMatch.range.length
                }
                if segLastIdx < nsSeg.length {
                    processedSeg += nsSeg.substring(with: NSRange(location: segLastIdx, length: nsSeg.length - segLastIdx))
                }
                return processedSeg
            }
        }

        // 5. Trim whitespace safely inside math blocks without corrupting surrounding text
        let mathDelimPattern = #"(\$\$[\s\S]*?\$\$|\$[^\$\n]+?\$)"#
        if let mathRegex = try? NSRegularExpression(pattern: mathDelimPattern) {
            let nsText = text as NSString
            let matches = mathRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            var trimmedResult = ""
            var lastIdx = 0
            for match in matches {
                if match.range.location > lastIdx {
                    trimmedResult += nsText.substring(with: NSRange(location: lastIdx, length: match.range.location - lastIdx))
                }
                let math = nsText.substring(with: match.range)
                if math.hasPrefix("$$") && math.hasSuffix("$$") && math.count >= 4 {
                    let inner = String(math.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    trimmedResult += "$$" + inner + "$$"
                } else if math.hasPrefix("$") && math.hasSuffix("$") && math.count >= 2 {
                    let inner = String(math.dropFirst(1).dropLast(1)).trimmingCharacters(in: .whitespaces)
                    trimmedResult += "$" + inner + "$"
                } else {
                    trimmedResult += math
                }
                lastIdx = match.range.location + match.range.length
            }
            if lastIdx < nsText.length {
                trimmedResult += nsText.substring(with: NSRange(location: lastIdx, length: nsText.length - lastIdx))
            }
            text = trimmedResult
        }

        // 6. Clean up unmatched parentheses near dollar signs
        text = text.replacingOccurrences(of: #"\$\s*\)"#, with: "$)", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\(\s*\$"#, with: "($", options: .regularExpression)

        return text
    }
}
