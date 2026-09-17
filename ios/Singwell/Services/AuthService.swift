import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import Supabase
import SingwellCore

/// A signed-in person, as the shared backend knows them.
struct UserProfile: Codable, Equatable {
    var id: UUID
    var email: String?
    var fullName: String?

    var displayName: String {
        if let fullName, !fullName.isEmpty { return fullName }
        if let email, !email.isEmpty { return email }
        return "Singer"
    }
}

enum AuthState: Equatable {
    case signedOut
    case guest
    case signedIn(UserProfile)

    var isAuthenticated: Bool { if case .signedIn = self { return true } else { return false } }
    var profile: UserProfile? { if case .signedIn(let p) = self { return p } else { return nil } }
}

/// Accounts live in the same Supabase project as the web app, so one sign-in works on both.
/// Two ways in: Sign in with Apple (native, token handed to Supabase) and an emailed link that
/// opens the app through its `singwell://` scheme. Guest mode stays fully functional offline.
@MainActor
@Observable
final class AuthService {
    private(set) var state: AuthState = .signedOut
    var lastError: String?
    /// Set after a sign-in email was sent so the UI can say "check your inbox".
    private(set) var pendingEmail: String?
    private(set) var busy = false
    /// Fires once per successful sign-in so stores can pull and merge.
    var onSignedIn: ((UserProfile) -> Void)?

    private let guestKey = "singwell-guest"
    private let nameKey = "singwell-apple-name"
    private var currentNonce: String?
    private var listener: Task<Void, Never>?

    init() {
        if UserDefaults.standard.bool(forKey: guestKey) { state = .guest }
        listener = Task { [weak self] in
            guard let client = Backend.client else { return }
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session { self.apply(session, announce: event == .signedIn) }
                case .signedOut:
                    if self.state.isAuthenticated { self.state = .signedOut }
                default: break
                }
            }
        }
    }

    private func apply(_ session: Session, announce: Bool) {
        let cachedName = UserDefaults.standard.string(forKey: nameKey)
        let profile = UserProfile(id: session.user.id, email: session.user.email, fullName: cachedName)
        let wasAuthenticated = state.isAuthenticated
        state = .signedIn(profile)
        UserDefaults.standard.set(false, forKey: guestKey)
        pendingEmail = nil
        lastError = nil
        if announce || !wasAuthenticated { onSignedIn?(profile) }
    }

    var backendAvailable: Bool { Backend.configured }

    // MARK: Sign in with Apple

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.nonce = Self.sha256(nonce)
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                lastError = "Unexpected sign-in response."
                return
            }
            if let components = credential.fullName {
                let name = PersonNameComponentsFormatter().string(from: components)
                if !name.isEmpty { UserDefaults.standard.set(name, forKey: nameKey) }
            }
            guard let client = Backend.client else { lastError = "Accounts are not configured in this build."; return }
            busy = true
            Task {
                defer { busy = false }
                do {
                    _ = try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
                } catch {
                    lastError = Sync.authMessage(error.localizedDescription)
                }
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = "Sign in with Apple did not complete. Please try again."
        }
    }

    // MARK: Email link

    func sendSignInLink(to email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Sync.looksLikeEmail(trimmed) else { lastError = "That does not look like an email address."; return }
        guard let client = Backend.client else { lastError = "Accounts are not configured in this build."; return }
        busy = true
        defer { busy = false }
        do {
            try await client.auth.signInWithOTP(email: trimmed, redirectTo: Backend.redirect)
            pendingEmail = trimmed
            lastError = nil
        } catch {
            lastError = Sync.authMessage(error.localizedDescription)
        }
    }

    /// The emailed link opens the app; hand its tokens to Supabase.
    func handleOpen(_ url: URL) {
        guard url.scheme == "singwell", let client = Backend.client else { return }
        Task {
            do { _ = try await client.auth.session(from: url) }
            catch { lastError = Sync.authMessage(error.localizedDescription) }
        }
    }

    func cancelPendingEmail() { pendingEmail = nil }

    func continueAsGuest() {
        UserDefaults.standard.set(true, forKey: guestKey)
        state = .guest
    }

    func signOut() {
        UserDefaults.standard.set(false, forKey: guestKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        state = .signedOut
        Task { try? await Backend.client?.auth.signOut() }
    }

    // MARK: Nonce helpers

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status != errSecSuccess { fatalError("Unable to generate nonce.") }
            if random < charset.count { result.append(charset[Int(random)]); remaining -= 1 }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
