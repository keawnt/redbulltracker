import Foundation
import SwiftData

/// One row of the bundled can database. The JSON uses snake_case keys,
/// so we map them explicitly rather than trusting a global decoding strategy.
private struct SeedSKU: Decodable {
    let barcode: String
    let name: String
    let flavor: String
    let sizeML: Int
    let sizeOZ: Double
    let caffeineMG: Int
    let sugarG: Double
    let calories: Int
    let sugarFree: Bool
    let accentHex: String
    let canStyle: String
    let verified: Bool

    enum CodingKeys: String, CodingKey {
        case barcode
        case name
        case flavor
        case sizeML = "size_ml"
        case sizeOZ = "size_oz"
        case caffeineMG = "caffeine_mg"
        case sugarG = "sugar_g"
        case calories
        case sugarFree = "sugar_free"
        case accentHex = "accent_hex"
        case canStyle = "can_style"
        case verified
    }
}

/// Loads `redbull_skus.json` into SwiftData on first launch (and tops up
/// whenever the bundled database gains new cans). Upsert-by-barcode: rows
/// already in the store are never overwritten, so scan-created SKUs from
/// Open Food Facts and any future user corrections survive every relaunch.
enum SeedLoader {
    static func seedIfNeeded(container: ModelContainer) {
        guard let url = Bundle.main.url(forResource: "redbull_skus", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seeds = try? JSONDecoder().decode([SeedSKU].self, from: data)
        else {
            // The fridge shipped empty. Ship-stopping in Debug, silent in Release
            // (the app still works — scans fall back to Open Food Facts).
            assertionFailure("SeedLoader: redbull_skus.json is missing or malformed.")
            return
        }

        let context = container.mainContext

        // One fetch for all known barcodes beats N per-barcode lookups.
        let existingBarcodes: Set<String>
        do {
            existingBarcodes = Set(try context.fetch(FetchDescriptor<SKU>()).map(\.barcode))
        } catch {
            // If the fetch itself fails, don't risk violating the unique
            // barcode constraint with blind inserts. Try again next launch.
            return
        }

        var inserted = 0
        for seed in seeds where !existingBarcodes.contains(seed.barcode) {
            let sku = SKU(
                barcode: seed.barcode,
                name: seed.name,
                flavor: seed.flavor,
                sizeML: seed.sizeML,
                sizeOZ: seed.sizeOZ,
                caffeineMG: seed.caffeineMG,
                sugarG: seed.sugarG,
                calories: seed.calories,
                sugarFree: seed.sugarFree,
                accentHex: seed.accentHex,
                canStyle: seed.canStyle,
                verified: seed.verified
            )
            context.insert(sku)
            inserted += 1
        }

        guard inserted > 0 else { return }
        try? context.save()
    }
}
