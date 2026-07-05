import XCTest

/// UI driver harness: walks every major flow of CanCount in the Simulator and
/// captures screenshots as keep-always attachments for headless verification.
final class CanCountUIDriver: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 8) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    func testFullWalkthrough() throws {
        // ── 1. Home, empty state ──────────────────────────────────────────
        XCTAssertTrue(wait(app.buttons["Scan a can"]), "Home should show the scan button")
        sleep(2) // let count-up + cascade animations settle
        shot("01-home-empty")

        // ── 2. Scanner (simulator mode) ───────────────────────────────────
        app.buttons["Scan a can"].tap()
        XCTAssertTrue(wait(app.staticTexts["SIMULATOR MODE"]), "Scanner should fall back to simulator mode")
        sleep(1)
        shot("02-scanner-simulator-mode")

        // Tap the first seeded can row to fake a scan
        let firstCan = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Red Bull'")).firstMatch
        XCTAssertTrue(wait(firstCan), "Simulator scan list should show seeded cans")
        firstCan.tap()

        let confirm = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'CONFIRM'")).firstMatch
        XCTAssertTrue(wait(confirm), "Result card with CONFIRM should slide up after a scan")
        sleep(1)
        shot("03-scan-result-card")
        confirm.tap()

        // Can Drop celebration (reduced-motion layout under test settings)
        let keepCold = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'keep it cold'")
        ).firstMatch
        XCTAssertTrue(wait(keepCold, 6), "Celebration should play after confirm")
        sleep(1)
        shot("03b-celebration-scan")
        if keepCold.exists { keepCold.tap() }

        XCTAssertTrue(wait(app.buttons["Scan a can"], 10), "Should morph back to Home after celebration")
        sleep(2)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label == '1 cans this week'")).firstMatch.exists,
            "Hero numeral should tick up to 1 after the scan logs"
        )
        shot("04-home-after-first-log")

        // ── 3. Manual log ─────────────────────────────────────────────────
        app.buttons["Log a can manually"].firstMatch.tap()
        XCTAssertTrue(wait(app.staticTexts["THE HONOR SYSTEM"]), "Manual log sheet should appear")
        sleep(1)
        shot("05-manual-log-flavors")

        let flavorTile = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Tropical'")).firstMatch
        if wait(flavorTile, 4) {
            flavorTile.tap()
        } else {
            app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Edition'")).firstMatch.tap()
        }
        let logIt = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'LOG IT'")).firstMatch
        XCTAssertTrue(wait(logIt), "Size stage should offer LOG IT")
        sleep(1)
        shot("06-manual-log-size")
        logIt.tap()

        // Manual path celebration plays at the root after the sheet dismisses
        let keepColdManual = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'keep it cold'")
        ).firstMatch
        if wait(keepColdManual, 6) {
            sleep(1)
            shot("06b-celebration-manual")
            if keepColdManual.exists { keepColdManual.tap() }
        }

        XCTAssertTrue(wait(app.buttons["Scan a can"], 10), "Manual sheet should dismiss back to Home")
        sleep(2)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label == '2 cans this week'")).firstMatch.exists,
            "Hero numeral should now read 2"
        )
        shot("07-home-two-cans")

        // ── 4. Scanner rejection flow (mystery barcode) ───────────────────
        app.buttons["Scan a can"].tap()
        XCTAssertTrue(wait(app.staticTexts["SIMULATOR MODE"]))
        let mystery = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'mystery barcode'")).firstMatch
        XCTAssertTrue(wait(mystery))
        mystery.tap()
        // Either the OFF lookup resolves (rejection card) or network fails (still rejection)
        let rejection = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] \"not a Red Bull\"")).firstMatch
        XCTAssertTrue(wait(rejection, 15), "Non-Red-Bull barcode should show the playful rejection")
        sleep(1)
        shot("08-scan-rejected")
        let closeScanner = app.buttons["Close scanner"]
        if closeScanner.exists { closeScanner.tap() }
        _ = wait(app.buttons["Scan a can"], 8)

        // ── 5. Stats tab ──────────────────────────────────────────────────
        app.buttons["Stats"].firstMatch.tap()
        sleep(3) // bar-growth animation
        shot("09-stats")

        // ── 6. Crew (leaderboard) tab ─────────────────────────────────────
        app.buttons["Crew"].firstMatch.tap()
        sleep(1)
        shot("10-crew-empty")
        let create = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'CREATE CREW'")).firstMatch
        if wait(create, 4) {
            create.tap()
            sleep(3) // entries load + podium springs
            shot("11-crew-podium")
        }

        // ── 7. Profile tab ────────────────────────────────────────────────
        app.buttons["Profile"].firstMatch.tap()
        sleep(2)
        shot("12-profile")

        // ── 8. Back home for the final hero shot ──────────────────────────
        app.buttons["Home"].firstMatch.tap()
        sleep(2)
        shot("13-home-final")
    }
}
