import Foundation
import Vision

struct MedicalRecordRecognitionResult: Sendable {
    let text: String
    let suggestedTitle: String?
    let suggestedProvider: String?
    let suggestedCost: String?
}

enum MedicalRecordRecognitionService {
    static func recognize(imageData: Data) async throws -> MedicalRecordRecognitionResult {
        try await Task.detached(priority: .userInitiated) {
            let text = try recognizeText(in: imageData)
            return MedicalRecordRecognitionResult(
                text: text,
                suggestedTitle: firstValue(
                    after: ["初步诊断", "诊断", "主诉", "Diagnosis", "Chief Complaint"],
                    in: text
                ),
                suggestedProvider: detectProvider(in: text),
                suggestedCost: detectCost(in: text)
            )
        }.value
    }

    nonisolated private static func recognizeText(in imageData: Data) throws -> String {
        var recognizedLines: [String] = []
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation]
            else { return }
            recognizedLines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(data: imageData).perform([request])
        return recognizedLines.joined(separator: "\n")
    }

    nonisolated private static func firstValue(after labels: [String], in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            for label in labels where line.localizedCaseInsensitiveContains(label) {
                let range = line.range(of: label, options: .caseInsensitive)
                let value = range.map { String(line[$0.upperBound...]) } ?? line
                let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: ":： -"))
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    nonisolated private static func detectProvider(in text: String) -> String? {
        let providerTerms = ["医院", "诊所", "医疗中心", "hospital", "clinic", "medical center"]
        return text.components(separatedBy: .newlines).first { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count <= 60
                && providerTerms.contains { trimmed.localizedCaseInsensitiveContains($0) }
        }?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func detectCost(in text: String) -> String? {
        let pattern = "(?:合计|总计|应收|实收|金额|费用|total|amount|paid|cost)[^0-9]{0,12}([0-9]+(?:[.,][0-9]{1,2})?)"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range]).replacingOccurrences(of: ",", with: ".")
    }
}
