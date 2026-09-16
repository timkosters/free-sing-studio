import SwiftUI

/// Onboarding once, then the five tabs. Leaving a tab ends any drill running on it.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PracticeSession.self) private var session
    @Environment(ProgressStore.self) private var progress
    @Environment(TakeLibrary.self) private var library
    @Environment(StoreService.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: PracticeMode = .daily

    var body: some View {
        Group {
            if settings.onboarded {
                TabView(selection: $tab) {
                    DailyView().tabItem { Label("Today", systemImage: "flame") }.tag(PracticeMode.daily)
                    SingView().tabItem { Label("Sing", systemImage: "music.mic") }.tag(PracticeMode.sing)
                    TrainView().tabItem { Label("Train", systemImage: "figure.mind.and.body") }.tag(PracticeMode.train)
                    LibraryView().tabItem { Label("Library", systemImage: "waveform") }.tag(PracticeMode.library)
                    ProgressTabView().tabItem { Label("Progress", systemImage: "chart.bar") }.tag(PracticeMode.progress)
                }
                .tint(.voice)
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .onChange(of: tab) { old, new in
            // Drills belong to one surface; switching ends them but keeps the microphone open for Sing/Train.
            if old == .daily { session.stopRoutine(logPartial: true) }
            if old == .train { session.stopWarmup(); session.endQuest() }
            if new == .library || new == .progress { session.finishRecording() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { session.stopEverything() }
        }
        .task {
            session.attach(progress: progress, library: library, settings: settings)
            Haptics.enabled = settings.hapticsEnabled
            await store.load()
            await auth.refreshCredentialState()
        }
    }
}
