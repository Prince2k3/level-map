import XCTest

/// UI tests for the map, and for the avatar walking towards the next level with
/// `.levelMapProgress(toNext:)`.
///
/// The demo opens on level 5,000 of an endless map. With `-uitest` it shows where the avatar
/// stands on the road (`avatarProbe`). The library hides the avatar itself from accessibility.
/// A leg is 120 m long, and the walk covers `-walkStep` metres every half second.
@MainActor
final class LiveWalkUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    // MARK: - Standing on a level

    func testOpensOnCurrentLevelWithAvatarOnItsNode() throws {
        launch()
        XCTAssertEqual(label("levelLabel"), "Level 5,000")
        XCTAssertFalse(app.staticTexts["metresLabel"].exists, "No walk in progress, so no distance")

        XCTAssertEqual(node("4,999").value as? String, "Completed")
        XCTAssertEqual(node("5,000").value as? String, "Current level")
        XCTAssertEqual(node("5,001").value as? String, "Locked")

        let avatar = try XCTUnwrap(waitForAvatar())
        XCTAssertLessThan(avatar.distance(to: center("5,000")), 3, "The avatar stands on the current node")
    }

    // MARK: - Walking

    func testWalkingMovesAvatarSmoothlyTowardsNextLevel() throws {
        launch()
        try assertWalksTowardsNextLevel(from: "5,000", to: "5,001")
    }

    func testWalkingOnHorizontalMap() throws {
        launch("-horizontal")
        try assertWalksTowardsNextLevel(from: "5,000", to: "5,001")
    }

    func testWalkingOnTopDownMap() throws {
        launch()
        // Tap the switch itself, at the trailing end of the toggle's row.
        app.switches["Bottom-up"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(app.switches["Bottom-up"].value as? String, "0")
        XCTAssertTrue(node("5,000").waitForExistence(timeout: 5))
        try assertWalksTowardsNextLevel(from: "5,000", to: "5,001")
    }

    func testWalkingOnEveryRoute() throws {
        for route in ["Wave", "Zigzag", "Spline", "Exported"] {
            launch("-sample", route)
            try assertWalksTowardsNextLevel(from: "5,000", to: "5,001", ticks: 4)
            app.terminate()
        }
    }

    func testStopFreezesAvatarAndDistance() throws {
        launch()
        app.buttons["Walk"].tap()
        waitUntil { (self.metres() ?? 120) <= 80 }
        app.buttons["Stop"].tap()
        pause(1) // Let the last half-second step finish animating.

        let metres = metres()
        let avatar = try XCTUnwrap(avatarPosition())
        pause(2)
        XCTAssertEqual(self.metres(), metres)
        XCTAssertEqual(try XCTUnwrap(avatarPosition()).distance(to: avatar), 0, accuracy: 1)
        XCTAssertEqual(label("levelLabel"), "Level 5,000")
    }

    // MARK: - Arriving

    func testArrivingMakesNextLevelCurrentWithoutAJump() throws {
        launch()
        app.buttons["Walk"].tap()
        waitUntil(timeout: 10) { self.label("levelLabel") == "Level 5,001" }

        // Arrival scrolls the map to the new level while the walk carries on. The avatar must
        // stay on the new leg, not run back over the one it just walked. `avatarGap` is measured
        // in the same frame as the node, so it holds while the map scrolls.
        let leg = center("5,000").distance(to: center("5,001"))
        let firstMetres = try XCTUnwrap(metres())
        XCTAssertGreaterThanOrEqual(firstMetres, 90, "The next leg starts from its full length")
        // The probe of the new current node reports once its geometry first changes.
        waitUntil(timeout: 3) { self.avatarGap(from: 5_001) != nil }
        // Sampled as fast as queries allow. The avatar must never be further from 5,001 than the
        // distance walked since arriving; running back would put it most of a leg away.
        for sample in 0..<5 {
            let gap = try XCTUnwrap(avatarGap(from: 5_001))
            let walked = leg * CGFloat(120 - (metres() ?? 120)) / 120 // Read after the gap, so ≥ it.
            XCTAssertLessThanOrEqual(gap, walked + 12, "No running back on arrival (sample \(sample))")
            pause(0.1)
        }

        XCTAssertEqual(node("5,000").value as? String, "Completed")
        XCTAssertEqual(node("5,001").value as? String, "Current level")

        // And the walk carries on, past 5,001 towards 5,002. (Queries are slow enough that a
        // tick-by-tick check here could see the next arrival.)
        app.buttons["Stop"].tap()
        pause(1)
        let left = try XCTUnwrap(metres())
        XCTAssertLessThan(left, firstMetres, "The walk carried on after arriving")
        let avatar = try XCTUnwrap(avatarPosition())
        let towards5002 = center("5,001").distance(to: center("5,002")) * CGFloat(120 - left) / 120
        XCTAssertEqual(avatar.distance(to: center("5,001")), towards5002, accuracy: 12,
                       "On the new leg, as far along as the distance walked")
        XCTAssertLessThan(avatar.distance(to: center("5,002")), center("5,001").distance(to: center("5,002")),
                          "Heading for 5,002")
    }

    func testWalkingSeveralLevels() throws {
        launch("-walkStep", "40") // Three steps per leg.
        app.buttons["Walk"].tap()
        waitUntil(timeout: 12) { self.label("levelLabel") == "Level 5,003" }
        app.buttons["Stop"].tap()
        pause(1.5)

        // A level takes only 1.5 s at this pace, so the walk can reach 5,004 before the app acts
        // on Stop. Check whichever level it stopped on.
        let stopped = try XCTUnwrap(label("levelLabel"))
        XCTAssertTrue(["Level 5,003", "Level 5,004"].contains(stopped), "Stopped on \(stopped)")
        let current = stopped == "Level 5,004" ? 5_004 : 5_003
        func name(_ level: Int) -> String { level.formatted() }
        XCTAssertEqual(node(name(current - 1)).value as? String, "Completed")
        XCTAssertEqual(node(name(current)).value as? String, "Current level")
        // Steps can land between the Stop tap and the app acting on it, so the avatar may be
        // anywhere on the leg after the current level. It must not be behind it.
        let avatar = try XCTUnwrap(avatarPosition())
        let here = center(name(current)), next = center(name(current + 1))
        let leg = here.distance(to: next)
        XCTAssertLessThan(avatar.distance(to: here), leg + 5, "Not past the next level")
        XCTAssertLessThan(avatar.distance(to: here) + avatar.distance(to: next), leg * 1.3,
                          "On the leg after the current level, not left behind")
    }

    // MARK: - Changing level mid-walk

    func testCompletingLevelMidWalkMovesAvatarToThatLevel() throws {
        launch()
        app.buttons["Walk"].tap()
        waitUntil { (self.metres() ?? 120) <= 60 }
        app.buttons["Complete level"].tap()
        app.buttons["Stop"].tap()
        pause(1.5)

        XCTAssertEqual(label("levelLabel"), "Level 5,001")
        // The walk takes a step or two between the taps.
        let metres = try XCTUnwrap(metres())
        XCTAssertGreaterThanOrEqual(metres, 95, "Progress starts again from the new level")
        let avatar = try XCTUnwrap(avatarPosition())
        let leg = center("5,001").distance(to: center("5,002"))
        XCTAssertLessThan(avatar.distance(to: center("5,001")), leg * CGFloat(120 - metres) / 120 + 10,
                          "The avatar is at the new level, plus the steps walked since")
    }

    func testGoingBackToLevelOneMidWalk() throws {
        launch()
        app.buttons["Walk"].tap()
        waitUntil { (self.metres() ?? 120) <= 80 }
        app.buttons["Go to 1"].tap()
        app.buttons["Stop"].tap()
        XCTAssertTrue(node("1").waitForExistence(timeout: 5))
        pause(1.5)

        XCTAssertEqual(label("levelLabel"), "Level 1")
        XCTAssertEqual(node("1").value as? String, "Current level")
        let avatar = try XCTUnwrap(avatarPosition())
        XCTAssertTrue(app.frame.contains(avatar), "The avatar jumped to level 1, on screen")
        XCTAssertLessThan(avatar.distance(to: center("1")), 12)
    }

    func testScrollingAwayWhileWalking() throws {
        launch("-walkStep", "4") // A 15-second leg, so the drags finish well before arriving.
        app.buttons["Walk"].tap()
        // Drag the map itself; the first scroll view is the route picker.
        for _ in 0..<3 {
            // Towards level 1: the endless end above is only loaded a few chunks ahead.
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.9))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.35)))
        }
        // The map is clipped below the controls; a node scrolled off the top sits behind them.
        let mapArea = visibleMapArea()
        let walkOnScreen = [node("5,000"), node("5,001")].contains { $0.exists && mapArea.intersects($0.frame) }
        XCTAssertFalse(walkOnScreen, "Scrolled away from the walk: map \(mapArea), 5,000 at \(node("5,000").frame), 5,001 at \(node("5,001").frame)")

        // Reaching the next level brings the map back to it.
        waitUntil(timeout: 30) { self.label("levelLabel") == "Level 5,001" }
        app.buttons["Stop"].tap()
        pause(1.5)
        XCTAssertTrue(visibleMapArea().contains(center("5,001")), "Back on screen")
        let avatar = try XCTUnwrap(avatarPosition())
        XCTAssertLessThan(avatar.distance(to: center("5,001")), 15)
    }

    // MARK: - The completed road

    func testCompletedRoadFollowsAvatar() throws {
        launch("-walkStep", "5")
        app.buttons["Walk"].tap()
        let first = try stopAt(metres: 80)
        app.buttons["Walk"].tap()
        let second = try stopAt(metres: 45)

        // Each stop is sampled in the other's screenshot: under the avatar itself the colours meet.
        // The map glides with the walk, so each point is moved into the other screenshot's scroll.
        XCTAssertEqual(try road(at: second.avatar - second.reference + first.reference, in: first.screenshot),
                       .notCompleted, "Ahead of the avatar at the first stop")
        XCTAssertEqual(try road(at: first.avatar - first.reference + second.reference, in: second.screenshot), .completed,
                       "The road completed so far stays completed")
    }
}

