import XCTest
import UIKit
import Vision
@testable import Zoji

final class ReminderCalculatorTests: XCTestCase {
    func testThirtyDayIntervalUsesActualCompletionDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let completedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11)))

        let nextDue = ReminderCalculator.nextDueDate(
            after: completedAt,
            scheduleType: .intervalDays,
            intervalValue: 30,
            calendar: calendar
        )

        XCTAssertEqual(nextDue, calendar.date(from: DateComponents(year: 2026, month: 9, day: 10)))
    }

    func testCalendarMonthHandlesMonthEnd() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let completedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31)))

        let nextDue = ReminderCalculator.nextDueDate(
            after: completedAt,
            scheduleType: .calendarMonths,
            intervalValue: 1,
            calendar: calendar
        )

        XCTAssertEqual(nextDue, calendar.date(from: DateComponents(year: 2026, month: 2, day: 28)))
    }

    func testCarePlanCatalogFiltersBySpecies() {
        XCTAssertEqual(CarePlanTemplateCatalog.templates(for: .cat).count, 3)
        XCTAssertEqual(CarePlanTemplateCatalog.templates(for: .dog).count, 3)
        XCTAssertTrue(CarePlanTemplateCatalog.templates(for: .other).isEmpty)
    }

    func testYoungVaccinationTemplateUsesFourWeekIntervals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))
        let template = try XCTUnwrap(CarePlanTemplateCatalog.templates.first { $0.id == "cat-kitten-core-v1" })

        XCTAssertEqual(template.steps[1].dueDate(from: startDate, calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
        XCTAssertEqual(template.steps[2].dueDate(from: startDate, calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 10, day: 7)))
    }

    func testRecurringReminderLocksCompletionUntilNextDueDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let completedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 10)))
        let nextDueAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 10)))
        let reminder = ReminderItem(
            id: UUID(),
            petID: UUID(),
            title: "体内驱虫",
            kind: .internalDeworming,
            dueAt: nextDueAt,
            scheduleType: .intervalDays,
            intervalValue: 30,
            lastCompletedAt: completedAt
        )

        XCTAssertTrue(reminder.isCompletionLocked(
            at: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))),
            calendar: calendar
        ))
        XCTAssertFalse(reminder.isCompletionLocked(
            at: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))),
            calendar: calendar
        ))
    }

    func testLongOverdueReminderRollsNotificationsForwardFromNow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dueAt = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 1, hour: 9)
        ))
        let now = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 12, hour: 12)
        ))
        let reminder = ReminderItem(
            id: UUID(),
            petID: UUID(),
            title: "复诊",
            kind: .medicalVisit,
            dueAt: dueAt,
            advanceDays: [0, 1, 3]
        )

        let candidates = LocalReminderNotificationScheduler.notificationCandidates(
            for: reminder,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(candidates.count, 7)
        XCTAssertTrue(candidates.allSatisfy { $0.alertAt > now })
        XCTAssertEqual(candidates.first?.advanceDay, -12)
        XCTAssertEqual(candidates.last?.advanceDay, -18)
        XCTAssertEqual(
            candidates.first?.alertAt,
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 9))
        )
    }

    func testFutureReminderIncludesAdvanceAndSevenOverdueDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dueAt = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 20, hour: 9)
        ))
        let now = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 12, hour: 12)
        ))
        let reminder = ReminderItem(
            id: UUID(),
            petID: UUID(),
            title: "疫苗",
            kind: .vaccine,
            dueAt: dueAt,
            advanceDays: [0, 1, 3]
        )

        let candidates = LocalReminderNotificationScheduler.notificationCandidates(
            for: reminder,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(candidates.count, 10)
        XCTAssertEqual(Set(candidates.prefix(3).map(\.advanceDay)), Set([3, 1, 0]))
        XCTAssertEqual(Array(candidates.suffix(7).map(\.advanceDay)), [-1, -2, -3, -4, -5, -6, -7])
    }
}

final class AppAppearanceTests: XCTestCase {
    func testAppearanceMapsToExpectedColorScheme() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }
}

