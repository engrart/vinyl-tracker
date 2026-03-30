import Foundation
import Combine

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case notFound
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:                 return "Invalid URL"
        case .unauthorized:               return "Session expired — please sign in again"
        case .notFound:                   return "Record not found"
        case .serverError(let c, let m):  return "Server error \(c): \(m)"
        case .decodingError(let e):       return "Response parse error: \(e.localizedDescription)"
        case .networkError(let e):        return e.localizedDescription
        }
    }
}

// MARK: - Response wrappers

private struct RecordsEnvelope: Decodable {
    let records: [Record]
}

private struct Empty: Decodable {}

// MARK: - APIClient

/// Thin async/await wrapper around URLSession.
/// Inject `authToken` after the user signs in (Clerk / Auth0 access token).
@MainActor
final class APIClient: ObservableObject {

    static let shared = APIClient()

    nonisolated let objectWillChange = ObservableObjectPublisher()

    /// Set this after Clerk/Auth0 delivers an access token.
    var authToken: String?

    private let baseURL: String
    private let decoder: JSONDecoder

    private init() {
        // API_BASE_URL is set in Info.plist via a build configuration.
        // Fallback to localhost for simulator development.
        self.baseURL = (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "http://localhost:3000/v1"

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy  = .convertFromSnakeCase
    }

    // MARK: - Records

    func fetchRecords(search: String? = nil, genre: String? = nil) async throws -> [Record] {
        var comps = URLComponents(string: baseURL + "/records")!
        var items: [URLQueryItem] = []
        if let s = search, !s.isEmpty { items.append(.init(name: "search", value: s)) }
        if let g = genre,  !g.isEmpty { items.append(.init(name: "genre",  value: g)) }
        if !items.isEmpty { comps.queryItems = items }

        let req = try makeRequest(.GET, url: comps.url!)
        let env: RecordsEnvelope = try await perform(req)
        return env.records
    }

    func fetchRecord(id: String) async throws -> Record {
        let req = try makeRequest(.GET, path: "/records/\(id)")
        return try await perform(req)
    }

    func createRecord(_ payload: RecordPayload) async throws -> Record {
        var req = try makeRequest(.POST, path: "/records")
        req.httpBody = try JSONEncoder().encode(payload)
        return try await perform(req)
    }

    func updateRecord(id: String, _ payload: RecordPayload) async throws -> Record {
        var req = try makeRequest(.PUT, path: "/records/\(id)")
        req.httpBody = try JSONEncoder().encode(payload)
        return try await perform(req)
    }

    func deleteRecord(id: String) async throws {
        let req = try makeRequest(.DELETE, path: "/records/\(id)")
        let _: Empty = try await perform(req)
    }

    /// POST /v1/records/lookup — send OCR-extracted strings, receive structured metadata.
    func lookup(artist: String?, title: String?) async throws -> LookupResult {
        struct Body: Encodable { let artist: String?; let title: String? }
        var req = try makeRequest(.POST, path: "/records/lookup")
        req.httpBody = try JSONEncoder().encode(Body(artist: artist, title: title))
        return try await perform(req)
    }

    /// Upload a JPEG photo as multipart/form-data.
    func uploadImage(recordId: String, imageData: Data, imageType: String, isPrimary: Bool = false) async throws -> RecordImage {
        guard let url = URL(string: baseURL + "/records/\(recordId)/images") else {
            throw APIError.invalidURL
        }

        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"record.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        append("\r\n")

        for (name, value) in [("image_type", imageType), ("is_primary", isPrimary ? "true" : "false")] {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)--\r\n")
        req.httpBody = body

        return try await perform(req)
    }

    // MARK: - HTTP helpers

    private enum Method: String { case GET, POST, PUT, DELETE }

    private func makeRequest(_ method: Method, path: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        return try makeRequest(method, url: url)
    }

    private func makeRequest(_ method: Method, url: URL) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200..<300:
            if T.self == Empty.self { return Empty() as! T }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default:
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(http.statusCode, msg)
        }
    }
}
