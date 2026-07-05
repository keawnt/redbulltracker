import Foundation
import SwiftData

// MARK: - OFFProduct

/// A minimal view of an Open Food Facts product — just enough to decide
/// whether the mystery barcode deserves a place in the fridge.
nonisolated struct OFFProduct {
    let barcode: String
    let name: String
    let brand: String?

    var isRedBull: Bool {
        // "Red Bull", "RedBull", "Red-Bull", "REDBULL" — spelling varies
        // across OFF contributors; normalize before matching.
        func normalized(_ text: String) -> String {
            text.lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
        }
        if normalized(name).contains("redbull") { return true }
        if let brand, normalized(brand).contains("redbull") { return true }
        return false
    }
}

/// Tri-state lookup result: a failed request is NOT the same thing as
/// "that's not a Red Bull" — offline users get honesty, not accusations.
nonisolated enum OFFLookup {
    case found(OFFProduct)
    case notFound
    case unavailable
}

// MARK: - OpenFoodFactsClient

enum OpenFoodFactsClient {

    // MARK: Fetch

    /// GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json
    nonisolated static func fetch(barcode: String) async -> OFFLookup {
        guard
            let encoded = barcode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(encoded).json")
        else { return .unavailable }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("CanCount iOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            // OFF answers 404 for unknown barcodes on v2; that's a real
            // "nobody knows this can", not an outage.
            if http.statusCode == 404 { return .notFound }
            guard http.statusCode == 200 else { return .unavailable }

            let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
            guard decoded.status == 1, let payload = decoded.product else { return .notFound }

            let trimmedName = (payload.productName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmedName.isEmpty ? "Unknown Product" : trimmedName
            return .found(OFFProduct(barcode: barcode, name: name, brand: payload.brands))
        } catch {
            return .unavailable
        }
    }

    // MARK: SKU creation

    /// Builds an unverified SKU from an OFF product with sensible 8.4oz/80mg
    /// defaults, silver accent, unknown can style — and inserts it.
    static func makeSKU(from product: OFFProduct, context: ModelContext) -> SKU {
        let loweredName = product.name.lowercased()
        let sugarFree = loweredName.contains("sugarfree")
            || loweredName.contains("sugar free")
            || loweredName.contains("sugar-free")
            || loweredName.contains("zero")

        let lineup: String
        if loweredName.contains("zero") {
            lineup = "zero"
        } else if sugarFree {
            lineup = "sugarfree"
        } else if loweredName.contains("edition") {
            lineup = "editions"
        } else {
            lineup = "original"
        }

        let sku = SKU(
            barcode: product.barcode,
            name: product.name,
            flavor: guessFlavor(from: product.name),
            sizeML: 250,
            sizeOZ: 8.4,
            caffeineMG: 80,
            sugarG: sugarFree ? 0 : 27,
            calories: sugarFree ? 10 : 110,
            sugarFree: sugarFree,
            accentHex: "#C8CDD4",
            canStyle: "unknown",
            verified: false,
            lineup: lineup
        )
        context.insert(sku)
        return sku
    }

    // MARK: Private

    /// Strips the brand-y noise out of an OFF product name to leave a
    /// plausible flavor. "Red Bull Coconut Edition Energy Drink" → "Coconut".
    private static func guessFlavor(from name: String) -> String {
        var working = name
        for noise in ["red bull", "energy drink", "edition", "the "] {
            working = working.replacingOccurrences(
                of: noise, with: "", options: [.caseInsensitive]
            )
        }
        let trimmed = working.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        )
        return trimmed.isEmpty ? "Original" : trimmed
    }
}

// MARK: - Wire format (private)

/// Decodes only the fields we actually use from the OFF v2 payload.
private nonisolated struct OFFResponse: Decodable {
    let status: Int?
    let product: OFFProductPayload?
}

private nonisolated struct OFFProductPayload: Decodable {
    let productName: String?
    let brands: String?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
    }
}
