# CanCount 🥫⚡

**Flighty, but for Red Bulls.** A native iOS app that tracks your Red Bull consumption with completely serious craft: scan a can's barcode, it identifies the exact SKU (flavor + size), logs it, computes weekly totals and caffeine intake, and ranks you against your friends.

## Stack

- **Swift 6 / SwiftUI**, iOS 26 minimum — the whole UI is built on the Liquid Glass design system (`.glassEffect()`, `GlassEffectContainer`, glass tab bar)
- **SwiftData** for local persistence
- **VisionKit `DataScannerViewController`** for barcode scanning (AVFoundation fallback, simulated-scan picker in Simulator)
- **Swift Charts** for stats
- **Open Food Facts** lookup for unknown barcodes
- Leaderboard runs on a mock `LeaderboardService` in v1 — CloudKit slots in behind the protocol

## Building

Requires Xcode 26+.

```sh
brew install xcodegen   # if you don't have it
xcodegen generate
open CanCount.xcodeproj
```

The Xcode project is generated from `project.yml` (XcodeGen), so the `.xcodeproj` itself is not checked in as the source of truth — regenerate after pulling.

## Structure

```
CanCount/
  App/            entry point + ModelContainer
  Models/         SwiftData models (SKU, CanLog, UserProfile, Crew)
  Theme/          palette, type, copy
  Services/       stats engine, log pipeline, badges, scanner resolution, seed loader
  Views/          Home, Stats, Leaderboard, Profile, Scanner + shared components
  Resources/      redbull_skus.json seed database, assets
```

## Design

Design direction and mockups live in `CANCOUNT_BUILD_HANDOFF.md` and `CanCount screen mockups.zip` — GO Club DNA on Liquid Glass, near-black canvas, energy-yellow accent, massive rounded numerals, and a floating can as the hero object.