final class ZojiBackupTests: XCTestCase {
    func testBackupRoundTripPreservesAttachmentsAndCurrency() throws {
        let petID = UUID()
        let archive = ZojiBackupArchive(
            selectedPetID: petID,
            pets: [Pet(id: petID, name: "团子", species: .cat)],
            records: [
                HealthRecord(
                    id: UUID(),
                    petID: petID,
                    kind: .medicalVisit,
                    title: "复诊",
                    occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    costCents: 9_999,
                    currencyCode: "USD",
                    attachments: [HealthRecordAttachment(data: Data([1, 2, 3]))]
                )
            ],
            reminders: []
        )

        let data = try ZojiBackupDocument.encode(archive)
        let decoded = try ZojiBackupDocument.decode(data)

        XCTAssertEqual(decoded.pets.first?.name, "团子")
        XCTAssertEqual(decoded.records.first?.attachments.first?.data, Data([1, 2, 3]))
        XCTAssertEqual(decoded.records.first?.costCents, 9_999)
        XCTAssertEqual(decoded.records.first?.currencyCode, "USD")
    }

    func testBackupRejectsRecordWithoutPet() {
        let archive = ZojiBackupArchive(
            selectedPetID: nil,
            pets: [],
            records: [
                HealthRecord(
                    id: UUID(),
                    petID: UUID(),
                    kind: .custom,
                    title: "异常记录",
                    occurredAt: Date()
                )
            ],
            reminders: []
        )

        XCTAssertThrowsError(try archive.validate())
    }
}

final class RegionalFormatTests: XCTestCase {
    func testCurrencyMinorUnitsRespectCurrencyPrecision() {
        XCTAssertEqual(RegionalFormat.minorUnits(from: "12.34", code: "USD"), 1_234)
        XCTAssertEqual(RegionalFormat.minorUnits(from: "1200", code: "JPY"), 1_200)
    }

    func testLegacyRecordWithoutCurrencyDecodesAsChineseYuan() throws {
        let record = HealthRecord(
            id: UUID(),
            petID: UUID(),
            kind: .custom,
            title: "旧记录",
            occurredAt: Date(),
            costCents: 8_800
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(HealthRecord.self, from: data)

        XCTAssertNil(decoded.currencyCode)
        XCTAssertEqual(decoded.resolvedCurrencyCode, "CNY")
    }

    func testMalformedCurrencyDoesNotMergeIntoChineseYuan() {
        let record = HealthRecord(
            id: UUID(),
            petID: UUID(),
            kind: .custom,
            title: "Imported",
            occurredAt: Date(),
            costCents: 100,
            currencyCode: "US"
        )

        XCTAssertEqual(record.resolvedCurrencyCode, "XXX")
    }

    func testOccurrenceYearUsesTheTimeZoneCapturedWithTheRecord() throws {
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2025-01-01T00:30:00Z")
        )
        let losAngelesRecord = HealthRecord(
            id: UUID(),
            petID: UUID(),
            kind: .custom,
            title: "New Year's Eve",
            occurredAt: instant,
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let shanghaiRecord = HealthRecord(
            id: UUID(),
            petID: UUID(),
            kind: .custom,
            title: "New Year's Day",
            occurredAt: instant,
            timeZoneIdentifier: "Asia/Shanghai"
        )

        XCTAssertEqual(losAngelesRecord.occurrenceYear(), 2024)
        XCTAssertEqual(shanghaiRecord.occurrenceYear(), 2025)
    }

    func testLegacyRecordWithoutTimeZoneStillDecodes() throws {
        let record = HealthRecord(
            id: UUID(),
            petID: UUID(),
            kind: .custom,
            title: "Legacy",
            occurredAt: Date()
        )
        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "timeZoneIdentifier")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(HealthRecord.self, from: legacyData)
        XCTAssertNil(decoded.timeZoneIdentifier)
    }

    func testMassConversionRoundTripsStoredKilograms() {
        let displayed = RegionalFormat.displayedMass(fromKilograms: 27)

        XCTAssertEqual(
            RegionalFormat.kilograms(fromDisplayedMass: displayed),
            27,
            accuracy: 0.000_001
        )
    }

    func testDisplayedMassComparisonIgnoresEditorRoundTripNoise() {
        let storedKilograms = 28.0
        let displayed = RegionalFormat.displayedMass(fromKilograms: storedKilograms)
        let editorKilograms = RegionalFormat.kilograms(fromDisplayedMass: (displayed * 100).rounded() / 100)

        XCTAssertTrue(RegionalFormat.representsSameDisplayedMass(storedKilograms, editorKilograms))
    }
}

