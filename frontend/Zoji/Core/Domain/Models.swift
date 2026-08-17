import Foundation

enum PetSpecies: String, Codable, CaseIterable, Sendable {
    case cat
    case dog
    case other

    var displayName: String {
        switch self {
        case .cat: L10n.string("猫")
        case .dog: L10n.string("狗")
        case .other: L10n.string("其他")
        }
    }

    var avatarSymbol: String {
        switch self {
        case .cat: "cat.fill"
        case .dog: "dog.fill"
        case .other: "pawprint.fill"
        }
    }
}

enum PetBreedCatalog {
    static let catBreeds = [
        "中华田园猫",
        "英国短毛猫",
        "美国短毛猫",
        "布偶猫",
        "暹罗猫",
        "缅因猫",
        "异国短毛猫",
        "波斯猫",
        "俄罗斯蓝猫",
        "斯芬克斯猫",
        "德文卷毛猫",
        "苏格兰折耳猫",
        "孟加拉豹猫",
        "橘猫"
    ]

    static let dogBreeds = [
        "中华田园犬",
        "柴犬",
        "金毛寻回犬",
        "拉布拉多寻回犬",
        "威尔士柯基",
        "贵宾犬",
        "比熊犬",
        "博美犬",
        "萨摩耶犬",
        "西伯利亚哈士奇",
        "边境牧羊犬",
        "德国牧羊犬",
        "法国斗牛犬",
        "巴哥犬",
        "雪纳瑞犬",
        "吉娃娃"
    ]

    static func breeds(for species: PetSpecies) -> [String] {
        switch species {
        case .cat: catBreeds
        case .dog: dogBreeds
        case .other: []
        }
    }

    static func localizedName(_ storedBreed: String) -> String {
        L10n.dynamic(storedBreed)
    }
}

enum PetSex: String, Codable, CaseIterable, Sendable {
    case female
    case male
    case unknown

    var displayName: String {
        switch self {
        case .female: L10n.string("妹妹")
        case .male: L10n.string("弟弟")
        case .unknown: L10n.string("未知")
        }
    }

    var symbol: String {
        switch self {
        case .female: "♀"
        case .male: "♂"
        case .unknown: ""
        }
    }
}

enum PetProfileStatus: String, Codable, CaseIterable, Sendable {
    case active
    case archived
    case memorial

    var displayName: String {
        switch self {
        case .active: L10n.string("正常")
        case .archived: L10n.string("已归档")
        case .memorial: L10n.string("纪念")
        }
    }

    var symbol: String {
        switch self {
        case .active: "pawprint.fill"
        case .archived: "archivebox.fill"
        case .memorial: "heart.fill"
        }
    }

    var isActive: Bool { self == .active }
}

enum RecordKind: String, Codable, CaseIterable, Sendable {
    case life
    case vaccine
    case internalDeworming
    case externalDeworming
    case bathGrooming
    case medicalVisit
    case medication
    case custom

    var displayName: String {
        switch self {
        case .life: L10n.string("生活记录")
        case .vaccine: L10n.string("疫苗")
        case .internalDeworming: L10n.string("体内驱虫")
        case .externalDeworming: L10n.string("体外驱虫")
        case .bathGrooming: L10n.string("洗澡护理")
        case .medicalVisit: L10n.string("看病就医")
        case .medication: L10n.string("用药")
        case .custom: L10n.string("自定义")
        }
    }

    var symbol: String {
        switch self {
        case .life: "camera.fill"
        case .vaccine: "syringe.fill"
        case .internalDeworming, .externalDeworming: "shield.lefthalf.filled"
        case .bathGrooming: "sparkles"
        case .medicalVisit: "cross.case.fill"
        case .medication: "pills.fill"
        case .custom: "pawprint.fill"
        }
    }

    var defaultTitle: String {
        switch self {
        case .life: L10n.string("生活记录")
        case .vaccine: L10n.string("疫苗接种")
        case .internalDeworming: L10n.string("体内驱虫")
        case .externalDeworming: L10n.string("体外驱虫")
        case .bathGrooming: L10n.string("洗澡护理")
        case .medicalVisit: ""
        case .medication: L10n.string("用药记录")
        case .custom: ""
        }
    }

    var titlePrompt: String {
        switch self {
        case .life: L10n.string("记录今天的美好瞬间")
        case .vaccine: L10n.string("例如：狂犬疫苗")
        case .internalDeworming: L10n.string("例如：体内驱虫")
        case .externalDeworming: L10n.string("例如：体外驱虫")
        case .bathGrooming: L10n.string("例如：洗澡剪毛")
        case .medicalVisit: L10n.string("例如：拉肚子")
        case .medication: L10n.string("例如：服用益生菌")
        case .custom: L10n.string("简要概括这次记录")
        }
    }

