import SwiftUI

@main
struct SingwellApp: App {
    @State private var session = PracticeSession()
    @State private var settings = AppSettings()
    @State private var progress = ProgressStore()
    @State private var library = TakeLibrary()
    @State private var store = StoreService()
    @State private var auth = AuthService()

    init() {
        // Navigation titles pick up the brand fonts once, app-wide.
        let nav = UINavigationBar.appearance()
        if let large = UIFont(name: "Fraunces-Light", size: 34) { nav.largeTitleTextAttributes = [.font: large] }
        if let inline = UIFont(name: "Sora-SemiBold", size: 17) { nav.titleTextAttributes = [.font: inline] }
        if let tab = UIFont(name: "Sora-Medium", size: 10) {
            UITabBarItem.appearance().setTitleTextAttributes([.font: tab], for: .normal)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(settings)
                .environment(progress)
                .environment(library)
                .environment(store)
                .environment(auth)
        }
    }
}
