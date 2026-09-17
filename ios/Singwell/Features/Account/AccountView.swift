import SwiftUI
import AuthenticationServices
import SingwellCore

/// Account, Pro status, your voice profile, reminders, appearance and legal links.
struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(StoreService.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(ProgressStore.self) private var progress
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @State private var confirmSignOut = false
    @State private var email = ""
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                Section("Your voice") {
                    if progress.profile.isEmpty {
                        Text("Tell the routine where your break sits and what you are working on. The steps rewrite themselves around it.")
                            .font(.sora(.footnote)).foregroundStyle(.secondary)
                    } else {
                        profileSummary
                    }
                    Button(progress.profile.isEmpty ? "Set up your voice profile" : "Edit voice profile") { showProfile = true }
                }
                Section("Singwell Pro") {
                    HStack {
                        Label(store.isPro ? "Pro is active" : "Free plan", systemImage: store.isPro ? "checkmark.seal.fill" : "seal")
                            .foregroundStyle(store.isPro ? Color.singGreen : .primary)
                        Spacer()
                        if !store.isPro { Button("Upgrade") { showPaywall = true }.buttonStyle(.borderedProminent).tint(.voice).controlSize(.small) }
                    }
                    if store.isPro { Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!) }
                    Button("Restore purchases") { Task { await store.restore() } }
                }
                Section("Reminder") {
                    Toggle("Daily practice reminder", isOn: Binding(get: { settings.reminderEnabled }, set: { on in
                        Task {
                            if on {
                                let ok = await Reminders.requestPermission()
                                settings.reminderEnabled = ok
                                if ok { await Reminders.schedule(minuteOfDay: settings.reminderMinuteOfDay) }
                            } else { settings.reminderEnabled = false; Reminders.cancel() }
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
                    Picker("Appearance", selection: Bindable(settings).appearance) { ForEach(Appearance.allCases) { Text($0.label).tag($0) } }
                    Toggle("Keep screen awake while practising", isOn: Bindable(settings).keepAwake)
                    Toggle("Haptics", isOn: Binding(get: { settings.hapticsEnabled }, set: { settings.hapticsEnabled = $0; Haptics.enabled = $0 }))
                    Toggle("Follow my pitch on the piano roll", isOn: Bindable(settings).followPitch)
                }
                Section("About") {
                    Link("Privacy policy", destination: Legal.privacy)
                    Link("Terms of use", destination: Legal.terms)
                    Link("Support", destination: Legal.support)
                    Link("Singwell on the web", destination: Legal.web)
                    LabeledContent("Version", value: Legal.version)
                    Text("Audio never leaves your device. Only your practice calendar and voice profile sync when you sign in.").font(.sora(.caption)).foregroundStyle(.secondary)
                }
                if auth.state != .signedOut {
                    Section { Button(auth.state.isAuthenticated ? "Sign out" : "Leave guest mode", role: .destructive) { confirmSignOut = true } }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPaywall) { PaywallView(reason: "Everything Singwell can do, without ceilings.") }
            .sheet(isPresented: $showProfile) { VoiceProfileEditor() }
            .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { progress.disconnect(); auth.signOut() }
            } message: { Text("Your takes and history stay on this device. Your synced calendar stays in your account.") }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(Color.voice)
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.state.profile?.displayName ?? "Guest").font(.sora(.headline, .semibold))
                    Text(auth.state.isAuthenticated ? "Signed in. Streak and voice profile sync with singwell on the web." : "Sign in to keep one streak across your phone and the web.")
                        .font(.sora(.caption)).foregroundStyle(.secondary)
                }
            }
            if auth.state.isAuthenticated {
                HStack {
                    Label(progress.syncing ? "Syncing…" : (progress.lastSyncedAt.map { "Synced \($0.formatted(.relative(presentation: .named)))" } ?? "Not synced yet"), systemImage: progress.syncing ? "arrow.triangle.2.circlepath" : "checkmark.icloud")
                        .font(.sora(.footnote)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Sync now") { Task { await progress.sync() } }.disabled(progress.syncing).font(.sora(.footnote))
                }
                if let e = progress.lastSyncError { Text(e).font(.sora(.caption)).foregroundStyle(.red) }
            } else if auth.backendAvailable {
                SignInWithAppleButton(.signIn, onRequest: { auth.configure($0) }, onCompletion: { auth.handle($0) })
                    .signInWithAppleButtonStyle(.black).frame(height: 44)
                if let pending = auth.pendingEmail {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Check your inbox", systemImage: "envelope.open").font(.sora(.subheadline, .semibold))
                        Text("We sent a sign-in link to \(pending). Open it on this phone and you will land back here signed in.").font(.sora(.caption)).foregroundStyle(.secondary)
                        Button("Use a different email") { auth.cancelPendingEmail() }.font(.sora(.caption))
                    }
                } else {
                    HStack {
                        TextField("Email for a sign-in link", text: $email)
                            .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                        Button("Send") { Task { await auth.sendSignInLink(to: email) } }
                            .disabled(auth.busy || !Sync.looksLikeEmail(email))
                    }
                }
            }
            if let e = auth.lastError { Text(e).font(.sora(.caption)).foregroundStyle(.red) }
        }
    }

    private var profileSummary: some View {
        let p = progress.profile
        return VStack(alignment: .leading, spacing: 4) {
            if let lo = p.low, let hi = p.high { Text("Range \(Pitch.noteName(Double(lo))) – \(Pitch.noteName(Double(hi)))") }
            if let a = p.breakLow, let b = p.breakHigh { Text("Break \(Pitch.noteName(Double(a))) – \(Pitch.noteName(Double(b)))") }
            if !p.songs.isEmpty { Text("Working on: \(p.songs.joined(separator: ", "))") }
            if let line = p.hardLine { Text("Hard line: \u{201C}\(line)\u{201D}").italic() }
        }
        .font(.sora(.subheadline))
    }
}

