#if !targetEnvironment(simulator)
import AMapFoundationKit
import AMapSearchKit
#endif
import CoreLocation
import Foundation
import MapKit
import OSLog
import Observation

private enum HospitalPOICategory {
    /// 高德官方 POI 分类：医疗保健服务 → 动物医疗场所。
    static let amapTypeCode = "090700"

    private static let veterinaryTerms = [
        "宠物医院", "动物医院", "宠物诊所", "动物诊所", "兽医站", "兽医院",
        "veterinary", "veterinarian", "animal hospital", "pet hospital", "vet clinic"
    ]

    static func appearsVeterinary(_ values: String?...) -> Bool {
        let searchableText = values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
        return veterinaryTerms.contains { searchableText.contains($0) }
    }

    static func shouldExpandSearch(
        query: String,
        results: some Collection<HospitalSummary>
    ) -> Bool {
        let normalizedQuery = normalizedSearchText(query)
        guard !normalizedQuery.isEmpty else { return false }
        return !results.contains { normalizedSearchText($0.name).contains(normalizedQuery) }
    }

    static func isNameMatch(_ hospital: HospitalSummary, query: String) -> Bool {
        let normalizedQuery = normalizedSearchText(query)
        return !normalizedQuery.isEmpty && normalizedSearchText(hospital.name).contains(normalizedQuery)
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: L10n.locale
            )
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}

@MainActor
protocol HospitalMapProviding: AnyObject {
    var source: HospitalDataSource { get }

    func searchHospitals(
        query: String,
        region: MKCoordinateRegion,
        referenceLocation: CLLocation
    ) async throws -> [HospitalSummary]
}

@MainActor
final class MapKitHospitalProvider: HospitalMapProviding {
    let source = HospitalDataSource.mapKit

    func searchHospitals(
        query: String,
        region: MKCoordinateRegion,
        referenceLocation: CLLocation
    ) async throws -> [HospitalSummary] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queries = trimmedQuery.isEmpty
            ? (L10n.usesEnglish
                ? ["veterinary hospital", "animal hospital", "vet clinic"]
                : ["宠物医院", "动物医院", "动物诊所"])
            : [trimmedQuery]

        var placesByID: [String: HospitalSummary] = [:]
        var lastError: Error?

