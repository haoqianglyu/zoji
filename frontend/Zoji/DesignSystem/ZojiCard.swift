import SwiftUI
import UIKit

struct PetAvatarPreset: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let species: PetSpecies
    let breed: String
    let assetName: String
    let searchAliases: [String]

    var localizedDisplayName: String { L10n.dynamic(displayName) }
    var localizedBreed: String { L10n.dynamic(breed) }
    var localizedSearchAliases: [String] { searchAliases.map(L10n.dynamic) }

    init(
        id: String,
        displayName: String,
        species: PetSpecies,
        breed: String,
        assetName: String,
        searchAliases: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.species = species
        self.breed = breed
        self.assetName = assetName
        self.searchAliases = searchAliases
    }

    static let all: [PetAvatarPreset] = [
        PetAvatarPreset(id: "cat-british-shorthair", displayName: "英短", species: .cat, breed: "英国短毛猫", assetName: "PetAvatarBritishShorthair", searchAliases: ["英国短毛"]),
        PetAvatarPreset(id: "cat-american-shorthair", displayName: "美短", species: .cat, breed: "美国短毛猫", assetName: "PetAvatarAmericanShorthair", searchAliases: ["美国短毛"]),
        PetAvatarPreset(id: "cat-ragdoll", displayName: "布偶", species: .cat, breed: "布偶猫", assetName: "PetAvatarRagdoll"),
        PetAvatarPreset(id: "cat-orange-tabby", displayName: "橘猫", species: .cat, breed: "橘猫", assetName: "PetAvatarOrangeTabby", searchAliases: ["橘子猫"]),
        PetAvatarPreset(id: "cat-siamese", displayName: "暹罗", species: .cat, breed: "暹罗猫", assetName: "PetAvatarSiamese"),
        PetAvatarPreset(id: "cat-maine-coon", displayName: "缅因", species: .cat, breed: "缅因猫", assetName: "PetAvatarMaineCoon"),
        PetAvatarPreset(id: "cat-persian", displayName: "波斯", species: .cat, breed: "波斯猫", assetName: "PetAvatarPersian"),
        PetAvatarPreset(id: "cat-sphynx", displayName: "斯芬克斯", species: .cat, breed: "斯芬克斯猫", assetName: "PetAvatarSphynx", searchAliases: ["无毛猫"]),
        PetAvatarPreset(id: "dog-corgi", displayName: "柯基", species: .dog, breed: "威尔士柯基", assetName: "PetAvatarCorgi"),
        PetAvatarPreset(id: "dog-golden-retriever", displayName: "金毛", species: .dog, breed: "金毛寻回犬", assetName: "PetAvatarGoldenRetriever", searchAliases: ["黄金猎犬"]),
        PetAvatarPreset(id: "dog-shiba-inu", displayName: "柴犬", species: .dog, breed: "柴犬", assetName: "PetAvatarShibaInu"),
        PetAvatarPreset(id: "dog-toy-poodle", displayName: "贵宾", species: .dog, breed: "贵宾犬", assetName: "PetAvatarToyPoodle", searchAliases: ["泰迪"]),
        PetAvatarPreset(id: "dog-labrador-retriever", displayName: "拉布拉多", species: .dog, breed: "拉布拉多寻回犬", assetName: "PetAvatarLabradorRetriever", searchAliases: ["拉拉"]),
        PetAvatarPreset(id: "dog-bichon-frise", displayName: "比熊", species: .dog, breed: "比熊犬", assetName: "PetAvatarBichonFrise"),
        PetAvatarPreset(id: "dog-pomeranian", displayName: "博美", species: .dog, breed: "博美犬", assetName: "PetAvatarPomeranian"),
        PetAvatarPreset(id: "dog-samoyed", displayName: "萨摩耶", species: .dog, breed: "萨摩耶犬", assetName: "PetAvatarSamoyed", searchAliases: ["萨摩"])
    ]

    static func find(_ id: String?) -> PetAvatarPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

struct PetAvatarView: View {
    @Environment(\.appColorTheme) private var theme
    let avatarData: Data?
    var avatarPresetID: String? = nil
    let fallbackSymbol: String
    let size: CGFloat
    var background: Color?
    var foreground: Color?

    var body: some View {
        Group {
            if let avatarData, let image = UIImage(data: avatarData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let preset = PetAvatarPreset.find(avatarPresetID) {
                Image(preset.assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(background ?? theme.accentSoft)
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(foreground ?? theme.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if avatarData == nil,
               PetAvatarPreset.find(avatarPresetID) != nil {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                theme.accent.opacity(0.56),
                                theme.accent.opacity(0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(2, size * 0.04)
                    )
            }
        }
        .contentShape(Circle())
    }
}

struct ZojiCard<Content: View>: View {
    @Environment(\.appColorTheme) private var theme
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String?

    var body: some View {
        HStack {
            Text(L10n.dynamic(title))
                .font(.title3.weight(.bold))
            Spacer()
            if let actionTitle {
                Button(L10n.dynamic(actionTitle)) { }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}
