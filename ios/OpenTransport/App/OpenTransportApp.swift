import SwiftUI
import UserNotifications
import OpenTransportCore

@main
struct OpenTransportApp: App {
    @State private var model = AppModel()
    @AppStorage("language") private var languageCode = AppModel.defaultLanguage.rawValue
    @AppStorage("theme") private var theme = AppTheme.system.rawValue

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.strings, Strings(Language.of(languageCode)))
                .preferredColorScheme(AppTheme(rawValue: theme)?.colorScheme)
                .task { await model.load() }
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func label(_ s: Strings) -> String {
        switch self {
        case .system: return s.auto
        case .light: return s.light
        case .dark: return s.dark
        }
    }
}

private struct StringsKey: EnvironmentKey {
    static let defaultValue = Strings(.en)
}

extension EnvironmentValues {
    var strings: Strings {
        get { self[StringsKey.self] }
        set { self[StringsKey.self] = newValue }
    }
}
