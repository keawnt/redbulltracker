# CANCOUNT — Build Handoff Prompt

> Paste everything below this line into Claude Code as the kickoff prompt.

---

You are building **CanCount**, a native iOS app for tracking Red Bull consumption. Think "Flighty, but for Red Bulls" — obsessively-designed stat tracking for something deliberately unserious, executed with completely serious craft. Scan a can's barcode, the app identifies the exact SKU (flavor + size), logs it, computes weekly totals and caffeine intake, and ranks you against your friends on a leaderboard.

## Platform & Tech Stack

- **Swift 6 / SwiftUI**, iOS 26 minimum deployment target (required — the entire UI is built on the Liquid Glass design system)
- **Liquid Glass everywhere**: `.glassEffect()`, `GlassEffectContainer`, `glassEffectID` morphing transitions, `.buttonStyle(.glass)` / `.glassProminent`, glass tab bar with `.tabBarMinimizeBehavior(.onScrollDown)`
- **Barcode scanning**: VisionKit `DataScannerViewController` (EAN-13 / UPC-A / EAN-8), wrapped in `UIViewControllerRepresentable`. Fallback: AVFoundation metadata output if DataScanner is unavailable on device
- **Local persistence**: SwiftData
- **Sync + social**: CloudKit (private DB for personal logs, shared/public DB for leaderboard groups). If CloudKit friend-group complexity blocks v1 velocity, stub a `LeaderboardService` protocol with a mock backend and note the swap point — do NOT let backend plumbing stall the UI build
- **Charts**: Swift Charts
- **Haptics**: CoreHaptics + `sensoryFeedback` modifiers on every meaningful interaction

## Core Concept: The Can Database

Ship a bundled `redbull_skus.json` seed database keyed by UPC/EAN. Each entry:

```json
{
  "barcode": "611269991000",
  "name": "Red Bull Energy Drink",
  "flavor": "Original",
  "size_ml": 250,
  "size_oz": 8.4,
  "caffeine_mg": 80,
  "sugar_g": 27,
  "calories": 110,
  "sugar_free": false,
  "accent_hex": "#FFC906",
  "can_style": "original"
}
```

Populate it with the full current North American lineup: Original, Sugarfree, Zero, and the Editions (Red/watermelon, Yellow/tropical, Blue/blueberry, Green/dragon fruit, Amber/strawberry apricot, Purple/açaí, Pink/forest fruits, Sea Blue/juneberry, Coconut, Peach, Winter/seasonal) across 8.4oz, 12oz, 16oz, and 20oz where they exist. Scale caffeine/sugar/calories linearly by volume from the 8.4oz base. Use realistic UPCs where you can find them; otherwise generate placeholder barcodes and mark them `"verified": false` — I'll correct real UPCs by scanning my own cans.

**Unknown barcode flow**: if a scan misses the local DB, query Open Food Facts (`https://world.openfoodfacts.org/api/v2/product/{barcode}.json`). If it's a Red Bull product, auto-create the SKU locally and log it. If it's not Red Bull at all, show a playful rejection ("That's not a Red Bull. We both know it.") with a manual-pick fallback grid of all flavors.

**Manual log**: always available — a flavor picker grid (can artwork tiles) + size selector, for when the can's already in the recycling.

## Design Language — GO Club DNA + Liquid Glass

Study direction (Mobbin refs: GO Club iOS). The look:

- **Near-black canvas** (`#0A0A0C`), a single **electric accent** — use Red Bull's palette instead of GO Club's lime: primary accent **energy yellow `#FFC906`**, secondary **racing blue `#001E50`→`#2E5FDF` gradient range**, danger/streak-fire moments in **red `#DB0A40`**
- **Massive display numerals** — the week's can count is the hero of the home screen, rendered huge (SF Pro Rounded, heavy weight, ~120pt) with a spring-animated rolling-odometer count-up on every appearance (`contentTransition(.numericText())`)
- **Rounded cards** (28pt radius) floating on the dark canvas, but built as **Liquid Glass surfaces** — translucent, refractive, catching the accent glow of content behind them
- **The can as a 3D hero object**: center of the home screen is a large rendered Red Bull can (use a high-quality can image asset per flavor with a subtle drop shadow + specular sheen overlay; simulate 3D with a slow idle float animation and parallax tilt via CoreMotion). When a scan logs successfully, the scanned flavor's can drops in from the top with a spring bounce, liquid-glass ripple, and a haptic thump
- **Streak flames, badges, and celebration moments**: confetti burst (Canvas-particle system, yellow/blue/silver bull-and-can shaped particles) on personal records, streak milestones, and overtaking a friend on the leaderboard
- **Playful, confident copy** throughout: "3 today. Your heart rate agrees." / "Zero cans. Suspicious." / "New PR. Please drink water."
- **Animation-first**: every state change springs (`.spring(response: 0.4, dampingFraction: 0.7)`), tab transitions morph glass elements via `glassEffectID`, list items cascade in with staggered delays, pull-to-refresh stretches the hero can

