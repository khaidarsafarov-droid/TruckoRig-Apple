import Foundation
import UIKit
import Vision

/// Text recognition for scanned documents.
///
/// Vision handles both Russian and English on-device, which is why there is no Tesseract fallback
/// here: adding a second engine would ship a large binary and a second set of language data for
/// output Vision already produces.
enum OCRService {

    /// Languages tried, most likely first.
    static let languages = ["en-US", "ru-RU"]

    /// Recognised text plus how sure Vision was about it.
    struct Recognition {
        var text: String
        var averageConfidence: Double
    }

    /// Recognises text in `image`. Returns `nil` when nothing legible was found.
    ///
    /// Recognised text is never logged: scans routinely carry names, addresses and rates.
    static func recognizeText(in image: UIImage) async -> Recognition? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    AppLog.media.notice("Text recognition failed")
                    continuation.resume(returning: nil)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                var lines: [String] = []
                var confidences: [Double] = []
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    lines.append(candidate.string)
                    confidences.append(Double(candidate.confidence))
                }

                guard !lines.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let average = confidences.reduce(0, +) / Double(confidences.count)
                continuation.resume(returning: Recognition(text: lines.joined(separator: "\n"), averageConfidence: average))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: image.cgImagePropertyOrientation)
            do {
                try handler.perform([request])
            } catch {
                AppLog.media.notice("Text recognition could not start")
                continuation.resume(returning: nil)
            }
        }
    }

    /// First line that looks like a title, for naming a scan.
    static func suggestedTitle(from text: String) -> String? {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count >= 4 && $0.count <= 48 }
    }
}

extension UIImage {
    /// Vision needs the orientation separately from the CGImage.
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
