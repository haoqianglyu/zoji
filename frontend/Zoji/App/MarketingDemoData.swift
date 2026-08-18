#if DEBUG
import Foundation
import MapKit
import SwiftData
import UIKit

/// Deterministic, fictional data for App Store screenshots.
///
/// This runs only in Debug builds with `-zojiMarketingDemo`. The matching
/// persistence configuration is in-memory, so none of these fixtures can be
/// written to the developer's CloudKit container or shipped to users.
@MainActor
enum MarketingDemoData {
    static func installIfRequested(in container: ModelContainer) {
        guard PersistenceController.isMarketingDemo else { return }

        UserDefaults.standard.set(true, forKey: AppPrivacyConsent.storageKey)
        UserDefaults.standard.set(AppColorTheme.mint.rawValue, forKey: AppColorTheme.storageKey)
        UserDefaults.standard.set(AppAppearance.light.rawValue, forKey: AppAppearance.storageKey)
        UserDefaults.standard.set(
            L10n.usesEnglish ? AppUnitSystem.us.rawValue : AppUnitSystem.metric.rawValue,
            forKey: AppUnitSystem.storageKey
        )

        let context = ModelContext(container)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        let huhuID = uuid("B0C2F7A3-2E88-4F7C-9404-7C811914E001")
        let zhazhaID = uuid("B0C2F7A3-2E88-4F7C-9404-7C811914E002")

        let huhu = PetEntity(
            id: huhuID,
            ownerID: PrivateDataScope.ownerID,
            name: localized(chinese: "呼呼", english: "Mochi"),
            species: .cat
        )
        huhu.breed = localized(chinese: "英国短毛猫", english: "British Shorthair")
        huhu.avatarPresetID = "cat-british-shorthair"
        huhu.sexRawValue = PetSex.female.rawValue
        huhu.birthday = calendar.date(byAdding: .year, value: -3, to: today)
        huhu.weightKilograms = 5.2
        huhu.weightHistoryData = try? JSONEncoder().encode([
            WeightEntry(measuredAt: calendar.date(byAdding: .month, value: -5, to: today)!, kilograms: 4.7),
            WeightEntry(measuredAt: calendar.date(byAdding: .month, value: -3, to: today)!, kilograms: 4.9),
            WeightEntry(measuredAt: calendar.date(byAdding: .month, value: -1, to: today)!, kilograms: 5.1),
            WeightEntry(measuredAt: today, kilograms: 5.2)
        ])
        huhu.profileStatusRawValue = PetProfileStatus.active.rawValue

        let zhazha = PetEntity(
            id: zhazhaID,
            ownerID: PrivateDataScope.ownerID,
            name: localized(chinese: "扎扎", english: "Biscuit"),
            species: .dog
        )
        zhazha.breed = localized(chinese: "贵宾犬", english: "Toy Poodle")
        zhazha.avatarPresetID = "dog-toy-poodle"
        zhazha.sexRawValue = PetSex.male.rawValue
        zhazha.birthday = calendar.date(byAdding: .year, value: -2, to: today)
        zhazha.weightKilograms = 4.6
        zhazha.profileStatusRawValue = PetProfileStatus.active.rawValue

        [huhu, zhazha].forEach(context.insert)

        let records: [(UUID, RecordKind, String, Int, String?, Int?)] = [
            (uuid("C0C2F7A3-2E88-4F7C-9404-7C811914E001"), .vaccine, localized(chinese: "疫苗接种", english: "Vaccination"), -1, localized(chinese: "安心宠物医院", english: "Cedar Veterinary Center"), 32000),
            (uuid("C0C2F7A3-2E88-4F7C-9404-7C811914E002"), .internalDeworming, localized(chinese: "体内驱虫", english: "Internal Deworming"), -32, nil, 8500),
            (uuid("C0C2F7A3-2E88-4F7C-9404-7C811914E003"), .medicalVisit, localized(chinese: "年度健康检查", english: "Annual Wellness Exam"), -74, localized(chinese: "安心宠物医院", english: "Cedar Veterinary Center"), 26000),
            (uuid("C0C2F7A3-2E88-4F7C-9404-7C811914E004"), .life, localized(chinese: "第一次去海边", english: "First Beach Day"), -9, nil, nil)
        ]
        for (id, kind, title, dayOffset, provider, cost) in records {
            let record = HealthRecordEntity(
                id: id,
                petID: huhuID,
                kind: kind,
                title: title,
                occurredAt: calendar.date(byAdding: .day, value: dayOffset, to: today)!
            )
            record.providerName = provider
            record.costCents = cost
            record.currencyCode = cost == nil ? nil : (L10n.usesEnglish ? "USD" : "CNY")
            record.timeZoneIdentifier = L10n.usesEnglish ? "America/Los_Angeles" : "Asia/Shanghai"
            record.notes = kind == .life
                ? localized(
                    chinese: "海风很舒服，呼呼第一次踩沙滩。",
                    english: "A breezy afternoon and Mochi's first walk on the sand."
                )
                : nil
            context.insert(record)
        }

        let reminders: [(UUID, RecordKind, String, Int, ScheduleType, Int?)] = [
            (uuid("D0C2F7A3-2E88-4F7C-9404-7C811914E001"), .vaccine, localized(chinese: "疫苗加强针", english: "Vaccine Booster"), 1, .calendarYears, 1),
            (uuid("D0C2F7A3-2E88-4F7C-9404-7C811914E002"), .internalDeworming, localized(chinese: "体内驱虫", english: "Internal Deworming"), 4, .intervalDays, 90),
            (uuid("D0C2F7A3-2E88-4F7C-9404-7C811914E003"), .bathGrooming, localized(chinese: "洗澡护理", english: "Bath & Grooming"), 6, .intervalDays, 30)
        ]
        for (id, kind, title, dayOffset, schedule, interval) in reminders {
            let reminder = ReminderRuleEntity(
                id: id,
                petID: huhuID,
                kind: kind,
                scheduleType: schedule,
                dueAt: calendar.date(byAdding: .day, value: dayOffset, to: today)!
            )
            reminder.title = title
            reminder.intervalValue = interval
            reminder.advanceDays = [3, 1, 0]
            context.insert(reminder)
        }

        try? context.save()
    }

