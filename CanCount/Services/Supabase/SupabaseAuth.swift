import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import SwiftData

// MARK: - SupabaseAuthError

enum SupabaseAuthError: Error {
    case notConfigured
    case notSignedIn
    case appleFailed
    case exchangeFailed
}

// MARK: - SupabaseAuth

/// Native Sign in with Apple → Supabase session broker.
///
/// The dance: `configure(request:)` stamps Apple's request with a hashed
/// nonce, `completeSignIn(with:)` trades the resulting identity token for a
/// Supabase session, and `validAccessToken()` quietly keeps that session
/// alive forever after. Refresh tokens live in the Keychain; access tokens
/// live in memory and nowhere else. Nothing in this file logs a token.
///
/// With the placeholder config every entry point is a no-op or a
/// `.notConfigured` throw — the solo path never gets here.
@MainActor
@Observable
final class SupabaseAuth: NSObject {

    static let shared = SupabaseAuth()

    // MARK: Observable state

    private(set) var userID: UUID?
    private(set) var accountName: String?

    var isSignedIn: Bool { userID != nil }

    // MARK: Private state

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessTokenExpiry: Date?
    @ObservationIgnored private var rawNonce: String?
    @ObservationIgnored private var refreshTask: Task<String, Error>?

    // MARK: Storage keys

    private static let userIDKey = "supabase.userID"
    private static let accountNameKey = "supabase.accountName"
    private nonisolated static let keychainService = "com.keawn.cancount.supabase"
    private nonisolated static let keychainAccount = "refresh-token"

    override private init() {
        // Rehydrate identity from UserDefaults so the UI shows the signed-in
        // state instantly at launch; restoreSession() validates it for real.
        if let stored = UserDefaults.standard.string(forKey: Self.userIDKey) {
            userID = UUID(uuidString: stored)
        }
        accountName = UserDefaults.standard.string(forKey: Self.accountNameKey)
        super.init()
    }

    // MARK: Session restore

    /// Called once at launch. If a refresh token survived in the Keychain,
    /// trade it for a fresh session; if the server says it's dead (revoked),
    /// fall back to signed-out without a word. Never blocks or alarms launch.
    func restoreSession() async {
        guard SupabaseConfig.isConfigured else { return }
        guard Self.storedRefreshToken() != nil else {
            // Defaults say signed in but the Keychain disagrees — the
            // Keychain wins.
            if userID != nil { clearLocalState() }
            return
        }
        _ = try? await refreshedAccessToken()
    }

    // MARK: Sign in with Apple

