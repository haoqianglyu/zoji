import SwiftUI

enum AppColorTheme: String, CaseIterable, Identifiable {
    case warm
    case sage
    case sky
    case lavender
    case sakura
    case honey
    case cocoa
    case mint

    static let storageKey = "zoji-color-theme"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .warm: L10n.string("暖杏")
        case .sage: L10n.string("鼠尾草")
        case .sky: L10n.string("晴空蓝")
        case .lavender: L10n.string("薰衣草")
        case .sakura: L10n.string("樱花粉")
        case .honey: L10n.string("蜂蜜黄")
        case .cocoa: L10n.string("奶咖")
        case .mint: L10n.string("薄荷青")
        }
    }

    var symbol: String {
        switch self {
        case .warm: "sun.max.fill"
        case .sage: "leaf.fill"
        case .sky: "cloud.sun.fill"
        case .lavender: "sparkles"
        case .sakura: "camera.macro"
        case .honey: "sun.max.fill"
        case .cocoa: "cup.and.saucer.fill"
        case .mint: "drop.fill"
        }
    }

    var accent: Color { dynamicColor(light: lightAccent, dark: darkAccent) }
    var accentDeep: Color { dynamicColor(light: lightAccentDeep, dark: darkAccentDeep) }
    var accentSoft: Color { dynamicColor(light: lightAccentSoft, dark: darkAccentSoft) }
    var background: Color { dynamicColor(light: lightBackground, dark: darkBackground) }
    var surface: Color { dynamicColor(light: lightSurface, dark: darkSurface) }
    var surfaceMuted: Color { dynamicColor(light: lightSurfaceMuted, dark: darkSurfaceMuted) }
    var warning: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.94, green: 0.45, blue: 0.42, alpha: 1)
                : UIColor(red: 0.74, green: 0.27, blue: 0.26, alpha: 1)
        })
    }

    private var lightAccent: UIColor {
        switch self {
        case .warm: UIColor(red: 0.73, green: 0.37, blue: 0.26, alpha: 1)
        case .sage: UIColor(red: 0.28, green: 0.48, blue: 0.37, alpha: 1)
        case .sky: UIColor(red: 0.25, green: 0.48, blue: 0.67, alpha: 1)
        case .lavender: UIColor(red: 0.48, green: 0.39, blue: 0.65, alpha: 1)
        case .sakura: UIColor(red: 0.67, green: 0.30, blue: 0.43, alpha: 1)
        case .honey: UIColor(red: 0.62, green: 0.43, blue: 0.10, alpha: 1)
        case .cocoa: UIColor(red: 0.42, green: 0.29, blue: 0.24, alpha: 1)
        case .mint: UIColor(red: 0.16, green: 0.48, blue: 0.45, alpha: 1)
        }
    }

    private var darkAccent: UIColor {
        switch self {
        case .warm: UIColor(red: 0.91, green: 0.60, blue: 0.45, alpha: 1)
        case .sage: UIColor(red: 0.55, green: 0.72, blue: 0.59, alpha: 1)
        case .sky: UIColor(red: 0.52, green: 0.72, blue: 0.88, alpha: 1)
        case .lavender: UIColor(red: 0.72, green: 0.63, blue: 0.86, alpha: 1)
        case .sakura: UIColor(red: 0.91, green: 0.58, blue: 0.66, alpha: 1)
        case .honey: UIColor(red: 0.91, green: 0.70, blue: 0.32, alpha: 1)
        case .cocoa: UIColor(red: 0.76, green: 0.60, blue: 0.51, alpha: 1)
        case .mint: UIColor(red: 0.49, green: 0.78, blue: 0.73, alpha: 1)
        }
    }

    private var lightAccentDeep: UIColor {
        switch self {
        case .warm: UIColor(red: 0.49, green: 0.23, blue: 0.17, alpha: 1)
        case .sage: UIColor(red: 0.18, green: 0.32, blue: 0.24, alpha: 1)
        case .sky: UIColor(red: 0.17, green: 0.32, blue: 0.48, alpha: 1)
        case .lavender: UIColor(red: 0.31, green: 0.24, blue: 0.46, alpha: 1)
        case .sakura: UIColor(red: 0.46, green: 0.20, blue: 0.29, alpha: 1)
        case .honey: UIColor(red: 0.43, green: 0.28, blue: 0.07, alpha: 1)
        case .cocoa: UIColor(red: 0.29, green: 0.19, blue: 0.16, alpha: 1)
        case .mint: UIColor(red: 0.10, green: 0.32, blue: 0.30, alpha: 1)
        }
    }

    private var darkAccentDeep: UIColor {
        switch self {
        case .warm: UIColor(red: 0.73, green: 0.36, blue: 0.25, alpha: 1)
        case .sage: UIColor(red: 0.34, green: 0.52, blue: 0.40, alpha: 1)
        case .sky: UIColor(red: 0.31, green: 0.51, blue: 0.69, alpha: 1)
        case .lavender: UIColor(red: 0.50, green: 0.40, blue: 0.66, alpha: 1)
        case .sakura: UIColor(red: 0.72, green: 0.37, blue: 0.48, alpha: 1)
        case .honey: UIColor(red: 0.70, green: 0.48, blue: 0.14, alpha: 1)
        case .cocoa: UIColor(red: 0.55, green: 0.38, blue: 0.31, alpha: 1)
        case .mint: UIColor(red: 0.27, green: 0.58, blue: 0.54, alpha: 1)
        }
    }

    private var lightAccentSoft: UIColor {
        switch self {
        case .warm: UIColor(red: 0.97, green: 0.91, blue: 0.86, alpha: 1)
        case .sage: UIColor(red: 0.89, green: 0.94, blue: 0.89, alpha: 1)
        case .sky: UIColor(red: 0.88, green: 0.93, blue: 0.97, alpha: 1)
        case .lavender: UIColor(red: 0.93, green: 0.90, blue: 0.97, alpha: 1)
        case .sakura: UIColor(red: 0.98, green: 0.89, blue: 0.91, alpha: 1)
        case .honey: UIColor(red: 0.98, green: 0.93, blue: 0.81, alpha: 1)
        case .cocoa: UIColor(red: 0.93, green: 0.88, blue: 0.84, alpha: 1)
        case .mint: UIColor(red: 0.86, green: 0.95, blue: 0.92, alpha: 1)
        }
    }

    private var darkAccentSoft: UIColor {
        switch self {
        case .warm: UIColor(red: 0.23, green: 0.14, blue: 0.11, alpha: 1)
        case .sage: UIColor(red: 0.11, green: 0.20, blue: 0.14, alpha: 1)
        case .sky: UIColor(red: 0.10, green: 0.17, blue: 0.23, alpha: 1)
        case .lavender: UIColor(red: 0.17, green: 0.13, blue: 0.23, alpha: 1)
        case .sakura: UIColor(red: 0.24, green: 0.12, blue: 0.16, alpha: 1)
        case .honey: UIColor(red: 0.23, green: 0.17, blue: 0.07, alpha: 1)
        case .cocoa: UIColor(red: 0.21, green: 0.16, blue: 0.14, alpha: 1)
        case .mint: UIColor(red: 0.08, green: 0.21, blue: 0.19, alpha: 1)
        }
    }

    private var lightBackground: UIColor {
        switch self {
        case .warm: UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1)
        case .sage: UIColor(red: 0.95, green: 0.96, blue: 0.93, alpha: 1)
        case .sky: UIColor(red: 0.94, green: 0.96, blue: 0.98, alpha: 1)
        case .lavender: UIColor(red: 0.96, green: 0.95, blue: 0.98, alpha: 1)
        case .sakura: UIColor(red: 0.99, green: 0.95, blue: 0.96, alpha: 1)
        case .honey: UIColor(red: 0.99, green: 0.97, blue: 0.91, alpha: 1)
        case .cocoa: UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1)
        case .mint: UIColor(red: 0.93, green: 0.98, blue: 0.96, alpha: 1)
        }
    }

    private var darkBackground: UIColor {
        switch self {
        case .warm: UIColor(red: 0.09, green: 0.07, blue: 0.06, alpha: 1)
        case .sage: UIColor(red: 0.06, green: 0.09, blue: 0.07, alpha: 1)
        case .sky: UIColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1)
        case .lavender: UIColor(red: 0.08, green: 0.07, blue: 0.11, alpha: 1)
        case .sakura: UIColor(red: 0.10, green: 0.06, blue: 0.08, alpha: 1)
        case .honey: UIColor(red: 0.10, green: 0.08, blue: 0.04, alpha: 1)
        case .cocoa: UIColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 1)
        case .mint: UIColor(red: 0.04, green: 0.09, blue: 0.08, alpha: 1)
        }
    }

    private var lightSurface: UIColor {
        switch self {
        case .warm: UIColor(red: 1.00, green: 0.99, blue: 0.97, alpha: 1)
        case .sage: UIColor(red: 0.99, green: 1.00, blue: 0.98, alpha: 1)
        case .sky: UIColor(red: 0.98, green: 0.99, blue: 1.00, alpha: 1)
        case .lavender: UIColor(red: 0.99, green: 0.98, blue: 1.00, alpha: 1)
        case .sakura: UIColor(red: 1.00, green: 0.98, blue: 0.99, alpha: 1)
        case .honey: UIColor(red: 1.00, green: 0.99, blue: 0.96, alpha: 1)
        case .cocoa: UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1)
        case .mint: UIColor(red: 0.98, green: 1.00, blue: 0.99, alpha: 1)
        }
    }

    private var darkSurface: UIColor {
        switch self {
        case .warm: UIColor(red: 0.15, green: 0.11, blue: 0.09, alpha: 1)
        case .sage: UIColor(red: 0.10, green: 0.14, blue: 0.11, alpha: 1)
        case .sky: UIColor(red: 0.10, green: 0.13, blue: 0.17, alpha: 1)
        case .lavender: UIColor(red: 0.13, green: 0.11, blue: 0.17, alpha: 1)
        case .sakura: UIColor(red: 0.16, green: 0.10, blue: 0.12, alpha: 1)
        case .honey: UIColor(red: 0.16, green: 0.13, blue: 0.07, alpha: 1)
        case .cocoa: UIColor(red: 0.14, green: 0.12, blue: 0.10, alpha: 1)
        case .mint: UIColor(red: 0.08, green: 0.15, blue: 0.13, alpha: 1)
        }
    }

    private var lightSurfaceMuted: UIColor {
        switch self {
        case .warm: UIColor(red: 0.96, green: 0.91, blue: 0.87, alpha: 1)
        case .sage: UIColor(red: 0.90, green: 0.93, blue: 0.89, alpha: 1)
        case .sky: UIColor(red: 0.89, green: 0.93, blue: 0.96, alpha: 1)
        case .lavender: UIColor(red: 0.93, green: 0.90, blue: 0.96, alpha: 1)
        case .sakura: UIColor(red: 0.97, green: 0.90, blue: 0.92, alpha: 1)
        case .honey: UIColor(red: 0.96, green: 0.92, blue: 0.82, alpha: 1)
        case .cocoa: UIColor(red: 0.91, green: 0.87, blue: 0.83, alpha: 1)
        case .mint: UIColor(red: 0.87, green: 0.94, blue: 0.92, alpha: 1)
        }
    }

    private var darkSurfaceMuted: UIColor {
        switch self {
        case .warm: UIColor(red: 0.20, green: 0.15, blue: 0.12, alpha: 1)
        case .sage: UIColor(red: 0.14, green: 0.20, blue: 0.16, alpha: 1)
        case .sky: UIColor(red: 0.14, green: 0.18, blue: 0.23, alpha: 1)
        case .lavender: UIColor(red: 0.18, green: 0.15, blue: 0.23, alpha: 1)
        case .sakura: UIColor(red: 0.21, green: 0.13, blue: 0.16, alpha: 1)
        case .honey: UIColor(red: 0.21, green: 0.16, blue: 0.08, alpha: 1)
        case .cocoa: UIColor(red: 0.19, green: 0.15, blue: 0.13, alpha: 1)
        case .mint: UIColor(red: 0.11, green: 0.20, blue: 0.18, alpha: 1)
        }
    }

    private func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

private struct AppColorThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = UserDefaults.standard.string(forKey: AppColorTheme.storageKey)
        .flatMap(AppColorTheme.init(rawValue:)) ?? .warm
}

extension EnvironmentValues {
    var appColorTheme: AppColorTheme {
        get { self[AppColorThemeEnvironmentKey.self] }
        set { self[AppColorThemeEnvironmentKey.self] = newValue }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "zoji-preferred-appearance"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .system: L10n.string("跟随系统")
        case .light: L10n.string("浅色")
        case .dark: L10n.string("深色")
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