    static var healthCases: [RecordKind] {
        allCases.filter { $0 != .life }
    }
}

enum ScheduleType: String, Codable, CaseIterable, Sendable {
    case oneOff
    case intervalDays
    case calendarMonths
    case calendarYears
    case preset
}

struct WeightEntry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var measuredAt: Date
    var kilograms: Double

    init(id: UUID = UUID(), measuredAt: Date, kilograms: Double) {
        self.id = id
        self.measuredAt = measuredAt
        self.kilograms = kilograms
    }
}

struct Pet: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var species: PetSpecies
    var breed: String?
    var avatarSymbol: String
    var avatarData: Data?
    var avatarPresetID: String?
    var sex: PetSex?
    var birthday: Date?
    var weightKilograms: Double?
    /// Optional for backward-compatible decoding of older backups and family
    /// sharing snapshots that predate weight history support.
    var weightEntries: [WeightEntry]?
    /// Optional so older backups and family-sharing snapshots decode as active.
    var profileStatus: PetProfileStatus?

    var resolvedProfileStatus: PetProfileStatus {
        profileStatus ?? .active
    }

    var isActiveProfile: Bool {
        resolvedProfileStatus.isActive
    }

    var sortedWeightEntries: [WeightEntry] {
        (weightEntries ?? []).sorted { $0.measuredAt < $1.measuredAt }
    }

    var localizedBreed: String? {
        breed.map(PetBreedCatalog.localizedName)
    }

    init(
        id: UUID,
        name: String,
        species: PetSpecies,
        breed: String? = nil,
        avatarSymbol: String? = nil,
        avatarData: Data? = nil,
        avatarPresetID: String? = nil,
        sex: PetSex? = nil,
        birthday: Date? = nil,
        weightKilograms: Double? = nil,
        weightEntries: [WeightEntry]? = nil,
        profileStatus: PetProfileStatus? = nil
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.breed = breed
        self.avatarSymbol = avatarSymbol ?? species.avatarSymbol
        self.avatarData = avatarData
        self.avatarPresetID = avatarPresetID
        self.sex = sex
        self.birthday = birthday
        self.weightKilograms = weightKilograms
        self.weightEntries = weightEntries
        self.profileStatus = profileStatus
    }
}

struct HealthRecord: Identifiable, Hashable, Codable, Sendable {
    static let reminderCompletionNoteMarker = "zoji:system-note:reminder-completion:v1"

    let id: UUID
    let petID: UUID
    var kind: RecordKind
    var title: String
    var occurredAt: Date
    var providerName: String?
    /// Historical name retained for storage compatibility. The value is the
    /// smallest unit of `currencyCode` (for example cents for CNY/USD).
    var costCents: Int?
    var currencyCode: String? = nil
    /// Time zone in which the event date was entered. Optional so records from
    /// older backups and family-sharing payloads continue to decode.
    var timeZoneIdentifier: String? = TimeZone.autoupdatingCurrent.identifier
    var notes: String? = nil
    var attachments: [HealthRecordAttachment] = []

    var resolvedCurrencyCode: String {
        // Records created before currency support always stored Chinese yuan.
        guard let currencyCode else { return "CNY" }
        return RegionalFormat.validatedCurrencyCode(currencyCode) ?? "XXX"
    }

    var localizedNotes: String? {
        switch notes {
        case Self.reminderCompletionNoteMarker,
             "由健康提醒完成后自动生成。",
             "由家庭共享提醒完成后自动生成。":
            L10n.string("由健康提醒完成后自动生成。")
        default:
            notes
        }
    }

    func occurrenceYear(fallbackCalendar: Calendar = .autoupdatingCurrent) -> Int {
        var calendar = fallbackCalendar
        if let timeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar.component(.year, from: occurredAt)
    }
}

struct HealthRecordAttachment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var kind: HealthRecordAttachmentKind
    var data: Data
    var originalName: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: HealthRecordAttachmentKind = .image,
        data: Data,
        originalName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.data = data
        self.originalName = originalName ?? (kind == .pdf ? "病例附件.pdf" : "病例图片.jpg")
        self.createdAt = createdAt
    }
}

enum HealthRecordAttachmentKind: String, Codable, Sendable {
    case image
    case pdf
}