    /// Stamp the Apple request: name scope plus a hashed one-shot nonce.
    /// The raw nonce stays here for the token exchange; Apple only ever
    /// sees its SHA-256.
    func configure(request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]

        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        }
        let raw = bytes.map { String(format: "%02x", $0) }.joined()
        rawNonce = raw
        request.nonce = SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Trade Apple's identity token for a Supabase session, persist it, and
    /// put a display name on the server profile. Apple only shares the name
    /// on the very first authorization, so it gets captured here or never.
    func completeSignIn(with result: Result<ASAuthorization, Error>) async throws {
        guard SupabaseConfig.isConfigured else { throw SupabaseAuthError.notConfigured }

        let authorization: ASAuthorization
        switch result {
        case .success(let value): authorization = value
        case .failure: throw SupabaseAuthError.appleFailed
        }

        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = rawNonce
        else { throw SupabaseAuthError.appleFailed }
        rawNonce = nil

        let appleName = credential.fullName.flatMap { components -> String? in
            let formatted = PersonNameComponentsFormatter
                .localizedString(from: components, style: .default)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return formatted.isEmpty ? nil : formatted
        }

        let session: SupabaseSession
        do {
            session = try await Self.requestSession(
                grantType: "id_token",
                body: ["provider": "apple", "id_token": idToken, "nonce": nonce]
            )
        } catch let error as SupabaseAuthError {
            throw error
        } catch {
            throw SupabaseAuthError.exchangeFailed
        }

        adopt(session)

        // Display name pecking order: whatever the user already calls
        // themselves locally, then Apple's word for it, then the default.
        let displayName = localDisplayName() ?? appleName ?? "Racer"
        accountName = displayName
        UserDefaults.standard.set(displayName, forKey: Self.accountNameKey)

        // Best effort — the signup trigger already made a profile row, and a
        // naming hiccup should never sink a successful sign-in.
        try? await Self.upsertProfile(
            userID: session.user.id,
            displayName: displayName,
            accessToken: session.accessToken
        )
    }

    // MARK: Sign out

    /// Tell the server (best effort), then forget everything locally.
    func signOut() async {
        if SupabaseConfig.isConfigured, let token = try? await validAccessToken() {
            await Self.postLogout(accessToken: token)
        }
        Self.deleteRefreshToken()
        clearLocalState()
    }

    // MARK: Access token

    /// The token every API call rides on. Returns the cached one while it
    /// has at least a minute left; otherwise refreshes — coalescing
    /// concurrent callers onto a single network round trip.
    func validAccessToken() async throws -> String {
        guard SupabaseConfig.isConfigured else { throw SupabaseAuthError.notConfigured }
        if let token = accessToken, let expiry = accessTokenExpiry,
           expiry.timeIntervalSinceNow > 60 {
            return token
        }
        return try await refreshedAccessToken()
    }

    private func refreshedAccessToken() async throws -> String {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        let task = Task<String, Error> { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = Self.storedRefreshToken() else {
            clearLocalState()
            throw SupabaseAuthError.notSignedIn
        }
        do {
            let session = try await Self.requestSession(
                grantType: "refresh_token",
                body: ["refresh_token": refreshToken]
            )
            adopt(session)
            return session.accessToken
        } catch let failure as AuthHTTPFailure where failure.isRejection {
            // The server says this session is dead — revoked, or rotated
            // away by another device. Local state follows suit.
            Self.deleteRefreshToken()
            clearLocalState()
            throw SupabaseAuthError.notSignedIn
        } catch let error as SupabaseAuthError {
            throw error
        } catch {
            // Transient (offline, 5xx): keep the refresh token and let the
            // next caller retry.
            throw SupabaseAuthError.exchangeFailed
        }
    }

    // MARK: Session adoption

    /// Persist a fresh session: access token in memory, rotated refresh
    /// token in the Keychain, identity in UserDefaults.
    private func adopt(_ session: SupabaseSession) {
        accessToken = session.accessToken
        accessTokenExpiry = Date(timeIntervalSinceNow: TimeInterval(session.expiresIn))
        userID = session.user.id
        Self.storeRefreshToken(session.refreshToken)
        UserDefaults.standard.set(session.user.id.uuidString, forKey: Self.userIDKey)
    }

    private func clearLocalState() {
        userID = nil
        accountName = nil
        accessToken = nil
        accessTokenExpiry = nil
        UserDefaults.standard.removeObject(forKey: Self.userIDKey)
        UserDefaults.standard.removeObject(forKey: Self.accountNameKey)
    }

    /// The name the user already goes by locally, if it's a real one.
    /// "You" is the untouched default, not an identity.
    private func localDisplayName() -> String? {
        guard let container = CanCountApp.sharedContainer else { return nil }
        let name = UserProfile.current(in: container.mainContext).displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty || name == "You") ? nil : name
    }

    // MARK: Network (nonisolated)

    /// POST {url}/auth/v1/token?grant_type={grantType}. Both grants —
    /// id_token exchange and refresh — speak the same envelope.
    private nonisolated static func requestSession(
        grantType: String,
        body: [String: String]
    ) async throws -> SupabaseSession {
        guard SupabaseConfig.isConfigured else { throw SupabaseAuthError.notConfigured }

        let url = SupabaseConfig.url
            .appending(path: "auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: grantType)])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.exchangeFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthHTTPFailure(statusCode: http.statusCode)
        }
        return try JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    /// Upsert the profile display name. Merge, not ignore — the signup
    /// trigger already created the row and this call gets the final say.
    private nonisolated static func upsertProfile(
        userID: UUID,
        displayName: String,
        accessToken: String
    ) async throws {
        let url = SupabaseConfig.url
            .appending(path: "rest/v1/profiles")
            .appending(queryItems: [URLQueryItem(name: "on_conflict", value: "id")])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            ["id": userID.uuidString, "display_name": displayName]
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw SupabaseAuthError.exchangeFailed
        }
    }

    /// POST {url}/auth/v1/logout. Fire and forget — local sign-out proceeds
    /// whether or not the server picked up.
    private nonisolated static func postLogout(accessToken: String) async {
        var request = URLRequest(url: SupabaseConfig.url.appending(path: "auth/v1/logout"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: Keychain (nonisolated)

    private nonisolated static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private nonisolated static func storedRefreshToken() -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func storeRefreshToken(_ token: String) {
        let data = Data(token.utf8)
        var query = keychainQuery()
        let update = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            _ = SecItemAdd(query as CFDictionary, nil)
        }
    }

    private nonisolated static func deleteRefreshToken() {
        _ = SecItemDelete(keychainQuery() as CFDictionary)
    }
}

// MARK: - Wire format (private)

/// The session envelope GoTrue returns for both grant types. Only the
/// fields the client actually uses.
private nonisolated struct SupabaseSession: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User

    nonisolated struct User: Decodable {
        let id: UUID
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

/// A non-2xx from the auth endpoint, status attached — 4xx means the
/// session is genuinely dead, anything else is weather.
private nonisolated struct AuthHTTPFailure: Error {
    let statusCode: Int

    var isRejection: Bool { (400...404).contains(statusCode) }
}
