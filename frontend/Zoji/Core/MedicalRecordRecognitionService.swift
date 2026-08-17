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
        try Task.checkCancellation()
        let cancellation = VisionRequestCancellationBox()
        let recognitionTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let text = try recognizeText(in: imageData, cancellation: cancellation)
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
            cancellation.cancel()
            recognitionTask.cancel()
        }
    }

    nonisolated private static func recognizeText(
        in imageData: Data,
        cancellation: VisionRequestCancellationBox
    ) throws -> String {
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
        guard cancellation.register(request) else { throw CancellationError() }
        defer { cancellation.unregister(request) }
        do {
            try VNImageRequestHandler(data: imageData).perform([request])
        } catch {
            if cancellation.isCancelled || Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }
        if cancellation.isCancelled || Task.isCancelled {
            throw CancellationError()
        }
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
        let labelPattern = "(?:合计|总计|应收|实收|金额|费用|total|amount|paid|cost)[^0-9\\r\\n]{0,12}([0-9][0-9.,'’\\u00A0 ]*)"
        let labelOnlyPattern = "(?:合计|总计|应收|实收|金额|费用|total|amount|paid|cost)\\s*[:：]?[\\p{Sc}]?\\s*$"
        let valuePattern = "^[\\p{Sc}\\s]*([0-9][0-9.,'’\\u00A0 ]*)$"
        guard let labelExpression = try? NSRegularExpression(
            pattern: labelPattern,
            options: .caseInsensitive
        ), let labelOnlyExpression = try? NSRegularExpression(
            pattern: labelOnlyPattern,
            options: .caseInsensitive
        ), let valueExpression = try? NSRegularExpression(pattern: valuePattern) else {
            return nil
        }

        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            if let amount = firstRecognizedAmount(in: line, using: labelExpression) {
                return amount
            }
            guard labelOnlyExpression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            ) != nil, index + 1 < lines.count else {
                continue
            }
            if let amount = firstRecognizedAmount(in: lines[index + 1], using: valueExpression) {
                return amount
            }
        }
        return nil
    }

    private nonisolated static func firstRecognizedAmount(
        in text: String,
        using expression: NSRegularExpression
    ) -> Decimal? {
        guard let match = expression.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ), let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
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

final class VisionRequestCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRequest?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Returns false when cancellation won the race before Vision registered
    /// its request. In that case the caller must not start recognition.
    func register(_ request: VNRequest) -> Bool {
        lock.lock()
        if cancelled {
            lock.unlock()
            request.cancel()
            return false
        }
        self.request = request
        lock.unlock()
        return true
    }

    func unregister(_ request: VNRequest) {
        lock.lock()
        if self.request === request {
            self.request = nil
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let request = request
        lock.unlock()
        request?.cancel()
    }
}