// MARK: - Helpers

extension LiveWalkUITests {
    private func launch(_ arguments: String...) {
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-look", "Meadow"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["levelLabel"].waitForExistence(timeout: 10))
        XCTAssertTrue(node("5,000").waitForExistence(timeout: 10))
    }

    /// Walks a few half-second steps and checks each one moves the avatar a little further from
    /// `from` and closer to `to`, with the map holding still and the avatar never reaching `to`.
    private func assertWalksTowardsNextLevel(from: String, to: String, alreadyWalking: Bool = false,
                                             ticks: Int = 4, file: StaticString = #filePath, line: UInt = #line) throws {
        if !alreadyWalking { app.buttons["Walk"].tap() }
        // The map glides along with the walk, so positions are measured from `from`, in map space.
        let leg = center(from).distance(to: center(to))
        let end = center(to) - center(from)
        var previous = try XCTUnwrap(waitForAvatar(), "No avatar", file: file, line: line) - center(from)
        var previousMetres = metres() ?? 120
        var previousFrom = center(from)

        for tick in 0..<ticks {
            pause(0.5)
            let from0 = center(from)
            let avatar = try XCTUnwrap(avatarPosition(), file: file, line: line) - from0
            let metres = metres() ?? 120
            XCTAssertLessThanOrEqual(metres, previousMetres, "Distance left never goes up", file: file, line: line)
            XCTAssertLessThan(from0.distance(to: previousFrom), leg / 2,
                              "The map glides rather than jumps (tick \(tick))", file: file, line: line)
            // Slow queries can let more than one walk step land in a tick, so allow for the metres
            // actually walked since the last sample, plus a quarter leg.
            let walked = leg * CGFloat(previousMetres - metres) / 120
            XCTAssertLessThan(avatar.distance(to: previous), walked + leg / 4,
                              "Each step is small; no jumps (tick \(tick))", file: file, line: line)
            XCTAssertLessThanOrEqual(avatar.distance(to: end), previous.distance(to: end) + 1.5,
                                     "Gets closer to \(to) (tick \(tick))", file: file, line: line)
            XCTAssertGreaterThanOrEqual(avatar.distance(to: .zero), previous.distance(to: .zero) - 1.5,
                                        "Gets further from \(from) (tick \(tick))", file: file, line: line)
            previous = avatar
            previousMetres = metres
            previousFrom = from0
        }
        XCTAssertGreaterThan(previous.distance(to: .zero), 10, "The avatar left \(from)", file: file, line: line)
        XCTAssertGreaterThan(previous.distance(to: end), 5, "…but hasn't reached \(to)", file: file, line: line)
        app.buttons["Stop"].tap()
    }

