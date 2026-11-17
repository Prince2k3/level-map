import SwiftUI

/// The look of a map: its ground, its road and the scenery scattered beside the road.
///
/// ```swift
/// LevelMap(levels, route: .serpentine()) { ... }
///     .levelMapTheme(.desert)
/// ```
public struct LevelMapTheme: Sendable {
    public var background: MapBackground
    public var road: RoadStyle
    public var decorations: [Decoration]
    /// About how many decorations to scatter per 100×100 points of map.
    public var decorationDensity: Double
    /// The gap kept free of decorations on each side of the road, in points.
    /// Make it at least as large as your level nodes so decorations never touch them.
    public var roadClearance: CGFloat
    /// Changes where decorations land. The same seed always gives the same scenery.
    public var seed: Int

    public init(
        background: MapBackground,
        road: RoadStyle = RoadStyle(),
        decorations: [Decoration] = [],
        decorationDensity: Double = 0.6,
        roadClearance: CGFloat = 30,
        seed: Int = 0
    ) {
        self.background = background
        self.road = road
        self.decorations = decorations
        self.decorationDensity = max(decorationDensity, 0)
        self.roadClearance = max(roadClearance, 0)
        self.seed = seed
    }

    /// No ground (whatever is behind the map shows through), the default road and no scenery.
    public static let plain = LevelMapTheme(background: .color(.clear))
}

/// The ground under the road.
public enum MapBackground: Sendable {
    /// One flat colour.
    case color(Color)
    /// A gradient across the map (left to right on vertical maps, top to bottom on horizontal ones),
    /// so it tiles seamlessly along the scroll axis.
    case gradient([Color])
}

/// How the road is drawn.
///
/// The road up to the current level uses ``completedColor``; the rest uses ``color``
/// (or ``shader``, when set). The completed part grows with an animation when a level unlocks.
public struct RoadStyle: Sendable {
    public var width: CGFloat
    public var color: Color
    public var completedColor: Color
    /// An edge drawn on both sides of the road, or `nil` for none.
    public var outline: Color?
    public var outlineWidth: CGFloat
    /// A line painted down the middle of the road, or `nil` for none.
    public var centerLine: CenterLine?
    /// Fills the remaining road instead of ``color``, for example a Metal shader made with `ShaderLibrary`.
    public var shader: Shader?

    /// A line painted down the middle of the road.
    public struct CenterLine: Sendable {
        public var color: Color
        public var width: CGFloat
        /// Dash and gap lengths, in points. Empty for a solid line.
        public var dash: [CGFloat]

        public init(color: Color, width: CGFloat = 3, dash: [CGFloat] = [10, 12]) {
            self.color = color
            self.width = width
            self.dash = dash
        }
    }

    public init(
        width: CGFloat = 26,
        color: Color = Color(red: 0.93, green: 0.85, blue: 0.62),
        completedColor: Color = Color(red: 0.98, green: 0.72, blue: 0.30),
        outline: Color? = nil,
        outlineWidth: CGFloat = 3,
        centerLine: CenterLine? = nil,
        shader: Shader? = nil
    ) {
        self.width = max(width, 0)
        self.color = color
        self.completedColor = completedColor
        self.outline = outline
        self.outlineWidth = max(outlineWidth, 0)
        self.centerLine = centerLine
        self.shader = shader
    }
}

/// One kind of scenery the map scatters beside the road.
public struct Decoration: Sendable {
    public enum Content: Sendable {
        /// An SF Symbol, tinted with the decoration's colour.
        case symbol(String)
        /// Any image. Template images are tinted with the decoration's colour.
        case image(Image)
    }

    public var content: Content
    public var color: Color
    /// The range of sizes (the longer side, in points) a placed decoration picks from.
    public var size: ClosedRange<CGFloat>
    /// How often this decoration is picked relative to the theme's others.
    public var weight: Double

    public init(_ content: Content, color: Color = .primary, size: ClosedRange<CGFloat> = 24...40, weight: Double = 1) {
        self.content = content
        self.color = color
        self.size = max(size.lowerBound, 1)...max(size.upperBound, 1)
        self.weight = max(weight, 0)
    }

    /// An SF Symbol decoration.
    public static func symbol(_ name: String, color: Color, size: ClosedRange<CGFloat> = 24...40, weight: Double = 1) -> Decoration {
        Decoration(.symbol(name), color: color, size: size, weight: weight)
    }

    /// An image decoration.
    public static func image(_ image: Image, color: Color = .primary, size: ClosedRange<CGFloat> = 24...40, weight: Double = 1) -> Decoration {
        Decoration(.image(image), color: color, size: size, weight: weight)
    }
}

/// Splits a map into chapters of levels, each with its own theme. Set with
/// ``SwiftUICore/View/levelMapChapters(every:_:)``.
struct LevelMapChapters: Sendable {
    /// Levels per chapter.
    let length: Int
    let theme: @Sendable (_ chapter: Int) -> LevelMapTheme

    init(every length: Int, theme: @escaping @Sendable (_ chapter: Int) -> LevelMapTheme) {
        self.length = max(length, 1)
        self.theme = theme
    }
}

/// How the ground changes from one chapter's theme to the next.
public enum ChapterTransition: Sendable, Hashable {
    /// A hard edge.
    case cut
    /// A blend over `length` points along the scroll axis, centred on the chapter boundary.
    case fade(length: CGFloat)

    var length: CGFloat {
        switch self {
        case .cut: 0
        case let .fade(length): max(length, 0)
        }
    }
}