final class MedicalRecordRecognitionTests: XCTestCase {
    func testVisionRequestCancellationBoxHandlesCancellationBeforeRegistration() {
        let cancellation = VisionRequestCancellationBox()
        cancellation.cancel()

        XCTAssertTrue(cancellation.isCancelled)
        XCTAssertFalse(cancellation.register(VNRecognizeTextRequest()))
    }

    func testVisionRequestCancellationBoxTracksCancellationAfterRegistration() {
        let cancellation = VisionRequestCancellationBox()
        let request = VNRecognizeTextRequest()

        XCTAssertTrue(cancellation.register(request))
        cancellation.cancel()
        XCTAssertTrue(cancellation.isCancelled)
        cancellation.unregister(request)
    }

    func testRecognizesUSGroupedAmount() {
        XCTAssertEqual(
            MedicalRecordRecognitionService.detectedCost(in: "Total: 1,234.56"),
            Decimal(string: "1234.56")
        )
    }

    func testRecognizesEuropeanGroupedAmount() {
        XCTAssertEqual(
            MedicalRecordRecognitionService.detectedCost(in: "Amount 1.234,56"),
            Decimal(string: "1234.56")
        )
    }

    func testTreatsThreeTrailingDigitsAsThousands() {
        XCTAssertEqual(
            MedicalRecordRecognitionService.detectedCost(in: "合计 ¥1,234"),
            Decimal(string: "1234")
        )
    }

    func testRecognizesAmountOnImmediatelyFollowingValueLine() {
        XCTAssertEqual(
            MedicalRecordRecognitionService.detectedCost(in: "金额\n¥ 1 200.00"),
            Decimal(string: "1200.00")
        )
    }

    func testDoesNotCrossIntoUnrelatedNumberedLine() {
        XCTAssertNil(
            MedicalRecordRecognitionService.detectedCost(in: "金额说明\n病历编号 1200")
        )
    }
}

final class FamilyPetMergeTests: XCTestCase {
    func testConcurrentWeightAdditionsAreBothPreserved() {
        let petID = UUID()
        let original = WeightEntry(measuredAt: Date(timeIntervalSince1970: 1), kilograms: 10)
        let local = WeightEntry(measuredAt: Date(timeIntervalSince1970: 2), kilograms: 11)
        let remote = WeightEntry(measuredAt: Date(timeIntervalSince1970: 3), kilograms: 12)
        let base = Pet(id: petID, name: "豆豆", species: .dog, weightKilograms: 10, weightEntries: [original])
        let desired = Pet(id: petID, name: "豆豆", species: .dog, weightKilograms: 11, weightEntries: [original, local])
        let server = Pet(id: petID, name: "豆豆", species: .dog, weightKilograms: 12, weightEntries: [original, remote])

        let merged = FamilySharingService.mergingPetChange(server: server, desired: desired, base: base)

        XCTAssertEqual(Set(merged.sortedWeightEntries.map(\.id)), Set([original.id, local.id, remote.id]))
        XCTAssertEqual(merged.weightKilograms, 12)
    }

    func testLocalWeightDeletionDoesNotDeleteConcurrentRemoteAddition() {
        let petID = UUID()
        let deleted = WeightEntry(measuredAt: Date(timeIntervalSince1970: 1), kilograms: 10)
        let remote = WeightEntry(measuredAt: Date(timeIntervalSince1970: 2), kilograms: 12)
        let base = Pet(id: petID, name: "豆豆", species: .dog, weightKilograms: 10, weightEntries: [deleted])
        let desired = Pet(id: petID, name: "豆豆", species: .dog, weightEntries: [])
        let server = Pet(id: petID, name: "豆豆", species: .dog, weightKilograms: 12, weightEntries: [deleted, remote])

        let merged = FamilySharingService.mergingPetChange(server: server, desired: desired, base: base)

        XCTAssertEqual(merged.sortedWeightEntries.map(\.id), [remote.id])
    }

    func testRecordTitleEditPreservesConcurrentAttachmentAddition() {
        let petID = UUID()
        let originalAttachment = HealthRecordAttachment(id: UUID(), data: Data([1]))
        let remoteAttachment = HealthRecordAttachment(id: UUID(), data: Data([2]))
        let base = HealthRecord(
            id: UUID(),
            petID: petID,
            kind: .medicalVisit,
            title: "复诊",
            occurredAt: Date(timeIntervalSince1970: 1),
            attachments: [originalAttachment]
        )
        var desired = base
        desired.title = "复诊结果"
        var server = base
        server.attachments.append(remoteAttachment)

        let merged = FamilySharingService.mergingHealthRecordChange(
            server: server,
            desired: desired,
            base: base
        )

        XCTAssertEqual(merged.title, "复诊结果")
        XCTAssertEqual(Set(merged.attachments.map(\.id)), Set([originalAttachment.id, remoteAttachment.id]))
    }

