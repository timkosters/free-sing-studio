import Foundation
import Observation
import AuthenticationServices
import Security

/// A signed-in person. Apple only sends name and email on the first authorization,
/// so both are cached locally the first time and reused afterwards.
struct UserProfile: Codable, Equatable {
    var appleUserID: String
    var fullName: String?
    var email: String?

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

/// Sign in with Apple plus a guest path. Everything stays on device: the Apple user
/// identifier lives in the keychain, the profile in UserDefaults.
@MainActor
@Observable
final class AuthService {
    private(set) var state: AuthState = .signedOut
    var lastError: String?

    private let keychainAccount = "live.singwell.apple-user-id"
    private let profileKey = "singwell-profile-v1"
    private let guestKey = "singwell-guest"

    init() {
        if let id = Keychain.read(account: keychainAccount) {
            let cached = UserDefaults.standard.data(forKey: profileKey).flatMap { try? JSONDecoder().decode(UserProfile.self, from: $0) }
            state = .signedIn(cached ?? UserProfile(appleUserID: id))
        } else if UserDefaults.standard.bool(forKey: guestKey) {
            state = .guest
        }
    }

    /// Apple asks apps to re-check the credential on launch and sign out if it was revoked.
    func refreshCredentialState() async {
        guard case .signedIn(let profile) = state else { return }
        let provider = ASAuthorizationAppleIDProvider()
        let credentialState: ASAuthorizationAppleIDProvider.CredentialState? = await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: profile.appleUserID) { result, _ in
                continuation.resume(returning: result)
            }
        }
        if credentialState == .revoked || credentialState == .notFound {
            signOut()
        }
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                lastError = "Unexpected sign-in response."
                return
            }
            let formatter = PersonNameComponentsFormatter()
            let name = credential.fullName.map { formatter.string(from: $0) }
            let cached = state.profile
            let profile = UserProfile(
                appleUserID: credential.user,
                fullName: (name?.isEmpty == false ? name : nil) ?? cached?.fullName,
                email: credential.email ?? cached?.email
            )
            Keychain.write(credential.user, account: keychainAccount)
            if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: profileKey) }
            UserDefaults.standard.set(false, forKey: guestKey)
            state = .signedIn(profile)
            lastError = nil
        case .failure(let error):
            let code = (error as? ASAuthorizationError)?.code
            if code == .canceled { return }
            lastError = "Sign in with Apple did not complete. Please try again."
        }
    }

    func continueAsGuest() {
        UserDefaults.standard.set(true, forKey: guestKey)
        state = .guest
    }

    func signOut() {
        Keychain.delete(account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: profileKey)
        UserDefaults.standard.set(false, forKey: guestKey)
        state = .signedOut
    }
}

/// Minimal generic-password keychain wrapper.
enum Keychain {
    private static let service = "live.singwell.app"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        delete(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
