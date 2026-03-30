import Vision
import UIKit

/// Runs Apple Vision text recognition entirely on-device.
/// The raw photo never leaves the device; only extracted strings are sent to the server.
final class VisionOCRService {

    enum OCRError: LocalizedError {
        case invalidImage
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidImage:          return "Could not read image data"
            case .requestFailed(let m):  return "OCR failed: \(m)"
            }
        }
    }

    // MARK: - Public API

    /// Recognise text in `image` and return a structured OCRResult.
    /// Runs on a background thread; safe to call with `await`.
    func recognizeText(in image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.requestFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResult(rawLines: [], candidateArtist: nil, candidateTitle: nil))
                    return
                }

                let result = Self.buildResult(from: observations)
                continuation.resume(returning: result)
            }

            // .accurate trades a little speed for significantly better results on styled text
            request.recognitionLevel      = .accurate
            request.recognitionLanguages  = ["en-US"]
            request.usesLanguageCorrection = true
            // Minimum confidence — discard near-noise observations
            request.minimumTextHeight = 0.02

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.requestFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Private

    /// Convert Vision observations to OCRResult.
    ///
    /// Sort strategy:
    ///   1. Top-to-bottom by bounding box (natural reading order on a label/cover).
    ///   2. Within a "row" (similar Y), left-to-right.
    ///
    /// VNObservation bounding boxes use a flipped coordinate system: origin at
    /// bottom-left, so *descending* minY = top of image first.
    private static func buildResult(from observations: [VNRecognizedTextObservation]) -> OCRResult {
        // Keep only the top candidate per observation; discard low-confidence hits
        let candidates = observations
            .compactMap { obs -> (text: String, confidence: Float, minY: CGFloat)? in
                guard let top = obs.topCandidates(1).first, top.confidence > 0.3 else { return nil }
                return (top.string, top.confidence, obs.boundingBox.minY)
            }
            // Sort top-to-bottom (descending minY in flipped coords)
            .sorted { $0.minY > $1.minY }

        let rawLines = candidates
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return OCRResult(
            rawLines: rawLines,
            candidateArtist: rawLines.first,
            candidateTitle: rawLines.dropFirst().first
        )
    }
}
