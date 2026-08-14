import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }

            RecordsView()
                .tabItem { Label("记录", systemImage: "list.bullet.clipboard.fill") }

            HospitalsView()
                .tabItem { Label("医院", systemImage: "cross.case.fill") }

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
        }
        .toolbarBackground(AppTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

#Preview {
    RootTabView()
        .environment(AppStore.preview)
}
