import Foundation

enum L10n {
    /// The language iOS selected for this app. This respects both the device's
    /// preferred languages and Settings > Zoji > Preferred Language.
    static var languageIdentifier: String {
        Bundle.main.preferredLocalizations.first
            ?? Locale.autoupdatingCurrent.language.languageCode?.identifier
            ?? "zh-Hans"
    }

    static var usesEnglish: Bool {
        languageIdentifier.lowercased().hasPrefix("en")
    }

    static var currentLanguageDisplayName: String {
        usesEnglish ? "English" : "简体中文"
    }

    static var locale: Locale {
        guard let region = Locale.autoupdatingCurrent.region?.identifier else {
            return Locale(identifier: languageIdentifier)
        }
        return Locale(identifier: "\(languageIdentifier)-\(region)")
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    /// Localizes catalog-backed values that are stored as data (for example,
    /// legacy Chinese breed names and generated reminder titles). Unknown
    /// values are returned unchanged, preserving user-entered content.
    static func dynamic(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    static func date(
        _ date: Date,
        dateStyle: Date.FormatStyle.DateStyle,
        timeStyle: Date.FormatStyle.TimeStyle
    ) -> String {
        date.formatted(
            Date.FormatStyle(date: dateStyle, time: timeStyle)
                .locale(locale)
        )
    }
}

enum AppUnitSystem: String, CaseIterable, Identifiable {
    case system
    case metric
    case us

    static let storageKey = "zoji-preferred-unit-system"

    var id: Self { self }

    static var selected: Self {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(Self.init(rawValue:)) ?? .system
    }

    var displayName: String {
        switch self {
        case .system: L10n.string("系统")
        case .metric: L10n.string("公制")
        case .us: L10n.string("美制")
        }
    }

    var detailText: String {
        switch self {
        case .system: L10n.string("根据 iPhone 地区自动选择")
        case .metric: L10n.string("kg · km · ℃")
        case .us: L10n.string("lb · mi · ℉")
        }
    }

    var symbol: String {
        switch self {
        case .system: "iphone"
        case .metric: "scalemass.fill"
        case .us: "ruler.fill"
        }
    }
}

enum RegionalFormat {
    private static let poundsPerKilogram = 2.204_622_621_8
    private static let feetPerMeter = 3.280_839_895
    private static let metersPerMile = 1_609.344
    private static let commonCurrencyCodes = [
        "CNY", "USD", "EUR", "GBP", "JPY", "HKD", "TWD", "KRW", "SGD", "AUD", "CAD"
    ]

    static var usesPounds: Bool {
        switch AppUnitSystem.selected {
        case .system: L10n.locale.measurementSystem == .us
        case .metric: false
        case .us: true
        }
    }

    static var usesMiles: Bool {
        switch AppUnitSystem.selected {
        case .system:
            L10n.locale.measurementSystem == .us || L10n.locale.measurementSystem == .uk
        case .metric: false
        case .us: true
        }
    }

    static var usesFahrenheit: Bool {
        switch AppUnitSystem.selected {
        case .system: L10n.locale.measurementSystem == .us
        case .metric: false
        case .us: true
        }
    }

    static var massUnitSymbol: String {
        usesPounds ? "lb" : "kg"
    }

    static func displayedMass(fromKilograms kilograms: Double) -> Double {
        usesPounds ? kilograms * poundsPerKilogram : kilograms
    }

    static func kilograms(fromDisplayedMass value: Double) -> Double {
        usesPounds ? value / poundsPerKilogram : value
    }

    static func massInputString(fromKilograms kilograms: Double) -> String {
        displayedMass(fromKilograms: kilograms).formatted(
            .number
                .precision(.fractionLength(0 ... 2))
                .locale(L10n.locale)
        )
    }

    static func representsSameDisplayedMass(_ lhsKilograms: Double, _ rhsKilograms: Double) -> Bool {
        let lhs = (displayedMass(fromKilograms: lhsKilograms) * 100).rounded()
        let rhs = (displayedMass(fromKilograms: rhsKilograms) * 100).rounded()
        return lhs == rhs
    }

    static func massString(fromKilograms kilograms: Double) -> String {
        "\(massInputString(fromKilograms: kilograms)) \(massUnitSymbol)"
    }

    static func distanceString(fromMeters meters: Double) -> String {
        let safeMeters = max(0, meters)
        if usesMiles {
            let miles = safeMeters / metersPerMile
            if miles < 0.1 {
                return "\(numberString(safeMeters * feetPerMeter, maximumFractionDigits: 0)) ft"
            }
            return "\(numberString(miles, maximumFractionDigits: 1)) mi"
        }

        if safeMeters < 1_000 {
            return "\(numberString(safeMeters, maximumFractionDigits: 0)) m"
        }
        return "\(numberString(safeMeters / 1_000, maximumFractionDigits: 1)) km"
    }

    static func temperatureString(fromCelsius celsius: Double) -> String {
        let value = usesFahrenheit ? (celsius * 9 / 5 + 32) : celsius
        let symbol = usesFahrenheit ? "℉" : "℃"
        return "\(numberString(value, maximumFractionDigits: 1)) \(symbol)"
    }

    static func parseNumber(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = L10n.locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }

        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    static var defaultCurrencyCode: String {
        normalizedCurrencyCode(L10n.locale.currency?.identifier ?? "CNY")
    }

    static var supportedCurrencyCodes: [String] {
        var codes = [defaultCurrencyCode]
        codes.append(contentsOf: commonCurrencyCodes)
        return codes.reduce(into: []) { result, code in
            if !result.contains(code) { result.append(code) }
        }
    }

    static func normalizedCurrencyCode(_ code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return validatedCurrencyCode(normalized) ?? "XXX"
    }

    static func validatedCurrencyCode(_ code: String) -> String? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 3,
              normalized.allSatisfy({ $0.isASCII && $0.isLetter }),
              Locale.commonISOCurrencyCodes.contains(normalized) || normalized == "XXX" else {
            return nil
        }
        return normalized
    }

    static func currencySymbol(for code: String) -> String {
        let formatter = currencyFormatter(code: code)
        return formatter.currencySymbol ?? normalizedCurrencyCode(code)
    }

    static func currencyPickerLabel(for code: String) -> String {
        let normalized = normalizedCurrencyCode(code)
        return "\(normalized) \(currencySymbol(for: normalized))"
    }

    static func currencyInputString(minorUnits: Int, code: String) -> String {
        let digits = currencyFractionDigits(code: code)
        let value = Double(minorUnits) / Double(minorUnitScale(code: code))
        return value.formatted(
            .number
                .precision(.fractionLength(0 ... digits))
                .locale(L10n.locale)
        )
    }

    static func numberInputString(_ value: Decimal, maximumFractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? NSDecimalNumber(decimal: value).stringValue
    }

    static func currencyString(minorUnits: Int, code: String) -> String {
        let value = Double(minorUnits) / Double(minorUnitScale(code: code))
        return currencyFormatter(code: code).string(from: NSNumber(value: value))
            ?? "\(normalizedCurrencyCode(code)) \(value)"
    }

    static func minorUnits(from input: String, code: String) -> Int? {
        guard let amount = parseNumber(input), amount >= 0, amount <= 1_000_000 else {
            return nil
        }
        return Int((amount * Double(minorUnitScale(code: code))).rounded())
    }

    static func maximumMinorUnits(code: String) -> Int {
        1_000_000 * minorUnitScale(code: code)
    }

    private static func numberString(_ value: Double, maximumFractionDigits: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0 ... maximumFractionDigits))
                .locale(L10n.locale)
        )
    }

    private static func minorUnitScale(code: String) -> Int {
        (0 ..< currencyFractionDigits(code: code)).reduce(1) { scale, _ in scale * 10 }
    }

    private static func currencyFractionDigits(code: String) -> Int {
        let formatter = currencyFormatter(code: code)
        return max(0, formatter.maximumFractionDigits)
    }

    private static func currencyFormatter(code: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = L10n.locale
        formatter.numberStyle = .currency
        formatter.currencyCode = normalizedCurrencyCode(code)
        return formatter
    }
}
