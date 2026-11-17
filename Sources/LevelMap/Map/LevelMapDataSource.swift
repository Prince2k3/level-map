/// Supplies the levels shown on a ``LevelMap``.
///
/// Arrays and integer ranges conform already. Use ``EndlessLevels`` for a map that never ends.
public protocol LevelMapDataSource {
    associatedtype Level

    /// The number of levels, or `nil` for an endless supply.
    var levelCount: Int? { get }

    /// The level at `index`. Only called with indices below ``levelCount``.
    func level(at index: Int) -> Level
}

extension Array: LevelMapDataSource {
    public var levelCount: Int? { count }
    public func level(at index: Int) -> Element { self[index] }
}

extension Range: LevelMapDataSource where Bound == Int {
    public var levelCount: Int? { count }
    public func level(at index: Int) -> Int { lowerBound + index }
}

/// An endless supply of levels, made on demand.
///
/// ```swift
/// LevelMap(EndlessLevels { index in Level(number: index + 1) }, route: .serpentine()) { ... }
/// ```
public struct EndlessLevels<Level>: LevelMapDataSource {
    private let make: (Int) -> Level

    public init(_ make: @escaping (Int) -> Level) {
        self.make = make
    }

    public var levelCount: Int? { nil }
    public func level(at index: Int) -> Level { make(index) }
}

extension EndlessLevels where Level == Int {
    /// Endless levels identified by their index.
    public init() {
        self.init { $0 }
    }
}
