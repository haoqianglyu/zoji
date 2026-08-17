import Combine
import SwiftUI
import UIKit

struct RootTabView: View {
    @Environment(\.appColorTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(FamilySharingStore.self) private var familyStore
    @Environment(\.openURL) private var openURL
    @AppStorage("zoji.notification-permission-prompt-suppressed") private var suppressesNotificationPrompt = false

    private enum Tab: Hashable {
        case home
        case records
        case reminders
        case hospitals
        case profile
    }

    @State private var selectedTab: Tab = .home
    @State private var reminderRoute: ReminderNotificationRoute?

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(Tab.home)

            RecordsView()
                .tabItem { Label("记录", systemImage: "list.bullet.clipboard.fill") }
                .tag(Tab.records)

            NavigationStack {
                ReminderListView(notificationRoute: $reminderRoute)
            }
            .tabItem { Label("提醒", systemImage: "bell.badge.fill") }
            .tag(Tab.reminders)

            HospitalsView()
                .tabItem { Label("医院", systemImage: "cross.case.fill") }
                .tag(Tab.hospitals)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(Tab.profile)
        }
        .toolbarBackground(theme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            if let route = ReminderNotificationRouter.pendingRoute {
                open(route)
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: ReminderNotificationRouter.didOpenNotification
        ).receive(on: DispatchQueue.main)) { notification in
            guard let route = notification.object as? ReminderNotificationRoute else { return }
            open(route)
        }
        .alert("系统通知未开启", isPresented: Binding(
            get: { store.notificationPermissionMessage != nil && !suppressesNotificationPrompt },
            set: { if !$0 { store.notificationPermissionMessage = nil } }
        )) {
            Button("前往设置") {
                store.notificationPermissionMessage = nil
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("不再提示") {
                suppressesNotificationPrompt = true
                store.notificationPermissionMessage = nil
            }
            Button("稍后", role: .cancel) {
                store.notificationPermissionMessage = nil
            }
        } message: {
            Text(store.notificationPermissionMessage ?? "提醒仍会保存在 App 中。")
        }
    }

    private func open(_ route: ReminderNotificationRoute) {
        if let sharedPet = familyStore.sharedPets.first(where: {
            $0.pet.id == route.petID && $0.reminders.contains(where: { $0.id == route.reminderID })
        }) {
            store.select(.shared(sharedPet), using: familyStore)
        } else if let pet = store.pets.first(where: { $0.id == route.petID }) {
            store.select(.local(
                pet: pet,
                records: store.records.filter { $0.petID == pet.id },
                reminders: store.reminders.filter { $0.petID == pet.id }
            ), using: familyStore)
        }
        reminderRoute = route
        selectedTab = .reminders
        ReminderNotificationRouter.clear(route)
    }
}

#Preview {
    RootTabView()
        .environment(AppStore.preview)
}