    private struct Stop {
        let avatar: CGPoint
        /// Where level 5,000 was, to line up screenshots taken at different scroll positions.
        let reference: CGPoint
        let screenshot: XCUIScreenshot
    }

    private func stopAt(metres target: Int) throws -> Stop {
        waitUntil { (self.metres() ?? 120) <= target }
        app.buttons["Stop"].tap()
        pause(1) // The last step finishes animating.
        return Stop(avatar: try XCTUnwrap(avatarPosition()), reference: center("5,000"), screenshot: app.screenshot())
    }

    private enum RoadColor: Equatable { case completed, notCompleted, other(String) }

    /// The meadow road is cream (blue ≈ 168) and its completed part orange (blue ≈ 82).
    private func road(at point: CGPoint, in screenshot: XCUIScreenshot) throws -> RoadColor {
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let frame = app.frame
        let scale = CGFloat(image.width) / frame.width
        let x = Int(((point.x - frame.minX) * scale).rounded()), y = Int(((point.y - frame.minY) * scale).rounded())

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        let (r, g, b) = (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Sampled (\(Int(point.x)), \(Int(point.y))) → rgb(\(r), \(g), \(b))"
        attachment.lifetime = .keepAlways
        add(attachment)

        if r > 220, g > 160, g < 215, b < 125 { return .completed }
        if r > 215, g > 205, b > 140, b < 200 { return .notCompleted }
        return .other("rgb(\(r), \(g), \(b))")
    }

    private func node(_ number: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value != nil", number)).firstMatch
    }

    /// The part of the screen the map shows: everything below the controls.
    private func visibleMapArea() -> CGRect {
        let top = app.buttons["Go to 1"].frame.maxY
        return CGRect(x: app.frame.minX, y: top, width: app.frame.width, height: app.frame.maxY - top)
    }

    private func center(_ number: String) -> CGPoint {
        let frame = node(number).frame
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func label(_ identifier: String) -> String? {
        let element = app.staticTexts[identifier]
        return element.exists ? element.label : nil
    }

    private func metres() -> Int? {
        label("metresLabel").flatMap { Int($0.split(separator: " ").first ?? "") }
    }

    private func avatarPosition() -> CGPoint? {
        guard let text = label("avatarProbe") else { return nil }
        let parts = text.split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }

    /// How far the avatar is from the node of `level`, if that is the current level.
    private func avatarGap(from level: Int) -> CGFloat? {
        gap(named: "avatarGap", from: level)
    }

    private func gap(named identifier: String, from level: Int) -> CGFloat? {
        let parts = (label(identifier) ?? "").split(separator: ":")
        guard parts.count == 2, Int(parts[0]) == level, let gap = Double(parts[1]) else { return nil }
        return CGFloat(gap)
    }

    private func waitForAvatar() -> CGPoint? {
        waitUntil { self.avatarPosition() != nil }
        return avatarPosition()
    }

    private func waitUntil(timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("Timed out after \(timeout)s", file: file, line: line) }
            pause(0.1)
        }
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
}