/// Range, break, songs and the one hard line. Saved locally and, when signed in, to the shared account.
struct VoiceProfileEditor: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(PracticeSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Profile()
    @State private var hasRange = false
    @State private var hasBreak = false
    @State private var low = 45
    @State private var high = 72
    @State private var breakLow = 63
    @State private var breakHigh = 67
    @State private var songsText = ""
    @State private var hardLine = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("I know my comfortable range", isOn: $hasRange)
                    if hasRange {
                        NoteStepper(title: "Lowest", midi: $low, range: 24...96, onPlay: { session.playKey($0) })
                        NoteStepper(title: "Highest", midi: $high, range: 24...96, onPlay: { session.playKey($0) })
                    }
                } footer: { Text("The Progress tab measures this for you over time; this is what you already know.") }
                Section {
                    Toggle("I know where my break sits", isOn: $hasBreak)
                    if hasBreak {
                        NoteStepper(title: "Break starts", midi: $breakLow, range: 24...96, onPlay: { session.playKey($0) })
                        NoteStepper(title: "Break ends", midi: $breakHigh, range: 24...96, onPlay: { session.playKey($0) })
                    }
                } footer: { Text("Where chest voice hands over to head voice. The bridge step rewrites itself around it.") }
                Section("Songs you are working on") {
                    TextField("One per line", text: $songsText, axis: .vertical).lineLimit(2...6)
                }
                Section("The one hard line") {
                    TextField("The phrase that keeps going wrong", text: $hardLine, axis: .vertical).lineLimit(1...3)
                }
            }
            .navigationTitle("Your voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() }.bold() }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        let p = progress.profile
        if let l = p.low, let h = p.high { hasRange = true; low = l; high = h }
        if let a = p.breakLow, let b = p.breakHigh { hasBreak = true; breakLow = a; breakHigh = b }
        songsText = p.songs.joined(separator: "\n")
        hardLine = p.hardLine ?? ""
    }

    private func save() {
        var p = Profile()
        if hasRange { p.low = min(low, high); p.high = max(low, high) }
        if hasBreak { p.breakLow = min(breakLow, breakHigh); p.breakHigh = max(breakLow, breakHigh) }
        p.songs = Array(songsText.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(12))
        let line = hardLine.trimmingCharacters(in: .whitespacesAndNewlines)
        p.hardLine = line.isEmpty ? nil : String(line.prefix(200))
        progress.setProfile(p)
    }
}

enum Legal {
    // TODO: swap for the live pages once singwell.io is up.
    static let privacy = URL(string: "https://singwell.io/privacy")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let support = URL(string: "https://singwell.io/support")!
    static let web = URL(string: "https://free-sing-studio.vercel.app")!
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