    func testRecordAttachmentDeletionPreservesConcurrentRemoteAddition() {
        let petID = UUID()
        let deletedAttachment = HealthRecordAttachment(id: UUID(), data: Data([1]))
        let remoteAttachment = HealthRecordAttachment(id: UUID(), data: Data([2]))
        let base = HealthRecord(
            id: UUID(),
            petID: petID,
            kind: .medicalVisit,
            title: "复诊",
            occurredAt: Date(timeIntervalSince1970: 1),
            attachments: [deletedAttachment]
        )
        var desired = base
        desired.attachments = []
        var server = base
        server.attachments.append(remoteAttachment)

        let merged = FamilySharingService.mergingHealthRecordChange(
            server: server,
            desired: desired,
            base: base
        )

        XCTAssertEqual(merged.attachments.map(\.id), [remoteAttachment.id])
    }

    func testReminderTitleEditPreservesConcurrentCompletion() {
        let petID = UUID()
        let originalDueAt = Date(timeIntervalSince1970: 1_700_000_000)
        let nextDueAt = Date(timeIntervalSince1970: 1_702_592_000)
        let completedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let base = ReminderItem(
            id: UUID(),
            petID: petID,
            title: "体内驱虫",
            kind: .internalDeworming,
            dueAt: originalDueAt,
            scheduleType: .intervalDays,
            intervalValue: 30
        )
        var desired = base
        desired.title = "每月体内驱虫"
        var server = base
        server.dueAt = nextDueAt
        server.lastCompletedAt = completedAt

        let merged = FamilySharingService.mergingReminderChange(
            server: server,
            desired: desired,
            base: base
        )

        XCTAssertEqual(merged.title, "每月体内驱虫")
        XCTAssertEqual(merged.dueAt, nextDueAt)
        XCTAssertEqual(merged.lastCompletedAt, completedAt)
    }
}

final class FamilyPendingQueueStorageTests: XCTestCase {
    func testQueueExternalizesAttachmentBytesAndRestoresThem() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoji-family-queue-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let attachmentData = Data(repeating: 0xA5, count: 1_000_000)
        let record = makeRecord(attachmentData: attachmentData)
        let change = FamilyPendingChange.save(record, at: makeLocation())
        let store = FamilySharingLocalStore(directory: directory)

        try await store.enqueue(change)

        let pendingData = try Data(contentsOf: directory.appendingPathComponent("pending-changes.plist"))
        XCTAssertLessThan(pendingData.count, 50_000)
        XCTAssertEqual(regularFiles(in: directory.appendingPathComponent("pending-attachment-blobs")).count, 1)

        let reloadedStore = FamilySharingLocalStore(directory: directory)
        let restored = try await reloadedStore.allPendingChanges()
        XCTAssertEqual(restored.first?.healthRecord?.attachments.first?.data, attachmentData)

