import Foundation

/// Applies heuristics to OCR text lines to extract vinyl record metadata fields.
/// Returns confidence-scored ParsedRecordMetadata — callers should use confidence
/// to decide whether to pre-fill a field or leave it blank for the user.
final class RecordTextParser {

    // MARK: - Patterns

    /// Matches years 1950–2029 as a standalone token (not part of a larger number)
    private static let yearRegex = try! NSRegularExpression(
        pattern: #"\b(19[5-9]\d|20[0-2]\d)\b"#
    )

    /// Tokens that strongly suggest a line is a record label, not artist/title
    private static let labelTokens: Set<String> = [
        "records", "music", "entertainment", "label", "productions", "studios",
        "publishing", "inc", "llc", "ltd", "corp", "co", "emi", "columbia",
        "atlantic", "capitol", "decca", "mercury", "reprise", "arista",
        "elektra", "island", "polydor", "epic", "mca", "rca", "motown",
        "stax", "chess", "blue note", "verve", "impulse", "prestige",
    ]

    /// Patterns that look like catalog numbers, matrix numbers, or side markers
    private static let catalogRegex = try! NSRegularExpression(
        pattern: #"^[A-Z]{1,4}[\-\s]?\d{3,8}[A-Z]?$"#
    )

    private static let sideRegex = try! NSRegularExpression(
        pattern: #"^(side\s)?[ab12]$"#,
        options: .caseInsensitive
    )

    // MARK: - Public

    func parse(_ result: OCRResult) -> ParsedRecordMetadata {
        let lines = result.rawLines
        guard !lines.isEmpty else { return .empty }

        let year  = extractYear(from: lines)
        let label = extractLabel(from: lines)
        let (artist, title) = extractArtistAndTitle(from: lines, yearString: year.map(String.init), label: label)

        return ParsedRecordMetadata(
            artist:           artist,
            artistConfidence: artist != nil ? 0.70 : 0,
            title:            title,
            titleConfidence:  title  != nil ? 0.65 : 0,
            year:             year,
            yearConfidence:   year   != nil ? 0.95 : 0,
            label:            label,
            labelConfidence:  label  != nil ? 0.60 : 0
        )
    }

    // MARK: - Field extraction

    private func extractYear(from lines: [String]) -> Int? {
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = Self.yearRegex.firstMatch(in: line, range: range),
               let swiftRange = Range(match.range, in: line),
               let year = Int(line[swiftRange]) {
                return year
            }
        }
        return nil
    }

    /// Label text tends to appear in the last few lines of a vinyl label scan,
    /// or anywhere on a cover, and contains known label-company vocabulary.
    private func extractLabel(from lines: [String]) -> String? {
        // Check last 4 lines first (label text usually near bottom of label scan)
        for line in lines.suffix(4).reversed() {
            if looksLikeLabel(line) { return line }
        }
        // Widen search to all lines
        for line in lines {
            if looksLikeLabel(line) { return line }
        }
        return nil
    }

    private func looksLikeLabel(_ line: String) -> Bool {
        let lower = line.lowercased()
        return Self.labelTokens.contains(where: { lower.contains($0) })
    }

    /// Remove noise lines then apply positional heuristic:
    /// top-most remaining line → artist, next → title.
    private func extractArtistAndTitle(
        from lines: [String],
        yearString: String?,
        label: String?
    ) -> (artist: String?, title: String?) {
        let filtered = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count < 2 { return false }

            // Drop year lines
            if let ys = yearString, t.contains(ys) { return false }

            // Drop the label line we already extracted
            if let lbl = label, t == lbl { return false }

            // Drop catalog / matrix numbers (e.g. "LSP-4567A")
            let r1 = NSRange(t.startIndex..., in: t)
            if Self.catalogRegex.firstMatch(in: t, range: r1) != nil { return false }

            // Drop side markers ("Side A", "B", "1", "2")
            let r2 = NSRange(t.startIndex..., in: t)
            if Self.sideRegex.firstMatch(in: t, range: r2) != nil { return false }

            // Drop pure-digit strings (track counts, RPM markers like "33⅓")
            if t.allSatisfy({ $0.isNumber || $0 == "⅓" || $0 == "/" }) { return false }

            return true
        }

        return (filtered.first, filtered.dropFirst().first)
    }
}

// MARK: - Empty sentinel

private extension ParsedRecordMetadata {
    static let empty = ParsedRecordMetadata(
        artist: nil, artistConfidence: 0,
        title:  nil, titleConfidence:  0,
        year:   nil, yearConfidence:   0,
        label:  nil, labelConfidence:  0
    )
}