enum HealthRecordAttachmentPolicy {
    static let maximumCount = 9
    static let maximumImageSourceBytes = 60_000_000
    static let maximumStoredImageBytes = 12_000_000
    static let preferredStoredImageBytes = 2_500_000
    static let maximumPDFBytes = 25_000_000
    static let maximumTotalBytes = 75_000_000
    static let maximumImageDimension = 2_048

    static func maximumBytes(for kind: HealthRecordAttachmentKind) -> Int {
        switch kind {
        case .image: maximumStoredImageBytes
        case .pdf: maximumPDFBytes
        }
    }

    static func validate(_ attachments: [HealthRecordAttachment]) throws {
        guard attachments.count <= maximumCount else {
            throw HealthRecordAttachmentValidationError.tooManyAttachments
        }

        var totalBytes = 0
        for attachment in attachments {
            guard !attachment.data.isEmpty else {
                throw HealthRecordAttachmentValidationError.emptyAttachment
            }
            guard attachment.data.count <= maximumBytes(for: attachment.kind) else {
                throw attachment.kind == .pdf
                    ? HealthRecordAttachmentValidationError.pdfTooLarge
                    : HealthRecordAttachmentValidationError.imageTooLarge
            }
            totalBytes += attachment.data.count
            guard totalBytes <= maximumTotalBytes else {
                throw HealthRecordAttachmentValidationError.totalTooLarge
            }
        }
    }

    static func validateAddition(
        kind: HealthRecordAttachmentKind,
        byteCount: Int,
        currentCount: Int,
        currentBytes: Int
    ) throws {
        guard currentCount < maximumCount else {
            throw HealthRecordAttachmentValidationError.tooManyAttachments
        }
        guard byteCount > 0 else {
            throw HealthRecordAttachmentValidationError.emptyAttachment
        }
        guard byteCount <= maximumBytes(for: kind) else {
            throw kind == .pdf
                ? HealthRecordAttachmentValidationError.pdfTooLarge
                : HealthRecordAttachmentValidationError.imageTooLarge
        }
        guard currentBytes <= maximumTotalBytes - byteCount else {
            throw HealthRecordAttachmentValidationError.totalTooLarge
        }
    }

    static func formattedByteCount(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

enum HealthRecordAttachmentValidationError: LocalizedError, Equatable {
    case tooManyAttachments
    case emptyAttachment
    case imageSourceTooLarge
    case imageTooLarge
    case pdfTooLarge
    case totalTooLarge
    case unreadableImage
    case unreadablePDF

    var errorDescription: String? {
        switch self {
        case .tooManyAttachments:
            L10n.string("每条健康记录最多添加 9 个附件。")
        case .emptyAttachment:
            L10n.string("附件内容为空，请重新选择。")
        case .imageSourceTooLarge:
            L10n.string("原始图片超过 60 MB，请先在照片中裁剪或压缩。")
        case .imageTooLarge:
            L10n.string("图片处理后仍超过 12 MB，请换一张尺寸较小的图片。")
        case .pdfTooLarge:
            L10n.string("单个 PDF 不能超过 25 MB。")
        case .totalTooLarge:
            L10n.string("本条记录的附件总计不能超过 75 MB。")
        case .unreadableImage:
            L10n.string("无法读取这张图片，请重新选择。")
        case .unreadablePDF:
            L10n.string("无法读取这个 PDF，文件可能已损坏或受密码保护。")
        }
    }
}

struct ReminderItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let petID: UUID
    var sourceRecordID: UUID?
    var title: String
    var kind: RecordKind
    var dueAt: Date
    var scheduleType: ScheduleType
    var intervalValue: Int?
    var advanceDays: [Int]
    var isEnabled: Bool
    var lastCompletedAt: Date?

    init(
        id: UUID,
        petID: UUID,
        sourceRecordID: UUID? = nil,
        title: String,
        kind: RecordKind,
        dueAt: Date,
        scheduleType: ScheduleType = .oneOff,
        intervalValue: Int? = nil,
        advanceDays: [Int] = [1, 0],
        isEnabled: Bool = true,
        lastCompletedAt: Date? = nil
    ) {
        self.id = id
        self.petID = petID
        self.sourceRecordID = sourceRecordID
        self.title = title
        self.kind = kind
        self.dueAt = dueAt
        self.scheduleType = scheduleType
        self.intervalValue = intervalValue
        self.advanceDays = advanceDays
        self.isEnabled = isEnabled
        self.lastCompletedAt = lastCompletedAt
    }

    var isCompleted: Bool {
        !isEnabled && lastCompletedAt != nil
    }

    var isOverdue: Bool {
        isEnabled && dueAt < Calendar.current.startOfDay(for: Date())
    }

    func isCompletionLocked(
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard isEnabled else { return true }
        guard let lastCompletedAt else { return false }
        return dueAt > lastCompletedAt
            && date < calendar.startOfDay(for: dueAt)
    }
}

enum CarePlanLifeStage: String, Codable, Sendable {
    case young
    case adult
    case all
}

struct CarePlanTemplateStep: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let kind: RecordKind
    let dayOffset: Int
    let scheduleType: ScheduleType
    let intervalValue: Int?
    let advanceDays: [Int]

