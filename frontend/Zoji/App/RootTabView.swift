import SwiftUI

struct RootTabView: View {
    @Environment(\.appColorTheme) private var theme

    private enum Tab: Hashable {
        case home
        case records
        case reminders
        case hospitals
        case profile
    }

    @State private var selectedTab: Tab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(Tab.home)

            RecordsView()
                .tabItem { Label("记录", systemImage: "list.bullet.clipboard.fill") }
                .tag(Tab.records)

            NavigationStack {
                ReminderListView()
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
    }
}

#Preview {
    RootTabView()
        .environment(AppStore.preview)
}
