import CoreGraphics

/// A description of the road that levels sit on, independent of screen size.
///
/// Build one with ``RouteBuilder``, or use a ready-made shape:
///
/// ```swift
/// let world = LevelRoute {
///     Start(x: 0.5)
///     Serpentine(levels: 10, amplitude: 0.35)
///     Detour(around: .leading, levels: 3)
///     Straight(levels: 4)
///     Repeat { Serpentine(levels: 6, halfWaves: 2) }
/// }
/// let road = world.resolved(width: 390, spacing: 110)
/// road.level(5_000)?.position
/// ```
///
/// A route without a ``Repeat`` holds exactly the sum of its segments' levels.
/// A route ending in a ``Repeat`` is endless.
public struct LevelRoute: Sendable {
    let start: Start
    let segments: [any RouteSegment]
    let repeatingSegments: [any RouteSegment]?

    public init(@RouteBuilder _ content: () -> [RouteComponent]) {
        self.init(components: content())
    }

    init(components: [RouteComponent]) {
        var start = Start()
        var segments: [any RouteSegment] = []
        var repeating: [any RouteSegment]?

        for (index, component) in components.enumerated() {
            precondition(repeating == nil, "Repeat must be the last item of a LevelRoute")
            switch component.kind {
            case .start(let value):
                precondition(index == 0, "Start must be the first item of a LevelRoute")
                start = value
            case .segment(let segment):
                segments.append(segment)
            case .repeating(let block):
                let body: [any RouteSegment] = block.body.map {
                    guard case .segment(let segment) = $0.kind else {
                        preconditionFailure("Repeat can only contain segments")
                    }
                    return segment
                }
                precondition(body.reduce(0) { $0 + $1.levelCount } > 0,
                             "Repeat needs at least one segment with levels")
                repeating = body
            }
        }

        self.start = start
        self.segments = segments
        self.repeatingSegments = repeating
    }

    /// Turns the description into concrete geometry for a map of the given width.
    ///
    /// - Parameters:
    ///   - width: The map width in points.
    ///   - spacing: How far the road advances along the scroll axis per level, in points.
    ///   - edgeInset: The least room between the road and the map's sides. A route that runs
    ///     closer is scaled in across the map to fit. Defaults to half the spacing.
    public func resolved(width: CGFloat, spacing: CGFloat, edgeInset: CGFloat? = nil) -> ResolvedRoute {
        precondition(width > 0 && spacing > 0, "Width and spacing must be positive")
        return ResolvedRoute(route: self, context: RouteContext(width: width, spacing: spacing, edgeInset: edgeInset))
    }
}

// MARK: - Ready-made routes

extension LevelRoute {
    /// An endless smooth wave.
    public static func serpentine(amplitude: CGFloat = 0.3, levelsPerWave: Int = 6) -> LevelRoute {
        LevelRoute {
            Repeat { Serpentine(levels: levelsPerWave, amplitude: amplitude, halfWaves: 2) }
        }
    }

    /// An endless zigzag with sharp turns.
    public static func zigzag(amplitude: CGFloat = 0.3, levelsPerWave: Int = 6) -> LevelRoute {
        LevelRoute {
            Repeat { Zigzag(levels: levelsPerWave, amplitude: amplitude, halfWaves: 2) }
        }
    }

    /// An endless straight road down the middle.
    public static var straight: LevelRoute {
        LevelRoute {
            Repeat { Straight(levels: 1) }
        }
    }

    /// A smooth curve through `points`, repeated forever.
    ///
    /// - Parameters:
    ///   - points: `x` is a fraction of the width; `y` is a fraction of one repetition's length.
    ///   - levelsPerRepeat: How many levels each repetition holds.
    public static func spline(_ points: [RoutePoint], levelsPerRepeat: Int) -> LevelRoute {
        LevelRoute {
            Start(x: points.first?.x ?? 0.5)
            Repeat { Spline(levels: levelsPerRepeat, through: points) }
        }
    }
}
