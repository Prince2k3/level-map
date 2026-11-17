import CoreGraphics
import LevelMap
import SwiftUI

/// Everything the editor lets you change: the route and how the map looks.
///
/// It is plain data, so you can save a design as JSON and open it again later.
public struct LevelMapDesign: Codable, Sendable, Equatable {
    /// The name used in the exported code, for example `LevelRoute.myWorld`.
    public var name: String
    public var route: RouteJSON
    /// How far apart levels are along the scroll axis, in points.
    public var spacing: CGFloat
    /// Puts level 1 at the bottom, so the player climbs the map.
    public var startsAtEnd: Bool
    /// Levels per chapter, or `nil` for one look across the whole map.
    public var chapterLength: Int?
    /// Names of the themes to use, taken from the themes passed to the editor. Without
    /// chapters only the first is used; with chapters they take turns.
    public var themes: [String]

    public init(name: String = "myWorld", route: RouteJSON = LevelMapDesign.starterRoute,
                spacing: CGFloat = 110, startsAtEnd: Bool = true,
                chapterLength: Int? = nil, themes: [String] = []) {
        self.name = name
        self.route = route
        self.spacing = spacing
        self.startsAtEnd = startsAtEnd
        self.chapterLength = chapterLength
        self.themes = themes
    }

    /// A short route to start from: a straight run, a wave, then a wave that repeats.
    public static let starterRoute = RouteJSON(
        start: 0.5,
        segments: [.straight(levels: 2, toX: nil), .serpentine(levels: 6, amplitude: 0.3, halfWaves: 2)],
        repeating: [.serpentine(levels: 6, amplitude: 0.3, halfWaves: 2)])

    /// The route, or the error that stops it being built.
    public func buildRoute() throws -> LevelRoute { try route.route() }

    /// How many levels the editor shows: the finite part and three passes of the repeating part.
    var previewLevelCount: Int {
        let prefix = route.segments.reduce(0) { $0 + $1.levelCount }
        let cycle = (route.repeating ?? []).reduce(0) { $0 + $1.levelCount }
        return max(prefix + 3 * cycle, 1)
    }

    /// Whether the map changes look every few levels. Needs a chapter length and two themes.
    var usesChapters: Bool { chapterLength != nil && themes.count > 1 }
}

// MARK: - Segments

/// Which list a segment is in.
enum RouteSection: Hashable, Sendable {
    /// Played once, in order.
    case main
    /// Repeated forever after the main list.
    case repeating
}

/// A segment's place in the design.
struct SegmentRef: Hashable, Sendable {
    var section: RouteSection
    var index: Int
}

/// The segment types a designer can add.
enum SegmentKind: String, CaseIterable, Identifiable, Sendable {
    case straight = "Straight", serpentine = "Serpentine", zigzag = "Zigzag", spline = "Spline",
         detour = "Detour", polyline = "Polyline"
    var id: Self { self }

    /// The segment added from the editor's menu.
    var template: RouteJSON.Segment {
        switch self {
        case .straight: .straight(levels: 3, toX: nil)
        case .serpentine: .serpentine(levels: 6, amplitude: 0.3, halfWaves: 2)
        case .zigzag: .zigzag(levels: 6, amplitude: 0.3, halfWaves: 2)
        case .spline: .spline(levels: 6, points: [RoutePoint(x: 0.25, y: 0.33), RoutePoint(x: 0.75, y: 0.66),
                                                  RoutePoint(x: 0.5, y: 1)])
        case .detour: .detour(side: .leading, levels: 3, inset: 0.12)
        case .polyline: .polyline(levels: 4, points: [RoutePoint(x: 0.2, y: 0.4), RoutePoint(x: 0.8, y: 0.8),
                                                      RoutePoint(x: 0.5, y: 1.2)], smooth: true)
        }
    }

    var symbol: String {
        switch self {
        case .straight: "arrow.up"
        case .serpentine: "point.topleft.down.to.point.bottomright.curvepath"
        case .zigzag: "chart.xyaxis.line"
        case .spline: "scribble"
        case .detour: "arrow.uturn.left"
        case .polyline: "point.3.connected.trianglepath.dotted"
        }
    }
}

extension RouteJSON.Segment {
    var kind: SegmentKind {
        switch self {
        case .straight: .straight
        case .serpentine: .serpentine
        case .zigzag: .zigzag
        case .spline: .spline
        case .detour: .detour
        case .polyline: .polyline
        }
    }