## Screens (4 tabs + scanner)

### 1. Home ("Today")
- Hero: this week's count as the giant numeral, current flavor-of-the-week can floating beside/behind it
- Glass stat pills row: today's count, caffeine mg today, current streak 🔥
- "Recent sips" — last 5 logs as compact glass cards (flavor chip, size, timestamp)
- Floating glass scan button (center-bottom, prominent, morphs into the scanner sheet via `glassEffectID`)

### 2. Stats
- Week selector (horizontal, glass segmented)
- Swift Charts: cans-per-day bar chart (bars in flavor accent colors, animated bar growth on appear), caffeine line overlay toggle
- Flavor breakdown donut + "your flavor personality" card (most-logged flavor gets a title: "Tropical Loyalist", "Sugarfree Purist", "Chaos Agent" for high variety)
- Lifetime totals: total cans, total liters, total caffeine (with absurd equivalents: "= 47 cups of coffee" / "enough caffeine to wake a small horse")
- Weekly recap card generated every Monday — shareable as an image (ImageRenderer), styled like a boarding-pass/Flighty-passport moment

### 3. Leaderboard
- Friend groups ("Crews") — create/join via share link or code
- Podium top-3 with avatars on glass pedestals (gold/silver/bronze glow), springy reorder animations when rankings change
- Full ranked list below: avatar, name, weekly can count, delta arrow vs last week
- Weekly reset Sunday midnight local; "last week's champion" crown persists through the week
- Tapping a friend shows their flavor breakdown mini-profile

### 4. Profile
- Avatar, display name, join date
- Badge wall (glass tiles, locked badges frosted/dimmed): First Scan, 7-Day Streak, 100 Club, Flavor Completionist, Night Owl (log after midnight), etc.
- Settings: caffeine warning threshold (default 400mg/day — show a gentle glass banner when crossed, never preachy), notifications, iCloud sync status

### Scanner (modal, morphs from scan button)
- Full-screen camera with a glass viewfinder frame, animated corner brackets pulsing in accent yellow
- On recognition: freeze frame, can artwork flies out of the barcode position to center, SKU card slides up on glass ("Red Bull Blue Edition · 12oz · 114mg caffeine"), single CONFIRM glass-prominent button + size override if the DB has multiple sizes for that flavor
- Success: haptic + ripple + dismiss-morph back to Home with the odometer ticking up

## Data Model (SwiftData)

- `CanLog` — id, timestamp, sku (relationship), source (.scan/.manual), synced
- `SKU` — barcode, name, flavor, sizeML, caffeineMG, sugarG, calories, sugarFree, accentHex, verified
- `UserProfile` — displayName, avatarData, streakCount, lastLogDate, badges
- `Crew` — id, name, inviteCode, members (leaderboard scope)

Derived stats (weekly counts, streaks, caffeine totals) computed via queries, never stored denormalized in v1.

## Build Order

1. Project scaffold, SwiftData models, seed JSON + loader
2. Home tab with hero numeral + mock data — nail the animation feel FIRST, this sets the bar
3. Scanner + SKU resolution + log pipeline (manual log included)
4. Stats tab + Swift Charts
5. Profile + badges + streak engine
6. Leaderboard UI with mock `LeaderboardService`, then CloudKit behind the protocol
7. Weekly recap share card
8. Polish pass: haptics audit, glass morph transitions between all tabs, empty states with personality

## Non-Negotiables

- 120fps-feel animations; if something stutters on device, simplify the effect rather than shipping jank
- Every empty state, error state, and loading state gets designed copy — no default spinners with no words
- Dark mode only in v1 (the design IS dark). Light mode is out of scope
- No account requirement to use solo — sign-in (Sign in with Apple) only gates the Leaderboard
- Accessibility: Dynamic Type on all body text, VoiceOver labels on stats, Reduce Motion swaps springs for crossfades

Start with step 1 and show me the Home tab running with mock data before building anything else.
