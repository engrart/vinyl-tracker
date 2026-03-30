import Foundation

struct RecordImage: Identifiable, Codable, Equatable {
    let id: UUID
    let recordId: UUID
    let imageUrl: String
    let imageType: ImageType
    let isPrimary: Bool
    let createdAt: Date

    enum ImageType: String, Codable {
        case cover
        case label
        case photo
    }

    enum CodingKeys: String, CodingKey {
        case id
        case recordId   = "record_id"
        case imageUrl   = "image_url"
        case imageType  = "image_type"
        case isPrimary  = "is_primary"
        case createdAt  = "created_at"
    }
}
