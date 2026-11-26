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
