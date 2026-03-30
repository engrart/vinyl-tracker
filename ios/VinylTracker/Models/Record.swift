import Foundation

// MARK: - Record

struct Record: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var year: Int?
    var genre: String?
    var notes: String?
    var condition: RecordCondition?
    var dateAdded: Date
    var mbid: String?
    var primaryImageUrl: String?
    var images: [RecordImage]?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, year, genre, notes, condition, mbid, images
        case dateAdded       = "date_added"
        case primaryImageUrl = "primary_image_url"
    }
}

// MARK: - Condition

enum RecordCondition: String, Codable, CaseIterable, Identifiable {
    case mint        = "M"
    case nearMint    = "NM"
    case veryGoodPlus = "VG+"
    case veryGood    = "VG"
    case goodPlus    = "G+"
    case good        = "G"
    case fair        = "F"
    case poor        = "P"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mint:         return "Mint (M)"
        case .nearMint:     return "Near Mint (NM)"
        case .veryGoodPlus: return "Very Good+ (VG+)"
        case .veryGood:     return "Very Good (VG)"
        case .goodPlus:     return "Good+ (G+)"
        case .good:         return "Good (G)"
        case .fair:         return "Fair (F)"
        case .poor:         return "Poor (P)"
        }
    }
}

// MARK: - Create / Update request body

struct RecordPayload: Encodable {
    let title: String
    let artist: String
    let year: Int?
    let genre: String?
    let notes: String?
    let condition: String?
    let mbid: String?
}