        for keyword in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmedQuery.isEmpty
                ? keyword
                : keyword
            request.region = region
            request.resultTypes = .pointOfInterest
            var usesAnimalServiceFilter = false
            if #available(iOS 18.0, *) {
                request.pointOfInterestFilter = MKPointOfInterestFilter(
                    including: [MKPointOfInterestCategory.animalService]
                )
                usesAnimalServiceFilter = true
            }

            do {
                let response = try await MKLocalSearch(request: request).start()
                for mapItem in response.mapItems {
                    guard isWithinSearchRegion(mapItem.placemark.coordinate, region: region) else {
                        continue
                    }
                    guard usesAnimalServiceFilter || HospitalPOICategory.appearsVeterinary(
                        mapItem.name,
                        mapItem.placemark.title
                    ) else {
                        continue
                    }
                    let place = makeHospital(from: mapItem, referenceLocation: referenceLocation)
                    if let existing = placesByID[place.id] {
                        placesByID[place.id] = preferred(existing, place)
                    } else {
                        placesByID[place.id] = place
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        if HospitalPOICategory.shouldExpandSearch(
            query: trimmedQuery,
            results: placesByID.values
        ) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmedQuery
            request.resultTypes = .pointOfInterest
            var usesAnimalServiceFilter = false
            if #available(iOS 18.0, *) {
                request.pointOfInterestFilter = MKPointOfInterestFilter(
                    including: [MKPointOfInterestCategory.animalService]
                )
                usesAnimalServiceFilter = true
            }

            do {
                let response = try await MKLocalSearch(request: request).start()
                for mapItem in response.mapItems {
                    guard usesAnimalServiceFilter || HospitalPOICategory.appearsVeterinary(
                        mapItem.name,
                        mapItem.placemark.title
                    ) else {
                        continue
                    }
                    let place = makeHospital(from: mapItem, referenceLocation: referenceLocation)
                    if let existing = placesByID[place.id] {
                        placesByID[place.id] = preferred(existing, place)
                    } else {
                        placesByID[place.id] = place
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        let results = placesByID.values
            .sorted { lhs, rhs in
                let lhsMatches = HospitalPOICategory.isNameMatch(lhs, query: trimmedQuery)
                let rhsMatches = HospitalPOICategory.isNameMatch(rhs, query: trimmedQuery)
                if lhsMatches != rhsMatches {
                    return lhsMatches
                }
                if lhs.distanceMeters == rhs.distanceMeters {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.distanceMeters < rhs.distanceMeters
            }

        if results.isEmpty, let lastError {
            throw lastError
        }
        return Array(results.prefix(40))
    }

    private func isWithinSearchRegion(
        _ coordinate: CLLocationCoordinate2D,
        region: MKCoordinateRegion
    ) -> Bool {
        let latitudeAllowance = max(0.03, region.span.latitudeDelta * 0.75)
        let longitudeAllowance = max(0.03, region.span.longitudeDelta * 0.75)
        let latitudeDifference = abs(coordinate.latitude - region.center.latitude)
        let rawLongitudeDifference = abs(coordinate.longitude - region.center.longitude)
        let longitudeDifference = min(rawLongitudeDifference, 360 - rawLongitudeDifference)

        return latitudeDifference <= latitudeAllowance && longitudeDifference <= longitudeAllowance
    }

    private func makeHospital(
        from mapItem: MKMapItem,
        referenceLocation: CLLocation
    ) -> HospitalSummary {
        let coordinate = mapItem.placemark.coordinate
        let name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = name?.isEmpty == false ? name! : L10n.string("宠物医院")
        let address = formattedAddress(for: mapItem.placemark)
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return HospitalSummary(
            id: sourceID(name: safeName, address: address, coordinate: coordinate),
            source: .mapKit,
            name: safeName,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            distanceMeters: max(0, Int(referenceLocation.distance(from: location).rounded())),
            phoneNumber: normalized(mapItem.phoneNumber),
            websiteURL: mapItem.url?.absoluteString,
            isFavorite: false
        )
    }

    private func formattedAddress(for placemark: MKPlacemark) -> String {
        if let title = normalized(placemark.title) {
            return title
        }

        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap(normalized)
            .joined()
        let components = [placemark.locality, placemark.subLocality, street]
            .compactMap(normalized)
        return components.isEmpty ? L10n.string("地址暂未提供") : components.joined(separator: " ")
    }

    private func sourceID(
        name: String,
        address: String,
        coordinate: CLLocationCoordinate2D
    ) -> String {
        let latitude = Int((coordinate.latitude * 100_000).rounded())
        let longitude = Int((coordinate.longitude * 100_000).rounded())
        let normalizedName = normalizedIdentifierComponent(name)
        let normalizedAddress = normalizedIdentifierComponent(address)
        return "mapkit|\(normalizedName)|\(normalizedAddress)|\(latitude)|\(longitude)"
    }

    private func normalizedIdentifierComponent(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func preferred(_ lhs: HospitalSummary, _ rhs: HospitalSummary) -> HospitalSummary {
        var result = lhs.distanceMeters <= rhs.distanceMeters ? lhs : rhs
        result.phoneNumber = result.phoneNumber ?? lhs.phoneNumber ?? rhs.phoneNumber
        result.websiteURL = result.websiteURL ?? lhs.websiteURL ?? rhs.websiteURL
        if result.address == "地址暂未提供" {
            result.address = lhs.address == "地址暂未提供" ? rhs.address : lhs.address
        }
        return result
    }
}

#if !targetEnvironment(simulator)
private enum AMapHospitalError: LocalizedError {
    case privacyConsentRequired
    case missingAPIKey
    case sdkInitializationFailed

    var errorDescription: String? {
        switch self {
        case .privacyConsentRequired:
            "需要先同意隐私说明，才能使用高德医院搜索。"
        case .missingAPIKey:
            "高德地图 Key 尚未写入本机配置。"
        case .sdkInitializationFailed:
            "高德地图服务初始化失败，请检查 Key 类型和 Bundle ID。"
        }
    }
}

@MainActor
private enum AMapSDKConfiguration {
    static var apiKey: String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "AMapAPIKey") as? String else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    static func configureAfterConsent() throws {
        guard AppPrivacyConsent.isGranted else {
            throw AMapHospitalError.privacyConsentRequired
        }
        guard let apiKey else {
            throw AMapHospitalError.missingAPIKey
        }

        AMapSearchAPI.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        AMapSearchAPI.updatePrivacyAgree(.didAgree)
        // AMap's English POI channel in mainland China is a separate,
        // sparsely populated data path and may require additional service
        // access. Keep the local search data in Simplified Chinese so an
        // English app UI returns the same nearby hospitals as the Chinese UI.
        // App-owned controls and messages are still localized independently.
        AMapServices.shared().regionLanguageType = .zhHans
        AMapServices.shared().enableHTTPS = true
        AMapServices.shared().apiKey = apiKey
    }
}

@MainActor
final class AMapHospitalProvider: NSObject, HospitalMapProviding, @preconcurrency AMapSearchDelegate {
    let source = HospitalDataSource.amap

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Zoji",
        category: "AMapHospitalSearch"
    )
    private var searchAPI: AMapSearchAPI?
    private var continuation: CheckedContinuation<[AMapPOI], Error>?

    func searchHospitals(
        query: String,
        region: MKCoordinateRegion,
        referenceLocation: CLLocation
    ) async throws -> [HospitalSummary] {
        try AMapSDKConfiguration.configureAfterConsent()
        let searchAPI = try makeSearchAPIIfNeeded()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let amapCenter = AMapCoordinateConvert(region.center, .GPS)
        let radius = searchRadius(for: region)

        var resultsByID: [String: HospitalSummary] = [:]
        var lastError: Error?

        do {
            let nearbyPOIs = try await performNearbySearch(
                keywords: trimmedQuery,
                center: amapCenter,
                radius: radius,
                searchAPI: searchAPI
            )
            addHospitals(
                from: nearbyPOIs,
                referenceLocation: referenceLocation,
                to: &resultsByID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastError = error
        }

        if HospitalPOICategory.shouldExpandSearch(
            query: trimmedQuery,
            results: resultsByID.values
        ) {
            do {
                let keywordPOIs = try await performKeywordSearch(
                    keywords: trimmedQuery,
                    referencePoint: amapCenter,
                    searchAPI: searchAPI
                )
                addHospitals(
                    from: keywordPOIs,
                    referenceLocation: referenceLocation,
                    to: &resultsByID
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        let results = resultsByID.values.sorted { lhs, rhs in
            let lhsMatches = HospitalPOICategory.isNameMatch(lhs, query: trimmedQuery)
            let rhsMatches = HospitalPOICategory.isNameMatch(rhs, query: trimmedQuery)
            if lhsMatches != rhsMatches {
                return lhsMatches
            }
            if lhs.distanceMeters == rhs.distanceMeters {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.distanceMeters < rhs.distanceMeters
        }

        if results.isEmpty, let lastError {
            throw lastError
        }
        return Array(results.prefix(40))
    }

    private func makeSearchAPIIfNeeded() throws -> AMapSearchAPI {
        if let searchAPI {
            return searchAPI
        }

        guard let searchAPI = AMapSearchAPI() else {
            throw AMapHospitalError.sdkInitializationFailed
        }
        searchAPI.delegate = self
        searchAPI.timeout = 15
        self.searchAPI = searchAPI
        return searchAPI
    }

    private func performNearbySearch(
        keywords: String,
        center: CLLocationCoordinate2D,
        radius: Int,
        searchAPI: AMapSearchAPI
    ) async throws -> [AMapPOI] {
        cancelPendingSearch()

        let request = AMapPOIAroundSearchRequest()
        request.location = AMapGeoPoint.location(
            withLatitude: CGFloat(center.latitude),
            longitude: CGFloat(center.longitude)
        )
        request.keywords = keywords
        request.types = HospitalPOICategory.amapTypeCode
        request.radius = radius
        request.sortrule = 0
        request.offset = 25
        request.page = 1
        request.showFieldsType = [.business]

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                searchAPI.aMapPOIAroundSearch(request)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPendingSearch()
            }
        }
    }

    private func performKeywordSearch(
        keywords: String,
        referencePoint: CLLocationCoordinate2D,
        searchAPI: AMapSearchAPI
    ) async throws -> [AMapPOI] {
        cancelPendingSearch()

        let request = AMapPOIKeywordsSearchRequest()
        request.keywords = keywords
        request.types = HospitalPOICategory.amapTypeCode
        request.cityLimit = false
        request.location = AMapGeoPoint.location(
            withLatitude: CGFloat(referencePoint.latitude),
            longitude: CGFloat(referencePoint.longitude)
        )
        request.sortrule = 0
        request.offset = 25
        request.page = 1
        request.showFieldsType = [.business]

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                searchAPI.aMapPOIKeywordsSearch(request)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPendingSearch()
            }
        }
    }

    private func addHospitals(
        from pois: [AMapPOI],
        referenceLocation: CLLocation,
        to resultsByID: inout [String: HospitalSummary]
    ) {
        for poi in pois {
            guard isVeterinaryPOI(poi) else { continue }
            guard let place = makeHospital(from: poi, referenceLocation: referenceLocation) else { continue }
            resultsByID[place.id] = place
        }
    }

    private func searchRadius(for region: MKCoordinateRegion) -> Int {
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let northEdge = CLLocation(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude
        )
        let eastEdge = CLLocation(
            latitude: region.center.latitude,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        )
        let visibleRadius = max(center.distance(from: northEdge), center.distance(from: eastEdge))
        return min(50_000, max(3_000, Int(visibleRadius.rounded())))
    }

    private func makeHospital(
        from poi: AMapPOI,
        referenceLocation: CLLocation
    ) -> HospitalSummary? {
        guard let location = poi.location else { return nil }
        let name = normalized(poi.name) ?? L10n.string("宠物医院")
        let coordinate = CLLocationCoordinate2D(
            latitude: CLLocationDegrees(location.latitude),
            longitude: CLLocationDegrees(location.longitude)
        )
        let address = formattedAddress(for: poi)
        let computedDistance = referenceLocation.distance(from: CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ))
        let distance = poi.distance > 0 ? Double(poi.distance) : computedDistance

        return HospitalSummary(
            id: "amap|\(normalized(poi.uid) ?? sourceID(name: name, coordinate: coordinate))",
            source: .amap,
            name: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            distanceMeters: max(0, Int(distance.rounded())),
            phoneNumber: normalized(poi.tel),
            websiteURL: normalized(poi.website),
            isFavorite: false
        )
    }

    private func isVeterinaryPOI(_ poi: AMapPOI) -> Bool {
        if let typecode = normalized(poi.typecode), typecode.hasPrefix("0907") {
            return true
        }
        return HospitalPOICategory.appearsVeterinary(poi.type, poi.name, poi.address)
    }

    private func formattedAddress(for poi: AMapPOI) -> String {
        if let address = normalized(poi.address) {
            let region = [normalized(poi.city), normalized(poi.district)]
                .compactMap { $0 }
                .joined()
            return region.isEmpty || address.hasPrefix(region) ? address : region + address
        }
        return [normalized(poi.city), normalized(poi.district)]
            .compactMap { $0 }
            .joined().nonEmpty ?? L10n.string("地址暂未提供")
    }

    private func sourceID(name: String, coordinate: CLLocationCoordinate2D) -> String {
        let latitude = Int((coordinate.latitude * 100_000).rounded())
        let longitude = Int((coordinate.longitude * 100_000).rounded())
        return "\(name)|\(latitude)|\(longitude)"
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cancelPendingSearch() {
        let pendingContinuation = continuation
        continuation = nil
        searchAPI?.cancelAllRequests()
        pendingContinuation?.resume(throwing: CancellationError())
    }

    func onPOISearchDone(
        _ request: AMapPOISearchBaseRequest!,
        response: AMapPOISearchResponse!
    ) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: response?.pois ?? [])
    }

    func aMapSearchRequest(_ request: Any!, didFailWithError error: Error!) {
        let continuation = continuation
        self.continuation = nil
        let resolvedError = error ?? URLError(.unknown)
        let nsError = resolvedError as NSError
        logger.error(
            "AMap POI request failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(nsError.localizedDescription, privacy: .public)"
        )
        continuation?.resume(throwing: resolvedError)
    }
}
#endif

@MainActor
final class AutomaticHospitalProvider: HospitalMapProviding {
    let source = HospitalDataSource.amap

    #if !targetEnvironment(simulator)
    private let amapProvider = AMapHospitalProvider()
    #endif
    private let mapKitProvider = MapKitHospitalProvider()

    func searchHospitals(
        query: String,
        region: MKCoordinateRegion,
        referenceLocation: CLLocation
    ) async throws -> [HospitalSummary] {
        #if targetEnvironment(simulator)
        return try await mapKitProvider.searchHospitals(
            query: query,
            region: region,
            referenceLocation: referenceLocation
        )
        #else
        guard shouldPreferAMap(at: region.center), AMapSDKConfiguration.apiKey != nil else {
            return try await mapKitProvider.searchHospitals(
                query: query,
                region: region,
                referenceLocation: referenceLocation
            )
        }

        do {
            return try await amapProvider.searchHospitals(
                query: query,
                region: region,
                referenceLocation: referenceLocation
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The native SDK can briefly fail while its service is warming up on first entry.
            // Retry once in-place so users do not need to leave and reopen the tab.
            try await Task.sleep(for: .milliseconds(450))
            try Task.checkCancellation()
            return try await amapProvider.searchHospitals(
                query: query,
                region: region,
                referenceLocation: referenceLocation
            )
        }
        #endif
    }

    #if !targetEnvironment(simulator)
    private func shouldPreferAMap(at coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= 17.5 && coordinate.latitude <= 54.5 &&
            coordinate.longitude >= 72 && coordinate.longitude <= 136
    }
    #endif
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct HospitalFavoriteStore {
    private let defaults: UserDefaults

    private var storageKey: String {
        "zoji.favorite-hospitals.v2.private"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [HospitalSummary] {
        guard let data = defaults.data(forKey: storageKey),
              let hospitals = try? JSONDecoder().decode([HospitalSummary].self, from: data) else {
            return []
        }
        return hospitals.map { hospital in
            var favorite = hospital
            favorite.isFavorite = true
            return favorite
        }
    }

    func save(_ hospitals: [HospitalSummary]) {
        let sorted = hospitals.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

@MainActor
@Observable
final class HospitalsViewModel {
    var hospitals: [HospitalSummary] = []
    var favorites: [HospitalSummary]
    var isSearching = false
    var message: String?
    var hasSearchError = false

    @ObservationIgnored private let provider: any HospitalMapProviding
    @ObservationIgnored private let favoriteStore: HospitalFavoriteStore
    @ObservationIgnored private var searchGeneration = 0
    private var currentSource: HospitalDataSource

    init(
        provider: (any HospitalMapProviding)? = nil,
        favoriteStore: HospitalFavoriteStore = HospitalFavoriteStore()
    ) {
        let resolvedProvider = provider ?? AutomaticHospitalProvider()
        self.provider = resolvedProvider
        self.favoriteStore = favoriteStore
        self.favorites = favoriteStore.load()
        self.currentSource = resolvedProvider.source
    }

    var sourceName: String { currentSource.displayName }

    func search(
        query: String,
        region: MKCoordinateRegion,
        userLocation: CLLocation?
    ) async {
        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        message = nil
        hasSearchError = false
        defer {
            if generation == searchGeneration {
                isSearching = false
            }
        }

        let referenceLocation = userLocation ?? CLLocation(
            latitude: region.center.latitude,
            longitude: region.center.longitude
        )

        do {
            let results = try await provider.searchHospitals(
                query: query,
                region: region,
                referenceLocation: referenceLocation
            )
            guard generation == searchGeneration else { return }
            if let source = results.first?.source {
                currentSource = source
            }
            let favoriteIDs = Set(favorites.map(\.id))
            hospitals = results.map { hospital in
                var updated = hospital
                updated.isFavorite = favoriteIDs.contains(hospital.id)
                return updated
            }
            if hospitals.isEmpty {
                let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                message = trimmedQuery.isEmpty
                    ? L10n.string("这个区域暂未搜到宠物医院，可以移动地图后重新搜索。")
                    : L10n.string("没有找到匹配的宠物医院，请尝试医院全名、所在城市或其他关键词。")
            }
        } catch {
            guard generation == searchGeneration else { return }
            hasSearchError = true
            message = L10n.string("医院信息暂时加载失败，请检查网络后重试。")
        }
    }

    func toggleFavorite(_ hospital: HospitalSummary) {
        if let index = favorites.firstIndex(where: { $0.id == hospital.id }) {
            favorites.remove(at: index)
        } else {
            var favorite = hospital
            favorite.isFavorite = true
            favorites.append(favorite)
        }

        let favoriteIDs = Set(favorites.map(\.id))
        hospitals = hospitals.map { hospital in
            var updated = hospital
            updated.isFavorite = favoriteIDs.contains(hospital.id)
            return updated
        }
        favorites = favorites.map { hospital in
            var updated = hospital
            updated.isFavorite = true
            return updated
        }
        favoriteStore.save(favorites)
    }

    func hospital(id: String) -> HospitalSummary? {
        hospitals.first { $0.id == id } ?? favorites.first { $0.id == id }
    }
}

@MainActor
@Observable
final class HospitalLocationManager: NSObject, @preconcurrency CLLocationManagerDelegate {
    var location: CLLocation?
    var locationRevision = 0
    var message: String?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            message = L10n.string("定位未开启。可以拖动地图，并点击“搜索此区域”。")
        @unknown default:
            message = L10n.string("暂时无法获取定位，可以拖动地图后搜索。")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            message = nil
            manager.requestLocation()
        case .denied, .restricted:
            message = L10n.string("定位未开启。可以拖动地图，并点击“搜索此区域”。")
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        locationRevision += 1
        message = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        message = L10n.string("暂时无法获取定位，可以拖动地图后搜索。")
    }
}