    var levelCount: Int {
        get {
            switch self {
            case let .straight(levels, _), let .serpentine(levels, _, _), let .zigzag(levels, _, _),
                 let .spline(levels, _), let .detour(_, levels, _), let .polyline(levels, _, _):
                levels
            }
        }
        set {
            let levels = max(newValue, 1)
            switch self {
            case let .straight(_, toX): self = .straight(levels: levels, toX: toX)
            case let .serpentine(_, a, h): self = .serpentine(levels: levels, amplitude: a, halfWaves: h)
            case let .zigzag(_, a, h): self = .zigzag(levels: levels, amplitude: a, halfWaves: h)
            case let .spline(_, points): self = .spline(levels: levels, points: points)
            case let .detour(side, _, inset): self = .detour(side: side, levels: levels, inset: inset)
            case let .polyline(_, points, smooth): self = .polyline(levels: levels, points: points, smooth: smooth)
            }
        }
    }

    /// The control points of a spline or polyline; empty for other segments.
    var points: [RoutePoint] {
        get {
            switch self {
            case let .spline(_, points), let .polyline(_, points, _): points
            default: []
            }
        }
        set {
            switch self {
            case let .spline(levels, _): self = .spline(levels: levels, points: newValue)
            case let .polyline(levels, _, smooth): self = .polyline(levels: levels, points: newValue, smooth: smooth)
            default: break
            }
        }
    }

    /// Adds a point after the last but one, halfway between it and the end.
    mutating func addPoint() {
        var points = self.points
        guard let last = points.last else { return }
        let before = points.count > 1 ? points[points.count - 2] : RoutePoint(x: 0.5, y: 0)
        points.insert(RoutePoint(x: rounded((before.x + last.x) / 2), y: rounded((before.y + last.y) / 2)),
                      at: points.count - 1)
        self.points = points
    }

    /// Removes the point before the end, keeping at least one.
    mutating func removePoint() {
        var points = self.points
        guard points.count > 1 else { return }
        points.remove(at: points.count - 2)
        self.points = points
    }
}

extension RouteJSON {
    func segments(in section: RouteSection) -> [Segment] {
        section == .main ? segments : (repeating ?? [])
    }

    subscript(ref: SegmentRef) -> Segment? {
        get {
            let list = segments(in: ref.section)
            return list.indices.contains(ref.index) ? list[ref.index] : nil
        }
        set {
            guard let newValue else { return }
            switch ref.section {
            case .main where segments.indices.contains(ref.index):
                segments[ref.index] = newValue
            case .repeating where repeating?.indices.contains(ref.index) == true:
                repeating?[ref.index] = newValue
            default: break
            }
        }
    }

    /// Appends a segment to a section and returns where it went.
    @discardableResult
    mutating func append(_ segment: Segment, to section: RouteSection) -> SegmentRef {
        switch section {
        case .main:
            segments.append(segment)
            return SegmentRef(section: .main, index: segments.count - 1)
        case .repeating:
            repeating = (repeating ?? []) + [segment]
            return SegmentRef(section: .repeating, index: repeating!.count - 1)
        }
    }

    mutating func remove(_ ref: SegmentRef) {
        switch ref.section {
        case .main:
            if segments.indices.contains(ref.index) { segments.remove(at: ref.index) }
        case .repeating:
            if repeating?.indices.contains(ref.index) == true { repeating?.remove(at: ref.index) }
            // A route with an empty repeat would not build; no repeat means the route ends.
            if repeating?.isEmpty == true { repeating = nil }
        }
    }

    /// Moves a segment one place up or down within its section. Returns where it ended up.
    mutating func move(_ ref: SegmentRef, by offset: Int) -> SegmentRef {
        var list = segments(in: ref.section)
        let target = ref.index + offset
        guard list.indices.contains(ref.index), list.indices.contains(target) else { return ref }
        list.swapAt(ref.index, target)
        if ref.section == .main { segments = list } else { repeating = list }
        return SegmentRef(section: ref.section, index: target)
    }

    /// Moves a segment between the main list and the repeating list.
    mutating func switchSection(_ ref: SegmentRef) -> SegmentRef? {
        guard let segment = self[ref] else { return nil }
        remove(ref)
        return append(segment, to: ref.section == .main ? .repeating : .main)
    }
}

/// Rounds to hundredths, so dragged values export as tidy numbers.
func rounded(_ value: CGFloat) -> CGFloat { (value * 100).rounded() / 100 }
