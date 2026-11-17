import CoreGraphics

/// Where the road begins across the map. Only valid as the first item of a route.
public struct Start: Sendable {
    /// A fraction of the map width.
    public var x: CGFloat

    public init(x: CGFloat = 0.5) {
        self.x = x
    }
}

/// Repeats its segments forever, making the route endless. Must be the last item of a route.
///
/// If the repeated part does not end at the same horizontal position it started at,
/// a short bend is added to its last segment so that every repetition joins up smoothly.
public struct Repeat: Sendable {
    let body: [RouteComponent]

    public init(@RouteBuilder _ body: () -> [RouteComponent]) {
        self.body = body()
    }

    init(body: [RouteComponent]) {
        self.body = body
    }
}

/// One item in a ``RouteBuilder`` block.
public struct RouteComponent: Sendable {
    enum Kind: Sendable {
        case start(Start)
        case segment(any RouteSegment)
        case repeating(Repeat)
    }

    let kind: Kind
}

/// Builds a ``LevelRoute`` from ``Start``, segments and an optional trailing ``Repeat``.
@resultBuilder
public enum RouteBuilder {
    public static func buildExpression(_ segment: some RouteSegment) -> [RouteComponent] {
        [RouteComponent(kind: .segment(segment))]
    }

    public static func buildExpression(_ start: Start) -> [RouteComponent] {
        [RouteComponent(kind: .start(start))]
    }

    public static func buildExpression(_ repeating: Repeat) -> [RouteComponent] {
        [RouteComponent(kind: .repeating(repeating))]
    }

    public static func buildExpression(_ components: [RouteComponent]) -> [RouteComponent] {
        components
    }

    public static func buildBlock(_ components: [RouteComponent]...) -> [RouteComponent] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [RouteComponent]?) -> [RouteComponent] {
        component ?? []
    }

    public static func buildEither(first component: [RouteComponent]) -> [RouteComponent] {
        component
    }

    public static func buildEither(second component: [RouteComponent]) -> [RouteComponent] {
        component
    }

    public static func buildArray(_ components: [[RouteComponent]]) -> [RouteComponent] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [RouteComponent]) -> [RouteComponent] {
        component
    }
}
