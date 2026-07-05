import Foundation

// MARK: - SupabaseConfig

/// Connection coordinates for CanCount's dedicated Supabase project.
///
/// ============================================================
/// SWAP POINT — BOTH VALUES BELOW ARE PLACEHOLDERS.
/// When the dedicated Supabase project exists, replace `url` with
/// the real project URL (https://<project-ref>.supabase.co) and
/// `publishableKey` with that project's publishable (anon) key.
/// ============================================================
///
/// Until then `isConfigured` reads false and every cloud feature in the
/// app stays invisible: no sign-in button, no crew sync, no network calls.
/// The solo path neither knows nor cares that this file exists.
nonisolated enum SupabaseConfig {

    /// PLACEHOLDER — swap for the real project URL. See header comment.
    static let url = URL(string: "https://CANCOUNT-PROJECT-REF.supabase.co")!

    /// PLACEHOLDER — swap for the real publishable key. See header comment.
    /// The publishable key is safe to ship in the binary; row-level security
    /// on the server is what actually guards the data.
    static let publishableKey = "SUPABASE_KEY_PLACEHOLDER"

    /// The single switch the whole cloud layer hides behind. Flips true the
    /// moment a real key lands above — no other code changes required.
    static var isConfigured: Bool { !publishableKey.contains("PLACEHOLDER") }
}
