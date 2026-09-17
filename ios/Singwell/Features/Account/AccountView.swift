import SwiftUI
import AuthenticationServices

/// Profile, Pro status, reminders, appearance and the legal links App Review expects.
struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(StoreService.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(Color.voice)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.state.profile?.displayName ?? "Guest").font(.headline)
                            Text(auth.state.isAuthenticated ? (auth.state.profile?.email ?? "Signed in with Apple") : "Sign in to keep your account across devices later.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !auth.state.isAuthenticated {
                        SignInWithAppleButton(.signIn, onRequest: { auth.configure($0) }, onCompletion: { auth.handle($0) })
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 44)
                    }
                    if let e = auth.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                }

                Section("Singwell Pro") {
                    HStack {
                        Label(store.isPro ? "Pro is active" : "Free plan", systemImage: store.isPro ? "checkmark.seal.fill" : "seal")
                            .foregroundStyle(store.isPro ? Color.singGreen : .primary)
                        Spacer()
                        if !store.isPro { Button("Upgrade") { showPaywall = true }.buttonStyle(.borderedProminent).tint(.voice).controlSize(.small) }
                    }
                    if store.isPro {
                        Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    }
                    Button("Restore purchases") { Task { await store.restore() } }
                }

                Section("Reminder") {
                    Toggle("Daily practice reminder", isOn: Binding(get: { settings.reminderEnabled }, set: { on in
                        Task {
                            if on {
                                let ok = await Reminders.requestPermission()
                                settings.reminderEnabled = ok
                                if ok { await Reminders.schedule(minuteOfDay: settings.reminderMinuteOfDay) }
                            } else {
                                settings.reminderEnabled = false
                                Reminders.cancel()
                            }
                        }
                    }))
                    if settings.reminderEnabled {
                        DatePicker("Time", selection: Binding(get: { settings.reminderTime }, set: { t in
                            settings.reminderTime = t
                            Task { await Reminders.schedule(minuteOfDay: settings.reminderMinuteOfDay) }
                        }), displayedComponents: .hourAndMinute)
                    }
                }

                Section("Practice") {
                    Picker("Appearance", selection: Bindable(settings).appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Keep screen awake while practising", isOn: Bindable(settings).keepAwake)
                    Toggle("Haptics", isOn: Binding(get: { settings.hapticsEnabled }, set: { settings.hapticsEnabled = $0; Haptics.enabled = $0 }))
                    Toggle("Follow my pitch on the piano roll", isOn: Bindable(settings).followPitch)
                }

                Section("About") {
                    Link("Privacy policy", destination: Legal.privacy)
                    Link("Terms of use", destination: Legal.terms)
                    Link("Support", destination: Legal.support)
                    LabeledContent("Version", value: Legal.version)
                    Text("Audio never leaves your device. There are no analytics or third-party trackers.").font(.caption).foregroundStyle(.secondary)
                }

                if auth.state != .signedOut {
                    Section {
                        Button(auth.state.isAuthenticated ? "Sign out" : "Leave guest mode", role: .destructive) { confirmSignOut = true }
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPaywall) { PaywallView(reason: "Everything Singwell can do, without ceilings.") }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { auth.signOut() }
            } message: { Text("Your takes and history stay on this device.") }
        }
    }
}

enum Legal {
    // TODO: replace with the live pages once the singwell.io site exists.
    static let privacy = URL(string: "https://singwell.io/privacy")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let support = URL(string: "https://singwell.io/support")!
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