    static func makeFamilySharingStore() -> FamilySharingStore {
        guard PersistenceController.isMarketingDemo else {
            return FamilySharingStore()
        }

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let ownedPetID = uuid("B0C2F7A3-2E88-4F7C-9404-7C811914E001")
        let ownedPet = Pet(
            id: ownedPetID,
            name: localized(chinese: "呼呼", english: "Mochi"),
            species: .cat,
            breed: localized(chinese: "英国短毛猫", english: "British Shorthair"),
            avatarPresetID: "cat-british-shorthair",
            sex: .female,
            birthday: calendar.date(byAdding: .year, value: -3, to: today),
            weightKilograms: 5.2,
            profileStatus: .active
        )
        let ownedMembers = [
            FamilyShareMember(
                id: "marketing-owner",
                personID: "marketing-owner",
                displayName: localized(chinese: "我", english: "Me"),
                accountIdentifier: nil,
                role: .owner,
                status: .accepted,
                isCurrentUser: true
            ),
            FamilyShareMember(
                id: "marketing-caregiver",
                personID: "marketing-caregiver",
                displayName: localized(chinese: "小雨", english: "Alex"),
                accountIdentifier: nil,
                role: .editor,
                status: .accepted,
                isCurrentUser: false
            )
        ]
        let ownedSharedPet = FamilySharedPet(
            location: FamilyShareLocation(
                zoneName: "marketing-family-huhu",
                zoneOwnerName: "marketing-owner",
                databaseScope: .ownerPrivate
            ),
            ownerName: localized(chinese: "我", english: "Me"),
            role: .owner,
            payload: FamilyPetSharePayload(
                exportedAt: today,
                pet: ownedPet,
                records: [],
                reminders: []
            ),
            members: ownedMembers
        )

        let receivedPetID = uuid("B0C2F7A3-2E88-4F7C-9404-7C811914E004")
        let receivedPet = Pet(
            id: receivedPetID,
            name: localized(chinese: "哈基米", english: "Hachi"),
            species: .dog,
            breed: localized(chinese: "柴犬", english: "Shiba Inu"),
            avatarPresetID: "dog-shiba-inu",
            sex: .male,
            birthday: calendar.date(byAdding: .year, value: -3, to: today),
            weightKilograms: 9.4,
            weightEntries: [
                WeightEntry(
                    id: uuid("F0C2F7A3-2E88-4F7C-9404-7C811914E001"),
                    measuredAt: calendar.date(byAdding: .month, value: -5, to: today)!,
                    kilograms: 8.8
                ),
                WeightEntry(
                    id: uuid("F0C2F7A3-2E88-4F7C-9404-7C811914E002"),
                    measuredAt: calendar.date(byAdding: .month, value: -2, to: today)!,
                    kilograms: 9.1
                ),
                WeightEntry(
                    id: uuid("F0C2F7A3-2E88-4F7C-9404-7C811914E003"),
                    measuredAt: today,
                    kilograms: 9.4
                )
            ],
            profileStatus: .active
        )
        let receivedRecords = [
            HealthRecord(
                id: uuid("C0C2F7A3-2E88-4F7C-9404-7C811914E001"),
                petID: receivedPetID,
                kind: .vaccine,
                title: localized(chinese: "疫苗接种", english: "Vaccination"),
                occurredAt: calendar.date(byAdding: .day, value: -1, to: today)!,
                providerName: localized(chinese: "安心宠物医院", english: "Cedar Veterinary Center"),
                costCents: 32000,
                currencyCode: L10n.usesEnglish ? "USD" : "CNY",
                timeZoneIdentifier: L10n.usesEnglish ? "America/Los_Angeles" : "Asia/Shanghai",
                attachments: [
                    vaccinationCertificateAttachment(
                        petName: receivedPet.name,
                        clinicName: localized(
                            chinese: "安心宠物医院",
                            english: "Cedar Veterinary Center"
                        ),
                        occurredAt: calendar.date(byAdding: .day, value: -1, to: today)!
                    )
                ]
            ),
            HealthRecord(
                id: uuid("C0C2F7A3-2E88-4F7C-9404-7C811914E002"),
                petID: receivedPetID,
                kind: .internalDeworming,
                title: localized(chinese: "体内驱虫", english: "Internal Deworming"),
                occurredAt: calendar.date(byAdding: .day, value: -32, to: today)!,
                costCents: 8500,
                currencyCode: L10n.usesEnglish ? "USD" : "CNY",
                timeZoneIdentifier: L10n.usesEnglish ? "America/Los_Angeles" : "Asia/Shanghai"
            ),
            HealthRecord(
                id: uuid("C0C2F7A3-2E88-4F7C-9404-7C811914E003"),
                petID: receivedPetID,
                kind: .medicalVisit,
                title: localized(chinese: "年度健康检查", english: "Annual Wellness Exam"),
                occurredAt: calendar.date(byAdding: .day, value: -74, to: today)!,
                providerName: localized(chinese: "安心宠物医院", english: "Cedar Veterinary Center"),
                costCents: 26000,
                currencyCode: L10n.usesEnglish ? "USD" : "CNY",
                timeZoneIdentifier: L10n.usesEnglish ? "America/Los_Angeles" : "Asia/Shanghai"
            ),
            HealthRecord(
                id: uuid("C0C2F7A3-2E88-4F7C-9404-7C811914E004"),
                petID: receivedPetID,
                kind: .life,
                title: localized(chinese: "第一次去海边", english: "First Beach Day"),
                occurredAt: calendar.date(byAdding: .day, value: -9, to: today)!,
                notes: localized(
                    chinese: "海风很舒服，哈基米第一次踩沙滩。",
                    english: "A breezy afternoon and Hachi's first walk on the sand."
                )
            )
        ]
        let receivedReminders = [
            ReminderItem(
                id: uuid("D0C2F7A3-2E88-4F7C-9404-7C811914E001"),
                petID: receivedPetID,
                title: localized(chinese: "疫苗加强针", english: "Vaccine Booster"),
                kind: .vaccine,
                dueAt: calendar.date(byAdding: .day, value: 1, to: today)!,
                scheduleType: .calendarYears,
                intervalValue: 1,
                advanceDays: [3, 1, 0]
            ),
            ReminderItem(
                id: uuid("D0C2F7A3-2E88-4F7C-9404-7C811914E002"),
                petID: receivedPetID,
                title: localized(chinese: "体内驱虫", english: "Internal Deworming"),
                kind: .internalDeworming,
                dueAt: calendar.date(byAdding: .day, value: 4, to: today)!,
                scheduleType: .intervalDays,
                intervalValue: 90,
                advanceDays: [3, 1, 0]
            ),
            ReminderItem(
                id: uuid("D0C2F7A3-2E88-4F7C-9404-7C811914E003"),
                petID: receivedPetID,
                title: localized(chinese: "洗澡护理", english: "Bath & Grooming"),
                kind: .bathGrooming,
                dueAt: calendar.date(byAdding: .day, value: 6, to: today)!,
                scheduleType: .intervalDays,
                intervalValue: 30,
                advanceDays: [3, 1, 0]
            )
        ]
        let receivedSharedPet = FamilySharedPet(
            location: FamilyShareLocation(
                zoneName: "marketing-family-hachi",
                zoneOwnerName: "marketing-caregiver",
                databaseScope: .shared
            ),
            ownerName: localized(chinese: "小雨", english: "Alex"),
            role: .editor,
            payload: FamilyPetSharePayload(
                exportedAt: today,
                pet: receivedPet,
                records: receivedRecords,
                reminders: receivedReminders
            ),
            members: [
                FamilyShareMember(
                    id: "marketing-caregiver",
                    personID: "marketing-caregiver",
                    displayName: localized(chinese: "小雨", english: "Alex"),
                    accountIdentifier: nil,
                    role: .owner,
                    status: .accepted,
                    isCurrentUser: false
                ),
                FamilyShareMember(
                    id: "marketing-viewer",
                    personID: "marketing-viewer",
                    displayName: localized(chinese: "我", english: "Me"),
                    accountIdentifier: nil,
                    role: .editor,
                    status: .accepted,
                    isCurrentUser: true
                )
            ]
        )

        let store = FamilySharingStore(restoredSharedPets: [])
        store.sharedPets = [receivedSharedPet]
        store.ownedSharedPets = [ownedSharedPet]
        // Populate after init so launch-selection resolution treats this as an
        // intentional screenshot choice rather than a cache auto-selection.
        store.selectedSharedPetID = receivedSharedPet.id
        store.recentActivities = [
            FamilyShareActivity(
                id: uuid("E0C2F7A3-2E88-4F7C-9404-7C811914E001"),
                petID: receivedPetID,
                petName: receivedPet.name,
                memberName: localized(chinese: "小雨", english: "Alex"),
                kind: .joined,
                occurredAt: calendar.date(byAdding: .day, value: -2, to: today)!,
                isAcknowledged: true,
                notificationDelivered: true
            )
        ]
        return store
    }

