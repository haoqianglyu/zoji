import CoreLocation
import MapKit
import SwiftUI
import UIKit

private enum HospitalPresentationMode: String, CaseIterable, Identifiable {
    case map
    case list

    var id: Self { self }

    var title: String {
        switch self {
        case .map: L10n.string("地图")
        case .list: L10n.string("列表")
        }
    }

    var symbol: String {
        switch self {
        case .map: "map.fill"
        case .list: "list.bullet"
        }
    }
}

private enum HospitalResultScope: String, CaseIterable, Identifiable {
    case nearby
    case favorites

    var id: Self { self }

    var title: String {
        switch self {
        case .nearby: L10n.string("附近")
        case .favorites: L10n.string("收藏")
        }
    }
}

struct HospitalsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appColorTheme) private var theme

    @State private var model = HospitalsViewModel()
    @State private var locationManager = HospitalLocationManager()
    @State private var query = ""
    @State private var mode = HospitalPresentationMode.map
    @State private var scope = HospitalResultScope.nearby
    @State private var selectedHospitalID: String?
    @State private var selectedHospital: HospitalSummary?
    @State private var hasCenteredOnUser = false
    @AppStorage(AMapPrivacyConsent.storageKey) private var amapPrivacyStatusRaw = AMapPrivacyConsent.Status.undetermined.rawValue
    @State private var isAMapPrivacyPresented = false

    @State private var currentRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    private var displayedHospitals: [HospitalSummary] {
        switch scope {
        case .nearby: model.hospitals
        case .favorites: model.favorites
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls

                if mode == .map {
                    hospitalMap
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                resultHeader
                resultList
            }
            .background(theme.background)
            .navigationTitle("宠物医院")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.easeInOut(duration: 0.2), value: mode)
            .task {
                if !store.hospitals.isEmpty, model.hospitals.isEmpty {
                    model.hospitals = store.hospitals
                }
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
                locationManager.requestLocation()
                if model.hospitals.isEmpty {
                    // Give Core Location a brief chance to supply the real region. This avoids
                    // racing a default-region request against the location-triggered request.
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled,
                          locationManager.location == nil,
                          model.hospitals.isEmpty,
                          !model.isSearching else { return }
                    await searchCurrentRegion()
                }
            }
            .onChange(of: locationManager.locationRevision) { _, _ in
                guard let location = locationManager.location else { return }
                let region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.07)
                )
                currentRegion = region
                if !hasCenteredOnUser {
                    position = .region(region)
                    hasCenteredOnUser = true
                }
                Task { await searchCurrentRegion(allowAMapConsentPrompt: true) }
            }
            .onChange(of: selectedHospitalID) { _, hospitalID in
                guard let hospitalID else { return }
                selectedHospital = model.hospital(id: hospitalID)
            }
            .sheet(item: $selectedHospital, onDismiss: {
                selectedHospitalID = nil
            }) { hospital in
                HospitalDetailView(
                    hospital: hospital,
                    onToggleFavorite: { model.toggleFavorite($0) }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isAMapPrivacyPresented) {
                AMapPrivacyConsentView {
                    amapPrivacyStatusRaw = AMapPrivacyConsent.Status.agreed.rawValue
                    Task { await searchCurrentRegion() }
                } onDecline: {
                    amapPrivacyStatusRaw = AMapPrivacyConsent.Status.declined.rawValue
                    Task { await searchCurrentRegion() }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索医院名称或所在城市", text: $query)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit {
                            scope = .nearby
                            Task { await searchCurrentRegion(allowAMapConsentPrompt: true) }
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                Button {
                    hasCenteredOnUser = false
                    locationManager.requestLocation()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .background(theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .accessibilityLabel("定位到当前位置")
            }

            HStack(spacing: 12) {
                Picker("医院范围", selection: $scope) {
                    ForEach(HospitalResultScope.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                HStack(spacing: 4) {
                    ForEach(HospitalPresentationMode.allCases) { option in
                        Button {
                            mode = option
                        } label: {
                            Image(systemName: option.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .foregroundStyle(mode == option ? theme.accent : .secondary)
                                .background(
                                    mode == option ? theme.surface : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                    }
                }
                .padding(3)
                .frame(width: 104)
                .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let locationMessage = locationManager.message {
                Label(locationMessage, systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var hospitalMap: some View {
        Map(position: $position, selection: $selectedHospitalID) {
            if locationManager.location != nil {
                UserAnnotation()
            }
            ForEach(displayedHospitals) { hospital in
                Marker(
                    hospital.name,
                    coordinate: CLLocationCoordinate2D(
                        latitude: hospital.latitude,
                        longitude: hospital.longitude
                    )
                )
                .tint(hospital.isFavorite ? theme.warning : theme.accent)
                .tag(hospital.id)
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            currentRegion = context.region
        }
        .frame(height: 285)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottom) {
            Button {
                scope = .nearby
                Task { await searchCurrentRegion(allowAMapConsentPrompt: true) }
            } label: {
                HStack(spacing: 7) {
                    if model.isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(model.isSearching ? "正在搜索" : "搜索此区域")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 13)
                .frame(height: 34)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isSearching)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
    }

    private var resultHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(resultHeaderTitle)
                .font(.title3.bold())
            if !displayedHospitals.isEmpty {
                Text("\(displayedHospitals.count) 家")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, mode == .map ? 16 : 4)
        .padding(.bottom, 10)
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.isSearching, displayedHospitals.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.string(
                            hasSearchQuery ? "正在搜索宠物医院…" : "正在查找附近的宠物医院…"
                        ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
                } else if displayedHospitals.isEmpty {
                    ContentUnavailableView {
                        Label(
                            emptyStateTitle,
                            systemImage: scope == .favorites ? "heart" : (model.hasSearchError ? "wifi.exclamationmark" : "cross.case")
                        )
                    } description: {
                        Text(scope == .favorites
                             ? "收藏常去的医院后，会在这里快速找到。"
                             : (model.message ?? "移动地图或更换关键词后重新搜索。"))
                    }
                    .padding(.top, 18)
                } else {
                    ForEach(displayedHospitals) { hospital in
                        HospitalRow(
                            hospital: hospital,
                            onSelect: { selectedHospital = hospital },
                            onToggleFavorite: { model.toggleFavorite(hospital) }
                        )
                    }
                }

                Text("地图信息可能存在延迟，就诊前请电话确认地址、营业时间和接诊范围。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable {
            await searchCurrentRegion(allowAMapConsentPrompt: true)
        }
    }

    private func searchCurrentRegion(allowAMapConsentPrompt: Bool = false) async {
        if allowAMapConsentPrompt,
           HospitalProviderPolicy.shouldOfferAMap(at: currentRegion.center),
           AMapPrivacyConsent.Status(rawValue: amapPrivacyStatusRaw) == .undetermined {
            isAMapPrivacyPresented = true
            return
        }

        await model.search(
            query: query,
            region: currentRegion,
            userLocation: locationManager.location
        )
    }

    private var hasSearchQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resultHeaderTitle: LocalizedStringKey {
        if scope == .favorites { return "收藏医院" }
        return hasSearchQuery ? "搜索结果" : "附近医院"
    }

    private var emptyStateTitle: LocalizedStringKey {
        if scope == .favorites { return "还没有收藏医院" }
        return model.hasSearchError ? "医院加载失败" : "暂未找到医院"
    }
}

private struct HospitalRow: View {
    @Environment(\.appColorTheme) private var theme
    let hospital: HospitalSummary
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        ZojiCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
                    .background(theme.accentSoft)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(hospital.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(hospital.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Label(hospital.distanceText, systemImage: "location.fill")
                        if hospital.phoneNumber != nil {
                            Label("可拨号", systemImage: "phone.fill")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.accent)
                }

                Spacer(minLength: 4)

                Button(action: onToggleFavorite) {
                    Image(systemName: hospital.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(hospital.isFavorite ? theme.warning : .secondary)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hospital.isFavorite ? "取消收藏" : "收藏医院")
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
        }
    }
}

private struct HospitalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme

    let hospital: HospitalSummary
    let onToggleFavorite: (HospitalSummary) -> Void
    @State private var isFavorite: Bool

    init(
        hospital: HospitalSummary,
        onToggleFavorite: @escaping (HospitalSummary) -> Void
    ) {
        self.hospital = hospital
        self.onToggleFavorite = onToggleFavorite
        _isFavorite = State(initialValue: hospital.isFavorite)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(theme.accentSoft)
                            .frame(height: 112)
                        VStack(spacing: 8) {
                            Image(systemName: "cross.case.fill")
                                .font(.system(size: 27, weight: .semibold))
                                .foregroundStyle(theme.accent)
                            Text(hospital.name)
                                .font(.title3.bold())
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }

                    ZojiCard {
                        VStack(alignment: .leading, spacing: 14) {
                            detailLine(symbol: "mappin.and.ellipse", title: "地址", value: hospital.address)
                            Divider()
                            detailLine(symbol: "location.fill", title: "距离", value: hospital.distanceText)
                            if let phone = hospital.phoneNumber {
                                Divider()
                                detailLine(symbol: "phone.fill", title: "电话", value: phone)
                            }
                            Divider()
                            detailLine(symbol: "map.fill", title: "数据来源", value: hospital.source.displayName)
                        }
                    }

                    HStack(spacing: 12) {
                        actionButton(title: "导航", symbol: "arrow.triangle.turn.up.right.diamond.fill") {
                            openDirections()
                        }
                        if hospital.phoneNumber != nil {
                            actionButton(title: "拨号", symbol: "phone.fill") {
                                callHospital()
                            }
                        }
                        actionButton(
                            title: isFavorite ? "已收藏" : "收藏",
                            symbol: isFavorite ? "heart.fill" : "heart"
                        ) {
                            onToggleFavorite(hospital)
                            isFavorite.toggle()
                        }
                    }

                    if let websiteURL = hospital.websiteURL,
                       let url = URL(string: websiteURL) {
                        Link(destination: url) {
                            Label("查看医院网站", systemImage: "safari")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }

                    Text("爪记仅展示地图地点信息，不对医院资质、营业状态或诊疗服务作保证，请在就诊前电话确认。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(16)
            }
            .background(theme.background)
            .navigationTitle("医院详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func detailLine(symbol: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.dynamic(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }
        }
    }

    private func actionButton(
        title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                Text(L10n.dynamic(title))
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(theme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.accent)
    }

    private func openDirections() {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(
                latitude: hospital.latitude,
                longitude: hospital.longitude
            )
        )
        let destination = MKMapItem(placemark: placemark)
        destination.name = hospital.name
        destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func callHospital() {
        guard let phone = hospital.phoneNumber else { return }
        let allowed = phone.filter { $0.isNumber || $0 == "+" }
        guard !allowed.isEmpty, let url = URL(string: "tel://\(allowed)") else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    HospitalsView()
        .environment(AppStore.preview)
}
