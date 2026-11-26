import Foundation

/// Labs › Manage autocorrect rules' export and import format, pairs with counts and language
/// only, never the text around them:
///
/// - JSON: `{"version":1,"rules":[{"language":"de","typed":"udn","correction":"und","count":3}]}`
/// - CSV: a `language,typed,correction,count` header, then one rule a line.
///
/// `language` is a keyboard language (`KeyboardLanguage.rawValue`); `count` is optional on import.
enum AutocorrectRulesFile {
    static let version = 1
    static let maxBytes = 256 * 1024
    static let maxRules = 1000
    static let maxWordLength = 48
    static let csvHeader = ["language", "typed", "correction", "count"]

    enum Format: String, CaseIterable {
        case json, csv

        var fileExtension: String { rawValue }
    }

    /// One row of a file being imported: a rule, or why it was left out.
    struct Row: Identifiable {
        let id: Int
        let result: Result<AutocorrectRule, Rejection>
    }

    struct Rejection: Error {
        let reason: String
    }

    struct Failure: Error {
        let reason: String
    }

    static func export(_ rules: [AutocorrectRule], as format: Format) -> String {
        switch format {
        case .json:
            let object: [String: Any] = [
                "version": version,
                "rules": rules.map { ["language": $0.language, "typed": $0.typed, "correction": $0.correction, "count": $0.count] },
            ]
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        case .csv:
            let lines = [csvHeader] + rules.map { [$0.language, $0.typed, $0.correction, String($0.count)] }
            return lines.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\n") + "\n"
        }
    }

    /// The file's rows, JSON when it starts with `{`, else CSV. Fails as a whole only when the
    /// file is too big, unreadable, or has too many rows.
    static func parse(_ data: Data) -> Result<[Row], Failure> {
        guard data.count <= maxBytes else {
            return .failure(Failure(reason: String(localized: "The file is larger than 256 KB.")))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .failure(Failure(reason: String(localized: "The file isn't UTF-8 text.")))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = trimmed.hasPrefix("{") ? parseJSON(data) : parseCSV(trimmed)
        if case .success(let list) = rows, list.count > maxRules {
            return .failure(Failure(reason: String(localized: "The file has more than \(maxRules) rules.")))
        }
        return rows
    }

    private static func parseJSON(_ data: Data) -> Result<[Row], Failure> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = object["rules"] as? [Any]
        else { return .failure(Failure(reason: String(localized: "The JSON has no \"rules\" list."))) }
        guard (object["version"] as? Int) == version else {
            return .failure(Failure(reason: String(localized: "Only version 1 files can be imported.")))
        }
        var seen: Set<String> = []
        return .success(rules.prefix(maxRules + 1).enumerated().map { index, item in
            guard let fields = item as? [String: Any] else {
                return Row(id: index, result: .failure(Rejection(reason: String(localized: "Not a rule"))))
            }
            let count: String? = switch fields["count"] {
            case nil: nil
            case let number as Int: String(number)
            default: "?"
            }
            return Row(id: index, result: validate(
                language: fields["language"] as? String, typed: fields["typed"] as? String,
                correction: fields["correction"] as? String, count: count, seen: &seen
            ))
        })
    }

    private static func parseCSV(_ text: String) -> Result<[Row], Failure> {
        let lines = csvRecords(text)
        guard let header = lines.first, header.map({ $0.lowercased() }) == csvHeader else {
            return .failure(Failure(reason: String(localized: "The CSV's first line must be language,typed,correction,count.")))
        }
        var seen: Set<String> = []
        return .success(lines.dropFirst().prefix(maxRules + 1).enumerated().map { index, fields in
            guard fields.count == csvHeader.count else {
                return Row(id: index, result: .failure(Rejection(reason: String(localized: "Needs 4 columns"))))
            }
            return Row(id: index, result: validate(
                language: fields[0], typed: fields[1], correction: fields[2],
                count: fields[3].isEmpty ? nil : fields[3], seen: &seen
            ))
        })
    }

    private static func validate(
        language: String?, typed: String?, correction: String?, count: String?, seen: inout Set<String>
    ) -> Result<AutocorrectRule, Rejection> {
        func reject(_ reason: String) -> Result<AutocorrectRule, Rejection> { .failure(Rejection(reason: reason)) }
        guard let language, KeyboardLanguage(rawValue: language) != nil else {
            return reject(String(localized: "Unknown language"))
        }
        guard let typed, isWord(typed), !typed.contains(" ") else {
            return reject(String(localized: "Typed must be one word"))
        }
        guard let correction, isWord(correction) else {
            return reject(String(localized: "Missing or invalid correction"))
        }
        guard typed != correction else { return reject(String(localized: "Typed and correction are the same")) }
        let number = count.map { Int($0) } ?? 0
        guard let number, number >= 0 else { return reject(String(localized: "Count must be a whole number")) }
        let rule = AutocorrectRule(language: language, typed: typed, correction: correction, count: number)
        guard seen.insert(rule.key).inserted else { return reject(String(localized: "Repeats an earlier rule")) }
        return .success(rule)
    }

    private static func isWord(_ text: String) -> Bool {
        !text.isEmpty && text.count <= maxWordLength && text == text.trimmingCharacters(in: .whitespaces)
            && !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) }
    }

    private static func csvField(_ field: String) -> String {
        field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : field
    }

    /// RFC 4180 records: quoted fields may hold commas, doubled quotes and line breaks.
    private static func csvRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { field.append(chars.removeFirst()) } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                quoted = true
            } else if c == "," {
                record.append(field)
                field = ""
            } else if c == "\n" {
                records.append(record + [field])
                record = []
                field = ""
            } else {
                field.append(c)
            }
        }
        records.append(record + [field])
        return records.filter { $0 != [""] }
    }
}