    var localizedTitle: String { L10n.dynamic(title) }

    init(
        id: String,
        title: String,
        kind: RecordKind,
        dayOffset: Int = 0,
        scheduleType: ScheduleType = .oneOff,
        intervalValue: Int? = nil,
        advanceDays: [Int] = [1, 0]
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.dayOffset = dayOffset
        self.scheduleType = scheduleType
        self.intervalValue = intervalValue
        self.advanceDays = advanceDays
    }

    func dueDate(from startDate: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
    }

    var scheduleDescription: String {
        if dayOffset == 0, scheduleType == .oneOff {
            return L10n.string("首次计划日")
        }
        if scheduleType == .oneOff {
            return String(
                localized: "第 \(dayOffset + 1) 天",
                locale: L10n.locale
            )
        }
        return switch (scheduleType, intervalValue) {
        case (.intervalDays, let days?): String(localized: "每 \(days) 天", locale: L10n.locale)
        case (.calendarMonths, 1), (.preset, 1): L10n.string("每月")
        case (.calendarMonths, let months?), (.preset, let months?): String(localized: "每 \(months) 个月", locale: L10n.locale)
        case (.calendarYears, 1): L10n.string("每年")
        case (.calendarYears, let years?): String(localized: "每 \(years) 年", locale: L10n.locale)
        default: L10n.string("按计划重复")
        }
    }
}

struct CarePlanTemplate: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let summary: String
    let species: PetSpecies
    let lifeStage: CarePlanLifeStage
    let symbol: String
    let steps: [CarePlanTemplateStep]

    var localizedTitle: String { L10n.dynamic(title) }
    var localizedSummary: String { L10n.dynamic(summary) }
}