        try await reloadedStore.markCompleted(change.id)
        XCTAssertTrue(regularFiles(in: directory.appendingPathComponent("pending-attachment-blobs")).isEmpty)
    }

    func testLegacyInlineAttachmentQueueMigratesOnFirstLoad() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoji-family-legacy-queue-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let attachmentData = Data(repeating: 0x5A, count: 500_000)
        let change = FamilyPendingChange.save(
            makeRecord(attachmentData: attachmentData),
            at: makeLocation()
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode([change]).write(
            to: directory.appendingPathComponent("pending-changes.plist"),
            options: .atomic
        )

        let store = FamilySharingLocalStore(directory: directory)
        let restored = try await store.allPendingChanges()
        XCTAssertEqual(restored.first?.healthRecord?.attachments.first?.data, attachmentData)

        let migratedData = try Data(contentsOf: directory.appendingPathComponent("pending-changes.plist"))
        let storedChanges = try PropertyListDecoder().decode([FamilyPendingChange].self, from: migratedData)
        XCTAssertEqual(storedChanges.first?.attachmentStorageVersion, 1)
        XCTAssertEqual(storedChanges.first?.healthRecord?.attachments.first?.data, Data())
        XCTAssertLessThan(migratedData.count, 50_000)
        XCTAssertEqual(regularFiles(in: directory.appendingPathComponent("pending-attachment-blobs")).count, 1)
    }

    func testMissingAttachmentSidecarFailsInsteadOfRestoringEmptyData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoji-family-missing-blob-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FamilySharingLocalStore(directory: directory)
        try await store.enqueue(.save(
            makeRecord(attachmentData: Data(repeating: 0x11, count: 128_000)),
            at: makeLocation()
        ))
        let blob = try XCTUnwrap(
            regularFiles(in: directory.appendingPathComponent("pending-attachment-blobs")).first
        )
        try FileManager.default.removeItem(at: blob)

        let reloadedStore = FamilySharingLocalStore(directory: directory)
        do {
            _ = try await reloadedStore.allPendingChanges()
            XCTFail("A queue with a missing attachment blob must not load as an empty attachment.")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
    }

    private func makeRecord(attachmentData: Data) -> HealthRecord {
        HealthRecord(
            id: UUID(),
            petID: UUID(),
            kind: .medicalVisit,
            title: "复诊",
            occurredAt: Date(),
            attachments: [HealthRecordAttachment(data: attachmentData)]
        )
    }

    private func makeLocation() -> FamilyShareLocation {
        FamilyShareLocation(
            zoneName: "ZojiPet_Test",
            zoneOwnerName: "owner",
            databaseScope: .ownerPrivate
        )
    }

    private func regularFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }
}

final class HealthRecordAttachmentPolicyTests: XCTestCase {
    func testAdditionRejectsCountIndividualSizeAndAggregateSize() {
        XCTAssertThrowsError(try HealthRecordAttachmentPolicy.validateAddition(
            kind: .image,
            byteCount: 1,
            currentCount: HealthRecordAttachmentPolicy.maximumCount,
            currentBytes: 0
        )) { error in
            XCTAssertEqual(error as? HealthRecordAttachmentValidationError, .tooManyAttachments)
        }

        XCTAssertThrowsError(try HealthRecordAttachmentPolicy.validateAddition(
            kind: .pdf,
            byteCount: HealthRecordAttachmentPolicy.maximumPDFBytes + 1,
            currentCount: 0,
            currentBytes: 0
        )) { error in
            XCTAssertEqual(error as? HealthRecordAttachmentValidationError, .pdfTooLarge)
        }

        XCTAssertThrowsError(try HealthRecordAttachmentPolicy.validateAddition(
            kind: .image,
            byteCount: 2,
            currentCount: 1,
            currentBytes: HealthRecordAttachmentPolicy.maximumTotalBytes - 1
        )) { error in
            XCTAssertEqual(error as? HealthRecordAttachmentValidationError, .totalTooLarge)
        }
    }

    func testImageProcessorDownsamplesAndCompressesForCloudStorage() throws {
        let sourceSize = CGSize(width: 3_000, height: 2_000)
        let renderer = UIGraphicsImageRenderer(size: sourceSize)
        let sourceImage = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: sourceSize))
            UIColor.white.setStroke()
            context.cgContext.setLineWidth(18)
            for offset in stride(from: 0, through: 3_000, by: 120) {
                context.cgContext.move(to: CGPoint(x: offset, y: 0))
                context.cgContext.addLine(to: CGPoint(x: 3_000 - offset, y: 2_000))
            }
            context.cgContext.strokePath()
        }
        let sourceData = try XCTUnwrap(sourceImage.pngData())

        let processed = try HealthRecordEditorView.processCaseImage(sourceData)
        let resultImage = try XCTUnwrap(UIImage(data: processed.data))

        XCTAssertLessThanOrEqual(
            max(resultImage.size.width, resultImage.size.height),
            CGFloat(HealthRecordAttachmentPolicy.maximumImageDimension)
        )
        XCTAssertLessThanOrEqual(
            processed.data.count,
            HealthRecordAttachmentPolicy.preferredStoredImageBytes
        )
        XCTAssertEqual(processed.sourceByteCount, sourceData.count)
    }

    func testByteCountFormattingIsUserReadable() {
        let formatted = HealthRecordAttachmentPolicy.formattedByteCount(2_500_000)
        XCTAssertTrue(formatted.contains("MB") || formatted.contains("兆"))
    }
}
