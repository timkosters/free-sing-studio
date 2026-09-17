import SwiftUI
import AuthenticationServices

/// Three short pages, then the microphone, then sign in or continue as a guest.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthService.self) private var auth
    @State private var page = 0
    @State private var micGranted: Bool?

    private let pages: [(icon: String, title: String, text: String)] = [
        ("waveform.path.ecg", "See your voice", "Sing anything and watch the note appear on a piano roll in real time. Tap a key to hear the reference."),
        ("flame.fill", "Ten minutes a day", "A guided routine built from what vocal coaches actually ask for: breath, clean tone, and the bridge between registers."),
        ("waveform", "Keep your takes", "Record with the pitch trail attached, listen back, and hear the difference in a month. Audio never leaves your phone."),
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    VStack(spacing: 18) {
                        Image(systemName: p.icon).font(.system(size: 72)).foregroundStyle(Color.voice)
                        Text(p.title).font(.display(.largeTitle)).multilineTextAlignment(.center)
                        Text(p.text).font(.sora(.body)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                    }
                    .tag(i)
                    .padding(.bottom, 40)
                }
                finalPage.tag(pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            if page < pages.count {
                Button { withAnimation { page += 1 } } label: { Text("Continue").bold().frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.voice).controlSize(.large)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 24)
        .background(Color.pageBackground)
    }

    private var finalPage: some View {
        VStack(spacing: 18) {
            Image(systemName: "mic.fill").font(.system(size: 64)).foregroundStyle(Color.voice)
            Text("Your voice stays yours").font(.display(.largeTitle)).multilineTextAlignment(.center)
            Text("Singwell needs the microphone to hear your pitch. Nothing is uploaded, ever.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            if micGranted == nil {
                Button { Task { micGranted = await AudioEngine.requestMicrophonePermission() } } label: {
                    Label("Allow microphone", systemImage: "mic").bold().frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.voice).controlSize(.large)
            } else if micGranted == false {
                Text("Microphone access was declined. You can turn it on later in Settings › Singwell.").font(.sora(.footnote)).foregroundStyle(.orange).multilineTextAlignment(.center)
            } else {
                Label("Microphone ready", systemImage: "checkmark.circle.fill").foregroundStyle(Color.singGreen)
            }
            VStack(spacing: 10) {
                SignInWithAppleButton(.continue, onRequest: { auth.configure($0) }, onCompletion: { auth.handle($0) })
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                Text("Same account as singwell on the web: one streak, one profile, everywhere.")
                    .font(.sora(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Continue without an account") { auth.continueAsGuest(); settings.onboarded = true }
                    .font(.sora(.subheadline))
                if let e = auth.lastError { Text(e).font(.sora(.caption)).foregroundStyle(.red) }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .onChange(of: auth.state) { _, new in if new.isAuthenticated { settings.onboarded = true } }
    }
}
