import Foundation

struct Pass: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var type: PassType
    var fields: PassFields
    var createdAt: Date
    var completedAt: Date?
    var imageSHA256: String
    var isPinned: Bool

    init(id: UUID = UUID(),
         type: PassType,
         fields: PassFields = [:],
         createdAt: Date = Date(),
         completedAt: Date? = nil,
         imageSHA256: String = "",
         isPinned: Bool = false) {
        self.id = id
        self.type = type
        self.fields = fields
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.imageSHA256 = imageSHA256
        self.isPinned = isPinned
    }

    var isCompleted: Bool { completedAt != nil }

    mutating func markCompleted(at date: Date = Date()) {
        completedAt = date
        isPinned = false
    }

    mutating func reopen() {
        completedAt = nil
    }
}

/// Pass's on-disk format. The two strategies must agree: if they drift, the
/// stored file becomes undecodable on the next launch and PassStore.load()
/// reads that as corruption and throws every pass away.
///
/// Deliberately not on PassStore, which is @MainActor — the widget extension
/// and the tests both need these without hopping to the main actor.
extension Pass {
    static func storeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func storeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
