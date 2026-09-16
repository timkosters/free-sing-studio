import SwiftUI

@main
struct SingwellApp: App {
    @State private var session = PracticeSession()
    @State private var settings = AppSettings()
    @State private var progress = ProgressStore()
    @State private var library = TakeLibrary()
    @State private var store = StoreService()
    @State private var auth = AuthService()

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
