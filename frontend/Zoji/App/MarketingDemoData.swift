#if DEBUG
import Foundation
import MapKit
import SwiftData

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
        let tangdouID = uuid("B0C2F7A3-2E88-4F7C-9404-7C811914E003")

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

        let tangdou = PetEntity(
            id: tangdouID,
            ownerID: PrivateDataScope.ownerID,
            name: localized(chinese: "糖豆", english: "Sunny"),
            species: .dog
        )
        tangdou.breed = localized(chinese: "威尔士柯基", english: "Welsh Corgi")
        tangdou.avatarPresetID = "dog-corgi"
        tangdou.sexRawValue = PetSex.female.rawValue
        tangdou.birthday = calendar.date(byAdding: .year, value: -4, to: today)
        tangdou.weightKilograms = 10.8
        tangdou.profileStatusRawValue = PetProfileStatus.active.rawValue

        [huhu, zhazha, tangdou].forEach(context.insert)

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
        let petID = uuid("B0C2F7A3-2E88-4F7C-9404-7C811914E001")
        let pet = Pet(
            id: petID,
            name: localized(chinese: "呼呼", english: "Mochi"),
            species: .cat,
            breed: localized(chinese: "英国短毛猫", english: "British Shorthair"),
            avatarPresetID: "cat-british-shorthair",
            sex: .female,
            birthday: calendar.date(byAdding: .year, value: -3, to: today),
            weightKilograms: 5.2,
            profileStatus: .active
        )
        let members = [
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
        let sharedPet = FamilySharedPet(
            location: FamilyShareLocation(
                zoneName: "marketing-family-huhu",
                zoneOwnerName: "marketing-owner",
                databaseScope: .ownerPrivate
            ),
            ownerName: localized(chinese: "我", english: "Me"),
            role: .owner,
            payload: FamilyPetSharePayload(
                exportedAt: today,
                pet: pet,
                records: [],
                reminders: []
            ),
            members: members
        )

        let store = FamilySharingStore(restoredSharedPets: [])
        store.ownedSharedPets = [sharedPet]
        store.recentActivities = [
            FamilyShareActivity(
                id: uuid("E0C2F7A3-2E88-4F7C-9404-7C811914E001"),
                petID: petID,
                petName: pet.name,
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

    private static func localized(chinese: String, english: String) -> String {
        L10n.usesEnglish ? english : chinese
    }

    private static func uuid(_ string: String) -> UUID {
        UUID(uuidString: string)!
    }
}
#endif
