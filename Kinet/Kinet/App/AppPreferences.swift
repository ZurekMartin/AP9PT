import Foundation
import KinetDesign
import Observation

@MainActor
@Observable
final class AppPreferences {
    var isDemoMode: Bool {
        didSet { store.save(isDemoMode, "app.demoMode") }
    }
    var demoSeeded: Bool {
        didSet { store.save(demoSeeded, "app.demoSeeded") }
    }
    var permissionsAsked: Bool {
        didSet { store.save(permissionsAsked, "app.permissionsAsked") }
    }
    var guideCompleted: Bool {
        didSet { store.save(guideCompleted, "app.guideCompleted") }
    }

    @ObservationIgnored private let store: SettingsStore

    init(defaults: UserDefaults) {
        store = SettingsStore(defaults)
        isDemoMode = store.value("app.demoMode", default: false)
        demoSeeded = store.value("app.demoSeeded", default: false)
        permissionsAsked = store.value("app.permissionsAsked", default: false)
        guideCompleted = store.value("app.guideCompleted", default: false)
    }
}