    static let usHospitalRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.6166, longitude: -122.3325),
        span: MKCoordinateSpan(latitudeDelta: 0.075, longitudeDelta: 0.075)
    )

    /// Stable screenshot pins rendered on Apple's MapKit map around Seattle.
    /// The names are deliberately fictional so marketing data never implies a
    /// relationship with, or availability at, a real veterinary practice.
    static let usHospitals: [HospitalSummary] = [
        HospitalSummary(
            id: "marketing-us-vet-1",
            source: .mapKit,
            name: "Cedar Veterinary Center",
            address: "Capitol Hill, Seattle, WA",
            latitude: 47.6233,
            longitude: -122.3197,
            distanceMeters: 1200,
            phoneNumber: "+1 206 555 0132"
        ),
        HospitalSummary(
            id: "marketing-us-vet-2",
            source: .mapKit,
            name: "Lakeview Animal Hospital",
            address: "South Lake Union, Seattle, WA",
            latitude: 47.6202,
            longitude: -122.3371,
            distanceMeters: 1900,
            phoneNumber: "+1 206 555 0178"
        ),
        HospitalSummary(
            id: "marketing-us-vet-3",
            source: .mapKit,
            name: "Rainier Pet Clinic",
            address: "First Hill, Seattle, WA",
            latitude: 47.6092,
            longitude: -122.3251,
            distanceMeters: 2700
        )
    ]

    private static func vaccinationCertificateAttachment(
        petName: String,
        clinicName: String,
        occurredAt: Date
    ) -> HealthRecordAttachment {
        // Keep the sample certificate square so the attachment grid can show
        // the entire document without cropping either localized version.
        let size = CGSize(width: 800, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        let imageData = renderer.jpegData(withCompressionQuality: 0.88) { rendererContext in
            let context = rendererContext.cgContext
            context.setFillColor(UIColor(red: 0.96, green: 0.94, blue: 0.86, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: size))

            context.setStrokeColor(UIColor(red: 0.18, green: 0.48, blue: 0.44, alpha: 1).cgColor)
            context.setLineWidth(8)
            context.stroke(CGRect(x: 34, y: 34, width: size.width - 68, height: size.height - 68))

            let title = localized(chinese: "宠物疫苗接种凭证", english: "PET VACCINATION CERTIFICATE")
            let subtitle = localized(chinese: "演示附件 · 非真实医疗文件", english: "SAMPLE ATTACHMENT · NOT A MEDICAL DOCUMENT")
            let dateText = occurredAt.formatted(
                .dateTime.year().month(.wide).day().locale(L10n.locale)
            )
            let rows = [
                localized(chinese: "宠物：\(petName)", english: "Pet: \(petName)"),
                localized(chinese: "项目：核心疫苗加强针", english: "Service: Core Vaccine Booster"),
                localized(chinese: "日期：\(dateText)", english: "Date: \(dateText)"),
                localized(chinese: "机构：\(clinicName)", english: "Clinic: \(clinicName)")
            ]

            let titleStyle: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: L10n.usesEnglish ? 32 : 40, weight: .bold),
                .foregroundColor: UIColor(red: 0.12, green: 0.34, blue: 0.31, alpha: 1)
            ]
            let subtitleStyle: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: UIColor(red: 0.42, green: 0.46, blue: 0.43, alpha: 1)
            ]
            let rowStyle: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 25, weight: .medium),
                .foregroundColor: UIColor(red: 0.14, green: 0.18, blue: 0.17, alpha: 1)
            ]

            (title as NSString).draw(at: CGPoint(x: 68, y: 88), withAttributes: titleStyle)
            (subtitle as NSString).draw(at: CGPoint(x: 70, y: 148), withAttributes: subtitleStyle)

            for (index, row) in rows.enumerated() {
                let y = 230 + CGFloat(index * 78)
                context.setStrokeColor(UIColor.black.withAlphaComponent(0.10).cgColor)
                context.setLineWidth(2)
                context.move(to: CGPoint(x: 82, y: y + 52))
                context.addLine(to: CGPoint(x: 718, y: y + 52))
                context.strokePath()
                (row as NSString).draw(at: CGPoint(x: 72, y: y), withAttributes: rowStyle)
            }

            context.setStrokeColor(UIColor(red: 0.72, green: 0.24, blue: 0.20, alpha: 0.72).cgColor)
            context.setLineWidth(7)
            context.strokeEllipse(in: CGRect(x: 570, y: 585, width: 140, height: 140))
            let stamp = localized(chinese: "示例", english: "SAMPLE")
            let stampStyle: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: L10n.usesEnglish ? 22 : 32, weight: .bold),
                .foregroundColor: UIColor(red: 0.72, green: 0.24, blue: 0.20, alpha: 0.72)
            ]
            (stamp as NSString).draw(
                in: CGRect(x: 580, y: 632, width: 120, height: 48),
                withAttributes: stampStyle
            )
        }

        return HealthRecordAttachment(
            id: uuid("A0C2F7A3-2E88-4F7C-9404-7C811914E001"),
            kind: .image,
            data: imageData,
            originalName: localized(chinese: "疫苗接种凭证.jpg", english: "vaccination-certificate.jpg"),
            createdAt: occurredAt
        )
    }

    private static func localized(chinese: String, english: String) -> String {
        L10n.usesEnglish ? english : chinese
    }

    private static func uuid(_ string: String) -> UUID {
        UUID(uuidString: string)!
    }
}
#endif
