import Foundation
import SwiftData
import SwiftUI

@Model
final class SKU {
    @Attribute(.unique) var barcode: String
    var name: String
    var flavor: String
    var sizeML: Int
    var sizeOZ: Double
    var caffeineMG: Int
    var sugarG: Double
    var calories: Int
    var sugarFree: Bool
    var accentHex: String
    var canStyle: String
    var verified: Bool
    /// Which Red Bull family this can belongs to:
    /// "original" | "sugarfree" | "zero" | "editions".
    /// Defaults to "" so pre-lineup stores migrate cleanly; SeedLoader
    /// backfills known barcodes on launch.
    var lineup: String = ""
    @Relationship(deleteRule: .cascade, inverse: \CanLog.sku) var logs: [CanLog] = []

    init(barcode: String, name: String, flavor: String, sizeML: Int, sizeOZ: Double,
         caffeineMG: Int, sugarG: Double, calories: Int, sugarFree: Bool,
         accentHex: String, canStyle: String, verified: Bool,
         lineup: String = "original") {
        self.barcode = barcode
        self.name = name
        self.flavor = flavor
        self.sizeML = sizeML
        self.sizeOZ = sizeOZ
        self.caffeineMG = caffeineMG
        self.sugarG = sugarG
        self.calories = calories
        self.sugarFree = sugarFree
        self.accentHex = accentHex
        self.canStyle = canStyle
        self.verified = verified
        self.lineup = lineup
    }

    var accent: Color { Color(hex: accentHex) }

    /// Display name for the lineup family. Unrecognized (or not-yet-healed)
    /// lineups read as "Original" — every can belongs somewhere.
    var lineupLabel: String {
        switch lineup {
        case "sugarfree": "Sugarfree"
        case "zero": "Zero"
        case "editions": "Editions"
        default: "Original"
        }
    }

    var sizeLabel: String {
        sizeOZ.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(sizeOZ))oz" : String(format: "%.1foz", sizeOZ)
    }
}

enum LogSource: String, Codable {
    case scan, manual
}

@Model
final class CanLog {
    var id: UUID
    var timestamp: Date
    var sku: SKU?
    var sourceRaw: String
    var synced: Bool

    init(sku: SKU, timestamp: Date = .now, source: LogSource = .scan) {
        self.id = UUID()
        self.timestamp = timestamp
        self.sku = sku
        self.sourceRaw = source.rawValue
        self.synced = false
    }

    var source: LogSource { LogSource(rawValue: sourceRaw) ?? .manual }
}

@Model
final class UserProfile {
    var displayName: String
    var avatarData: Data?
    var joinDate: Date
    var streakCount: Int
    var lastLogDate: Date?
    var badges: [String]
    var caffeineWarningMG: Int
    var notificationsEnabled: Bool

    init(displayName: String = "You") {
        self.displayName = displayName
        self.joinDate = .now
        self.streakCount = 0
        self.lastLogDate = nil
        self.badges = []
        self.caffeineWarningMG = 400
        self.notificationsEnabled = false
    }
}

@Model
final class Crew {
    var id: UUID
    var name: String
    var inviteCode: String
    var memberNames: [String]

    init(name: String, inviteCode: String, memberNames: [String] = []) {
        self.id = UUID()
        self.name = name
        self.inviteCode = inviteCode
        self.memberNames = memberNames
    }
}
