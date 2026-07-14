import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval?
    let text: String
}

enum LyricsParser {
    private static let timestamp = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
    )
    private static let metadata = try! NSRegularExpression(
        pattern: #"^\[(?:ti|ar|al|by|offset|re|ve|length):"#,
        options: [.caseInsensitive]
    )
    private static let offset = try! NSRegularExpression(
        pattern: #"\[offset:([+-]?\d+)\]"#,
        options: [.caseInsensitive]
    )

    static func parse(synced: String?, plain: String?) -> [LyricLine] {
        if let synced, !synced.isEmpty {
            let lines = synchronizedLines(from: synced)
            if !lines.isEmpty { return lines }
        }
        return plainLines(from: plain ?? synced ?? "")
    }

    static func activeLineID(in lines: [LyricLine], at elapsed: TimeInterval) -> Int? {
        lines.last { line in
            guard let time = line.time else { return false }
            return time <= elapsed
        }?.id
    }

    private static func synchronizedLines(from value: String) -> [LyricLine] {
        let offsetSeconds = lyricOffset(in: value) / 1_000
        var parsed: [(time: TimeInterval, order: Int, text: String)] = []

        for (order, rawLine) in value.components(separatedBy: .newlines).enumerated() {
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            let matches = timestamp.matches(in: rawLine, range: range)
            guard !matches.isEmpty else { continue }
            let text = timestamp.stringByReplacingMatches(
                in: rawLine,
                range: range,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let time = time(for: match, in: rawLine) else { continue }
                parsed.append((max(0, time + offsetSeconds), order, text))
            }
        }

        return parsed
            .sorted { lhs, rhs in
                lhs.time == rhs.time ? lhs.order < rhs.order : lhs.time < rhs.time
            }
            .enumerated()
            .map { index, value in
                LyricLine(id: index, time: value.time, text: value.text)
            }
    }

    private static func plainLines(from value: String) -> [LyricLine] {
        value.components(separatedBy: .newlines).compactMap { rawLine in
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard !trimmed.isEmpty,
                  metadata.firstMatch(in: trimmed, range: range) == nil else { return nil }
            let text = timestamp.stringByReplacingMatches(
                in: trimmed,
                range: range,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        .enumerated()
        .map { index, text in LyricLine(id: index, time: nil, text: text) }
    }

    private static func lyricOffset(in value: String) -> TimeInterval {
        let range = NSRange(value.startIndex..., in: value)
        guard let match = offset.firstMatch(in: value, range: range),
              let milliseconds = number(in: match, group: 1, source: value) else { return 0 }
        return milliseconds
    }

    private static func time(for match: NSTextCheckingResult, in source: String) -> TimeInterval? {
        guard let minutes = number(in: match, group: 1, source: source),
              let seconds = number(in: match, group: 2, source: source) else { return nil }
        let fractionText = text(in: match, group: 3, source: source) ?? ""
        let fraction = Double(fractionText) ?? 0
        let divisor = pow(10, Double(fractionText.count))
        return minutes * 60 + seconds + (divisor > 1 ? fraction / divisor : 0)
    }

    private static func number(
        in match: NSTextCheckingResult,
        group: Int,
        source: String
    ) -> Double? {
        text(in: match, group: group, source: source).flatMap(Double.init)
    }

    private static func text(
        in match: NSTextCheckingResult,
        group: Int,
        source: String
    ) -> String? {
        let range = match.range(at: group)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: source) else { return nil }
        return String(source[swiftRange])
    }
}