enum CarePlanTemplateCatalog {
    static let templates: [CarePlanTemplate] = [
        CarePlanTemplate(
            id: "cat-kitten-core-v1",
            title: "幼猫基础免疫",
            summary: "核心疫苗按 4 周间隔建立待办，并安排狂犬疫苗与首年加强评估。",
            species: .cat,
            lifeStage: .young,
            symbol: "syringe.fill",
            steps: [
                .init(id: "cat-core-1", title: "猫核心疫苗第 1 针", kind: .vaccine, advanceDays: [7, 1, 0]),
                .init(id: "cat-core-2", title: "猫核心疫苗第 2 针", kind: .vaccine, dayOffset: 28, advanceDays: [7, 1, 0]),
                .init(id: "cat-core-3", title: "猫核心疫苗第 3 针", kind: .vaccine, dayOffset: 56, advanceDays: [7, 1, 0]),
                .init(id: "cat-rabies-review", title: "狂犬疫苗评估", kind: .vaccine, dayOffset: 56, advanceDays: [7, 1, 0]),
                .init(id: "cat-first-booster", title: "首年免疫加强评估", kind: .vaccine, dayOffset: 365, advanceDays: [7, 1, 0])
            ]
        ),
        CarePlanTemplate(
            id: "cat-adult-review-v1",
            title: "成猫年度免疫评估",
            summary: "每年提醒复核核心疫苗、狂犬疫苗有效期和生活方式风险。",
            species: .cat,
            lifeStage: .adult,
            symbol: "calendar.badge.clock",
            steps: [
                .init(id: "cat-annual-review", title: "年度免疫评估", kind: .vaccine, scheduleType: .calendarYears, intervalValue: 1, advanceDays: [7, 1, 0]),
                .init(id: "cat-rabies-expiry", title: "核对狂犬疫苗有效期", kind: .vaccine, advanceDays: [7, 1, 0])
            ]
        ),
        CarePlanTemplate(
            id: "cat-deworming-v1",
            title: "猫咪常规驱虫",
            summary: "默认体内每 3 个月、体外每月；可生成后按产品和兽医建议调整。",
            species: .cat,
            lifeStage: .all,
            symbol: "shield.lefthalf.filled",
            steps: [
                .init(id: "cat-internal-deworming", title: "体内驱虫", kind: .internalDeworming, scheduleType: .calendarMonths, intervalValue: 3),
                .init(id: "cat-external-deworming", title: "体外驱虫", kind: .externalDeworming, scheduleType: .calendarMonths, intervalValue: 1)
            ]
        ),
        CarePlanTemplate(
            id: "dog-puppy-core-v1",
            title: "幼犬基础免疫",
            summary: "核心联苗按 4 周间隔建立待办，并安排狂犬疫苗与首年加强评估。",
            species: .dog,
            lifeStage: .young,
            symbol: "syringe.fill",
            steps: [
                .init(id: "dog-core-1", title: "犬核心联苗第 1 针", kind: .vaccine, advanceDays: [7, 1, 0]),
                .init(id: "dog-core-2", title: "犬核心联苗第 2 针", kind: .vaccine, dayOffset: 28, advanceDays: [7, 1, 0]),
                .init(id: "dog-core-3", title: "犬核心联苗第 3 针", kind: .vaccine, dayOffset: 56, advanceDays: [7, 1, 0]),
                .init(id: "dog-rabies-review", title: "狂犬疫苗评估", kind: .vaccine, dayOffset: 56, advanceDays: [7, 1, 0]),
                .init(id: "dog-first-booster", title: "首年免疫加强评估", kind: .vaccine, dayOffset: 365, advanceDays: [7, 1, 0])
            ]
        ),
        CarePlanTemplate(
            id: "dog-adult-review-v1",
            title: "成犬年度免疫评估",
            summary: "每年提醒复核核心疫苗、狂犬疫苗有效期及所在地区风险。",
            species: .dog,
            lifeStage: .adult,
            symbol: "calendar.badge.clock",
            steps: [
                .init(id: "dog-annual-review", title: "年度免疫评估", kind: .vaccine, scheduleType: .calendarYears, intervalValue: 1, advanceDays: [7, 1, 0]),
                .init(id: "dog-rabies-expiry", title: "核对狂犬疫苗有效期", kind: .vaccine, advanceDays: [7, 1, 0])
            ]
        ),
        CarePlanTemplate(
            id: "dog-deworming-v1",
            title: "狗狗常规驱虫",
            summary: "默认体内每 3 个月、体外每月；可生成后按产品和兽医建议调整。",
            species: .dog,
            lifeStage: .all,
            symbol: "shield.lefthalf.filled",
            steps: [
                .init(id: "dog-internal-deworming", title: "体内驱虫", kind: .internalDeworming, scheduleType: .calendarMonths, intervalValue: 3),
                .init(id: "dog-external-deworming", title: "体外驱虫", kind: .externalDeworming, scheduleType: .calendarMonths, intervalValue: 1)
            ]
        )
    ]

    static func templates(for species: PetSpecies) -> [CarePlanTemplate] {
        templates.filter { $0.species == species }
    }

    static func isRecommended(_ template: CarePlanTemplate, for pet: Pet, now: Date = Date()) -> Bool {
        guard template.lifeStage != .all else { return true }
        guard let birthday = pet.birthday,
              let ageInMonths = Calendar.current.dateComponents([.month], from: birthday, to: now).month else {
            return template.lifeStage == .young
        }
        return ageInMonths < 12 ? template.lifeStage == .young : template.lifeStage == .adult
    }

    static func suggestedStartDate(for pet: Pet, template: CarePlanTemplate, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let earliest = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        guard template.lifeStage == .young,
              let birthday = pet.birthday,
              let eightWeeksOld = calendar.date(byAdding: .day, value: 56, to: birthday),
              eightWeeksOld > earliest else {
            return earliest
        }
        return calendar.startOfDay(for: eightWeeksOld)
    }
}

enum HospitalDataSource: String, Codable, Sendable {
    case mapKit
    case amap

    var displayName: String {
        switch self {
        case .mapKit: L10n.string("Apple 地图")
        case .amap: L10n.string("高德地图")
        }
    }
}

struct HospitalSummary: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var source: HospitalDataSource
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var distanceMeters: Int
    var phoneNumber: String?
    var websiteURL: String?
    var isFavorite: Bool

    init(
        id: String,
        source: HospitalDataSource = .mapKit,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        distanceMeters: Int,
        phoneNumber: String? = nil,
        websiteURL: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.source = source
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
        self.phoneNumber = phoneNumber
        self.websiteURL = websiteURL
        self.isFavorite = isFavorite
    }

    var distanceText: String {
        RegionalFormat.distanceString(fromMeters: Double(distanceMeters))
    }
}
