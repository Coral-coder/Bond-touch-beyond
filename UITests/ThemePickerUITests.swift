import XCTest

/// Taps every theme in Settings → Theme on a simulator, the way a person would, and checks
/// each one actually becomes the selected theme. Screenshots before and after each tap are
/// attached to the result.
final class ThemePickerUITests: XCTestCase {
    private let titles = ["Aero Glass", "Midnight Neon", "Soft Pastel", "Minimal Mono", "Liquid Aurora",
                          "Paper & Ink", "Chalkboard", "Bubble", "Raindrop", "Citrus", "Matrix"]

    override func setUp() { continueAfterFailure = true }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testEveryThemeCanBePicked() {
        let app = XCUIApplication()
        // No -appStyle here: a launch argument would pin the theme and every pick would be ignored.
        app.launchArguments = ["-demo", "-demoTab", "settings", "-themePickerOpen", "1"]
        app.launch()
        sleep(4)
        // Start from the most likely offenders, then the rest.
        // Matrix is the last tile: scrolling it into view (with the picker open) crashed build 72.
        let order = ["Matrix", "Aero Glass", "Matrix", "Raindrop", "Bubble", "Raindrop", "Citrus", "Aero Glass", "Raindrop", "Midnight Neon", "Bubble"]
        for title in order {
            let tile = app.buttons["\(title) theme"]
            var swipes = 0
            // Hittable isn't enough: the floating tab bar sits over the bottom of the screen and
            // takes taps there, so the tile has to be clear of it (and of the top bar).
            func clear() -> Bool {
                guard tile.exists && tile.isHittable else { return false }
                let h = app.frame.height
                return tile.frame.minY > 100 && tile.frame.maxY < h - 120
            }
            while !clear() && swipes < 16 {
                // Scroll towards the tile, whichever way it is.
                if tile.exists && tile.frame.minY < 100 { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
                swipes += 1
            }
            shot(app, "\(title)-before-\(order.firstIndex(of: title) ?? 0)")
            guard tile.exists else { XCTFail("\(title): tile not found"); continue }
            guard tile.isHittable else {
                XCTFail("\(title): tile exists but is NOT hittable (something is covering it) frame=\(tile.frame)")
                print(app.debugDescription)
                continue
            }
            let start = Date()
            tile.tap()
            var picked = false
            while Date().timeIntervalSince(start) < 10 {
                let b = app.buttons["\(title) theme"]
                if b.exists && b.isSelected { picked = true; break }
                usleep(100_000)
            }
            print(String(format: "THEME TIMING %@: %.2fs", title, Date().timeIntervalSince(start)))
            shot(app, "\(title)-after")
            let after = app.buttons["\(title) theme"]
            if !picked { print("THEME FAIL \(title): selected=\(after.exists ? String(after.isSelected) : "missing")"); print(app.debugDescription) }
            XCTAssertTrue(picked, "\(title): tapped, but it did not become the selected theme")
            print("THEME \(title): \(picked ? "OK" : "FAILED")")
        }
    }
}
