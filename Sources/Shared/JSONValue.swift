import Foundation

/// A JSON scalar. The recognition backend returns heterogeneous `fields`
/// (strings, numbers, occasional nulls), so they cannot decode into one type.
enum JSONValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            // `unknown` results skip the backend's field normalisation, so the
            // model can emit a nested object or array. Dropping that one value
            // beats failing to decode a recognition the user already paid for.
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// Human-readable form. Integers lose the trailing `.0`.
    var displayText: String? {
        switch self {
        case .string(let value):
            return value.isEmpty ? nil : value
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 {
                return String(Int64(value))
            }
            return String(format: "%.2f", value)
        case .bool(let value):
            return value ? "是" : "否"
        case .null:
            return nil
        }
    }
}

/// The backend emits `datetime.isoformat()`, which omits the offset for naive
/// values. `ISO8601DateFormatter` rejects those, so try both shapes.
enum PassDateParser {
    private static let withZone: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let withZoneFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func localFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return formatter
    }

    private static let naiveSeconds = localFormatter("yyyy-MM-dd'T'HH:mm:ss")
    private static let naiveMinutes = localFormatter("yyyy-MM-dd'T'HH:mm")
    private static let naiveDate = localFormatter("yyyy-MM-dd")

    static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return withZone.date(from: trimmed)
            ?? withZoneFractional.date(from: trimmed)
            ?? naiveSeconds.date(from: trimmed)
            ?? naiveMinutes.date(from: trimmed)
            ?? naiveDate.date(from: trimmed)
    }
}

typealias PassFields = [String: JSONValue]

extension Dictionary where Key == String, Value == JSONValue {
    func text(_ key: String) -> String? {
        self[key]?.displayText
    }

    func number(_ key: String) -> Double? {
        self[key]?.doubleValue
    }

    func date(_ key: String) -> Date? {
        guard let raw = self[key]?.stringValue else { return nil }
        return PassDateParser.parse(raw)
    }

    /// Reads the first key that has a value, so callers can accept the several
    /// spellings the model tends to produce for the same idea.
    func firstText(_ keys: String...) -> String? {
        for key in keys {
            if let value = text(key) { return value }
        }
        return nil
    }

    func firstDate(_ keys: String...) -> Date? {
        for key in keys {
            if let value = date(key) { return value }
        }
        return nil
    }
}
