import Foundation
import Vision

struct MedicalRecordRecognitionResult: Sendable {
    let text: String
    let suggestedTitle: String?
    let suggestedProvider: String?
    let suggestedCost: Decimal?
}

enum MedicalRecordRecognitionService {
    static func recognize(imageData: Data) async throws -> MedicalRecordRecognitionResult {
        let recognitionTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let text = try recognizeText(in: imageData)
            try Task.checkCancellation()
            return MedicalRecordRecognitionResult(
                text: text,
                suggestedTitle: firstValue(
                    after: ["初步诊断", "诊断", "主诉", "Diagnosis", "Chief Complaint"],
                    in: text
                ),
                suggestedProvider: detectProvider(in: text),
                suggestedCost: detectedCost(in: text)
            )
        }
        return try await withTaskCancellationHandler {
            try await recognitionTask.value
        } onCancel: {
            recognitionTask.cancel()
        }
    }

    nonisolated private static func recognizeText(in imageData: Data) throws -> String {
        var recognizedLines: [String] = []
        var recognitionError: Error?
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                recognitionError = error
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            recognizedLines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(data: imageData).perform([request])
        if let recognitionError { throw recognitionError }
        try Task.checkCancellation()
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

    nonisolated static func detectedCost(in text: String) -> Decimal? {
        let pattern = "(?:合计|总计|应收|实收|金额|费用|total|amount|paid|cost)[^0-9]{0,12}([0-9][0-9.,'’\\u00A0 ]*)"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return parseRecognizedAmount(String(text[range]))
    }

    nonisolated static func parseRecognizedAmount(_ rawValue: String) -> Decimal? {
        let value = rawValue.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard value.contains(where: \.isNumber) else { return nil }

        let separators = value.indices.filter { value[$0] == "," || value[$0] == "." }
        let decimalIndex: String.Index? = separators.last.flatMap { index in
            let fractionDigits = value[value.index(after: index)...].filter(\.isNumber).count
            return (1 ... 2).contains(fractionDigits) ? index : nil
        }

        let integerPart: String
        let fractionPart: String
        if let decimalIndex {
            integerPart = String(value[..<decimalIndex].filter(\.isNumber))
            fractionPart = String(value[value.index(after: decimalIndex)...].filter(\.isNumber))
        } else {
            integerPart = String(value.filter(\.isNumber))
            fractionPart = ""
        }
        guard !integerPart.isEmpty else { return nil }
        let canonical = fractionPart.isEmpty ? integerPart : "\(integerPart).\(fractionPart)"
        return Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX"))
    }
}
