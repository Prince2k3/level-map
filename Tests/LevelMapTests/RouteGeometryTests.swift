import CoreGraphics
import Foundation
import Testing
@testable import LevelMap

private let width: CGFloat = 390
private let spacing: CGFloat = 110

private func resolve(@RouteBuilder _ content: () -> [RouteComponent]) -> ResolvedRoute {
    LevelRoute(content).resolved(width: width, spacing: spacing)
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

/// Angle between two unit tangents, in degrees.
private func turn(_ a: CGVector, _ b: CGVector) -> Double {
    let dot = max(-1, min(1, a.dx * b.dx + a.dy * b.dy))
    return acos(Double(dot)) * 180 / .pi
}

/// Largest tangent change between samples `step` apart over `range`.
private func maxTurn(_ road: ResolvedRoute, over range: ClosedRange<CGFloat>, step: CGFloat = 0.5) -> Double {
    var worst = 0.0
    var previous = road.sample(atDistance: range.lowerBound).tangent
    for d in stride(from: range.lowerBound + step, through: range.upperBound, by: step) {
        let tangent = road.sample(atDistance: d).tangent
        worst = max(worst, turn(previous, tangent))
        previous = tangent
    }
    return worst
}

@Suite("Route geometry")
struct RouteGeometryTests {

    @Test func straightLevelsAreOneSpacingApart() throws {
        let road = resolve { Straight(levels: 5) }
        #expect(road.levelCount == 5)
        #expect(abs(try #require(road.length) - 5 * spacing) < 0.01)
        for index in 0..<5 {
            let level = try #require(road.level(index))
            #expect(abs(level.position.x - width / 2) < 0.01)
            #expect(abs(level.position.y - (CGFloat(index) + 0.5) * spacing) < 0.01)
        }
    }

    @Test func outOfRangeLevelsAreNil() {
        let road = resolve { Serpentine(levels: 4) }
        #expect(road.level(-1) == nil)
        #expect(road.level(4) == nil)
        #expect(road.level(3) != nil)
    }

    @Test func sampleIsClampedOnFiniteRoutes() throws {
        let road = resolve { Straight(levels: 2) }
        let length = try #require(road.length)
        #expect(road.sample(atDistance: -50).distance == 0)
        #expect(abs(road.sample(atDistance: length + 500).position.y - 2 * spacing) < 0.01)
    }

    @Test func emptyRouteReturnsStartPoint() {
        let road = resolve { Start(x: 0.25) }
        #expect(road.levelCount == 0)
        #expect(road.level(0) == nil)
        #expect(road.sample(atDistance: 100).position == CGPoint(x: width * 0.25, y: 0))
    }

    @Test(arguments: [
        LevelRoute { Serpentine(levels: 12, amplitude: 0.35) },
        LevelRoute { Zigzag(levels: 9) },
        LevelRoute { Spline(levels: 8, through: [.init(x: 0.2, y: 0.3), .init(x: 0.8, y: 0.6), .init(x: 0.5, y: 1)]) },
        LevelRoute { Detour(around: .trailing, levels: 4) },
    ])
    func arcLengthIsUniform(route: LevelRoute) throws {
        let road = route.resolved(width: width, spacing: spacing)
        let length = try #require(road.length)
        for d in stride(from: CGFloat(0), to: length - 1, by: 7) {
            let step = distance(road.sample(atDistance: d).position, road.sample(atDistance: d + 1).position)
            // A 1pt chord can be slightly shorter than 1pt of arc on tight curves.
            #expect(step > 0.97 && step < 1.03, "chord \(step) at distance \(d)")
        }
    }

    @Test func levelsAreEvenlySpacedAlongEachSegment() throws {
        let road = resolve {
            Serpentine(levels: 7, amplitude: 0.35)
            Detour(around: .leading, levels: 5)
        }
        for range in [0..<7, 7..<12] {
            let distances = try range.map { try #require(road.distance(ofLevel: $0)) }
            let gaps = zip(distances, distances.dropFirst()).map { $1 - $0 }
            let mean = gaps.reduce(0, +) / CGFloat(gaps.count)
            for gap in gaps { #expect(abs(gap - mean) < 0.01) }
        }
    }

    @Test func smoothRouteHasNoKinks() throws {
        let road = resolve {
            Straight(levels: 3)
            Serpentine(levels: 8, amplitude: 0.3)
            Spline(levels: 6, through: [.init(x: 0.3, y: 0.4), .init(x: 0.7, y: 1)])
            Detour(around: .leading, levels: 4)
            Straight(levels: 2, toX: 0.5)
        }
        let worst = maxTurn(road, over: 0...(try #require(road.length)))
        #expect(worst < 3, "largest tangent jump was \(worst)°")
    }

    @Test func zigzagHasSharpCorners() throws {
        let road = resolve { Zigzag(levels: 6, amplitude: 0.3, halfWaves: 2) }
        let worst = maxTurn(road, over: 0...(try #require(road.length)))
        #expect(worst > 10, "expected corners, largest jump was \(worst)°")
    }

    @Test func serpentineStaysOnTheMap() throws {
        let road = resolve { Serpentine(levels: 30, amplitude: 0.45) }
        let length = try #require(road.length)
        for d in stride(from: CGFloat(0), through: length, by: 2) {
            let x = road.sample(atDistance: d).position.x
            #expect(x >= 0 && x <= width)
        }
    }

    @Test func resultsAreDeterministic() {
        let route = LevelRoute {
            Serpentine(levels: 5)
            Repeat { Zigzag(levels: 4); Straight(levels: 1, toX: 0.2) }
        }
        let a = route.resolved(width: width, spacing: spacing)
        let b = route.resolved(width: width, spacing: spacing)
        for index in [0, 3, 7, 150, 9_999] { #expect(a.level(index) == b.level(index)) }
    }
}

@Suite("Repeat")
struct RepeatTests {

    let road = resolve {
        Start(x: 0.3)
        Straight(levels: 2)
        Repeat {
            Serpentine(levels: 5, amplitude: 0.25, halfWaves: 1) // ends off-centre, so a closing curve is added
            Straight(levels: 1)
        }
    }

    @Test func endlessRouteHasNoCount() throws {
        #expect(road.isEndless)
        #expect(road.levelCount == nil)
        #expect(road.length == nil)
        let far = try #require(road.level(1_000_000))
        #expect(far.position.x.isFinite && far.position.y.isFinite)
        #expect(far.position.y > 1_000_000 * spacing * 0.5)
    }

    @Test func cyclesArePeriodic() throws {
        let cycle = try #require(road.cycle)
        let start = road.prefixLength
        for d in stride(from: start, to: start + cycle.length, by: 13) {
            let a = road.sample(atDistance: d)
            for repetition in [1, 2, 37] {
                let b = road.sample(atDistance: d + CGFloat(repetition) * cycle.length)
                #expect(abs(b.position.x - a.position.x) < 0.01)
                #expect(abs(b.position.y - a.position.y - CGFloat(repetition) * cycle.advance) < 0.01)
                #expect(turn(a.tangent, b.tangent) < 0.01)
            }
        }
        // Levels repeat too.
        let first = try #require(road.level(2))
        let next = try #require(road.level(2 + cycle.levelCount))
        #expect(abs(next.position.y - first.position.y - cycle.advance) < 0.01)
    }

    @Test func joinsAreSmooth() throws {
        let cycle = try #require(road.cycle)
        let worst = maxTurn(road, over: 0...(road.prefixLength + 3 * cycle.length))
        #expect(worst < 3, "largest tangent jump was \(worst)°")
    }

    @Test func endlessArcLengthIsUniform() throws {
        let cycle = try #require(road.cycle)
        for d in stride(from: road.prefixLength - 50, to: road.prefixLength + 2 * cycle.length, by: 5) {
            let step = distance(road.sample(atDistance: d).position, road.sample(atDistance: d + 1).position)
            #expect(step > 0.97 && step < 1.03, "chord \(step) at distance \(d)")
        }
    }

    @Test func presetsResolve() {
        for route in [LevelRoute.serpentine(), .zigzag(), .straight,
                      .spline([.init(x: 0.5, y: 0), .init(x: 0.2, y: 0.5), .init(x: 0.5, y: 1)], levelsPerRepeat: 4)] {
            let road = route.resolved(width: width, spacing: spacing)
            #expect(road.isEndless)
            #expect(road.level(500) != nil)
        }
    }

    @Test func lookupIsFast() {
        let road = LevelRoute.serpentine().resolved(width: width, spacing: spacing)
        let lookups = 100_000
        let clock = ContinuousClock()
        var sink: CGFloat = 0
        let elapsed = clock.measure {
            for index in 0..<lookups { sink += road.level(index * 7)?.position.x ?? 0 }
        }
        #expect(sink > 0)
        let perLookup = elapsed / lookups
        // Release builds land well under 10µs; debug builds get slack.
        #expect(perLookup < .microseconds(50), "\(perLookup) per lookup")
    }
}
