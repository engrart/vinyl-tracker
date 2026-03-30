import Foundation

/// Raw output from VisionOCRService — text lines extracted from the image.
struct OCRResult {
    /// All recognized text lines, sorted top-to-bottom by bounding box position.
    let rawLines: [String]
    /// First high-confidence line — likely the artist on a vinyl label/cover.
    let candidateArtist: String?
    /// Second high-confidence line — likely the album title.
    let candidateTitle: String?
}

/// Structured metadata produced by RecordTextParser from an OCRResult.
struct ParsedRecordMetadata {
    let artist: String?
    let artistConfidence: Double   // 0.0 – 1.0

    let title: String?
    let titleConfidence: Double

    let year: Int?
    let yearConfidence: Double

    let label: String?
    let labelConfidence: Double
}

/// Metadata returned by the /v1/records/lookup server endpoint.
struct LookupResult: Decodable {
    let title: String?
    let artist: String?
    let year: Int?
    let genre: String?
    let mbid: String?
    let coverArtUrl: String?
    let confidence: Double?
}
