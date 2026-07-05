import Foundation

// MARK: - SupabaseAPIError

/// A non-2xx answer from PostgREST, body included. The body is the raw
/// Postgres error message — keep it intact, it names the exact constraint
/// or policy that said no.
nonisolated struct SupabaseAPIError: Error, CustomStringConvertible {
    let statusCode: Int
    let body: String

    var description: String { "Supabase HTTP \(statusCode): \(body)" }
}

// MARK: - SupabaseAPI

/// Thin PostgREST helpers: call a database function, insert rows. No retry
/// logic, no caching, no opinions — callers own their error handling, and
/// `SupabaseAuth.validAccessToken()` owns the token these attach.
enum SupabaseAPI {

    // MARK: RPC

    /// POST {url}/rest/v1/rpc/{fn} with a JSON params object. Returns the
    /// raw response body — RPCs return rows, callers decode their own shape.
    nonisolated static func rpc(
        _ fn: String,
        params: [String: Any],
        accessToken: String
    ) async throws -> Data {
        var request = authedRequest(
            url: SupabaseConfig.url.appending(path: "rest/v1/rpc/\(fn)"),
            accessToken: accessToken
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        return try await perform(request)
    }

    // MARK: Insert

    /// POST {url}/rest/v1/{table} with a JSON array of rows. Pass
    /// `onConflict` (a column name) to make the insert idempotent —
    /// duplicates are silently skipped server-side, so re-syncing the same
    /// rows costs nothing.
    nonisolated static func insert(
        table: String,
        rows: [[String: Any]],
        accessToken: String,
        onConflict: String?
    ) async throws {
        var url = SupabaseConfig.url.appending(path: "rest/v1/\(table)")
        var prefer = "return=minimal"
        if let onConflict {
            url.append(queryItems: [URLQueryItem(name: "on_conflict", value: onConflict)])
            prefer = "resolution=ignore-duplicates,return=minimal"
        }

        var request = authedRequest(url: url, accessToken: accessToken)
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: rows)
        try await perform(request)
    }

    // MARK: Private

    private nonisolated static func authedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    @discardableResult
    private nonisolated static func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAPIError(statusCode: -1, body: "non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseAPIError(
                statusCode: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }
}
