import Foundation

nonisolated enum AppPage: Int, CaseIterable, Identifiable, Sendable {
    case study, profile, pet

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .study: "Studium"
        case .profile: "Profil"
        case .pet: "Akvárium"
        }
    }

    var symbol: String {
        switch self {
        case .study: "timer"
        case .profile: "person.crop.circle.fill"
        case .pet: "water.waves"
        }
    }
}
