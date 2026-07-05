import Contacts
import CryptoKit
import Foundation
import Observation

// MARK: - ContactsMatcher

/// Answers one question: which of your contacts are already in the game?
///
/// Privacy contract, in order of paranoia:
/// 1. Raw numbers never leave the device — each one is normalized to E.164
///    and SHA-256 hashed locally; only the hashes hit the network.
/// 2. The `match_contacts` RPC is the ONLY cross-user path into the server's
///    directory; there is no way to enumerate it.
/// 3. Address-book enumeration happens off the main actor, and the numbers
///    are discarded the moment they're hashed.
@MainActor
@Observable
final class ContactsMatcher {

    static let shared = ContactsMatcher()

    // MARK: Types

    enum MatchState: Equatable {
        case idle, needsPermission, denied, searching, done, failed(String)
    }

    struct MatchedFriend: Identifiable, Equatable {
        let id: UUID
        let displayName: String
        let crewID: UUID?
        let crewName: String?
    }

    // MARK: State

    private(set) var state: MatchState = .idle
    private(set) var matches: [MatchedFriend] = []

    /// `match_contacts` caps its reply at 100 rows; 400 hashes a request
    /// keeps payloads comfortably small without hammering the RPC.
    private static let chunkSize = 400

    private init() {}

    // MARK: Find friends

    func findFriends() async {
        guard SupabaseConfig.isConfigured, SupabaseAuth.shared.isSignedIn else {
            state = .failed("Backend not connected")
            return
        }

        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            state = .needsPermission
            let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
            guard granted else {
                state = .denied
                return
            }
        case .denied, .restricted:
            state = .denied
            return
        default:
            break // authorized / limited — off we go
        }

        state = .searching
        do {
            let token = try await SupabaseAuth.shared.validAccessToken()
            let hashes = try await Self.collectContactHashes()

            var found: [MatchedFriend] = []
            var seen = Set<UUID>()
            for chunkStart in stride(from: 0, to: hashes.count, by: Self.chunkSize) {
                let chunk = Array(hashes[chunkStart..<min(chunkStart + Self.chunkSize, hashes.count)])
                let data = try await SupabaseAPI.rpc(
                    "match_contacts", params: ["p_hashes": chunk], accessToken: token
                )
                for row in try JSONDecoder().decode([MatchRow].self, from: data)
                where seen.insert(row.userID).inserted {
                    found.append(MatchedFriend(
                        id: row.userID,
                        displayName: row.displayName,
                        crewID: row.crewID,
                        crewName: row.crewName
                    ))
                }
            }

            matches = found.sorted { $0.displayName < $1.displayName }
            state = .done
        } catch {
            print("ContactsMatcher: match failed — \(error)")
            state = .failed("Couldn't reach the server. Try again in a bit.")
        }
    }

    // MARK: Publish my number

    /// Files YOUR hashed number in the directory so friends can find you.
    /// Same normalization, same hash — anything under 10 digits isn't a
    /// phone number and gets thrown out.
    func publishMyNumber(_ rawPhone: String) async throws {
        guard SupabaseConfig.isConfigured else { throw SupabaseAuthError.notConfigured }
        guard let normalized = Self.normalize(rawPhone) else {
            throw ContactsMatcherError.invalidPhoneNumber
        }
        let token = try await SupabaseAuth.shared.validAccessToken()
        _ = try await SupabaseAPI.rpc(
            "set_phone_hash", params: ["p_hash": Self.sha256Hex(normalized)], accessToken: token
        )
    }

    // MARK: Contact enumeration (off the main actor)

    /// Walks the address book on a background executor, hashing as it goes.
    /// Returns deduped, sorted hashes; raw numbers never leave this function.
    @concurrent
    private nonisolated static func collectContactHashes() async throws -> [String] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(
            keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor]
        )

        var hashes = Set<String>()
        try store.enumerateContacts(with: request) { contact, _ in
            for phone in contact.phoneNumbers {
                guard let normalized = normalize(phone.value.stringValue) else { continue }
                hashes.insert(sha256Hex(normalized))
            }
        }
        return hashes.sorted()
    }

    // MARK: Normalization + hashing

    /// "(303) 555-0142" → "+13035550142". Ten digits get the NANP country
    /// code; 11–15 digits pass straight through; anything else is not a
    /// phone number, whatever the contact card claims.
    private nonisolated static func normalize(_ raw: String) -> String? {
        var digits = raw.filter { $0.isASCII && $0.isNumber }
        if digits.count == 10 { digits = "1" + digits }
        guard (11...15).contains(digits.count) else { return nil }
        return "+" + digits
    }

    /// Lowercased SHA-256 hex — exactly what `set_phone_hash` validates.
    private nonisolated static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - Errors

nonisolated enum ContactsMatcherError: Error {
    case invalidPhoneNumber
}

// MARK: - Wire format (private)

/// One row from `match_contacts` — crew fields are null for members who
/// haven't joined a crew yet.
private nonisolated struct MatchRow: Decodable {
    let userID: UUID
    let displayName: String
    let crewID: UUID?
    let crewName: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case crewID = "crew_id"
        case crewName = "crew_name"
    }
}
