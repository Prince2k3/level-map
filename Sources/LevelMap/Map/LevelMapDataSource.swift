import Foundation

/// Supplies the levels shown on a ``LevelMap``.
///
/// Arrays and integer ranges conform already. Use ``EndlessLevels`` for a map that never ends.
public protocol LevelMapDataSource {
    associatedtype Level

    /// The number of levels, or `nil` for an endless supply.
    var levelCount: Int? { get }

    /// The level at `index`. Only called with indices below ``levelCount``.
    func level(at index: Int) -> Level

    /// A stable identity for the level. The default identifies fixed slots by their offset.
    func levelID(at index: Int) -> AnyHashable
}

extension Array: LevelMapDataSource {
    public var levelCount: Int? { count }
    public func level(at index: Int) -> Element { self[index] }
    public func levelID(at index: Int) -> AnyHashable {
        if let item = self[index] as? any Identifiable { return erasedLevelID(item) }
        return AnyHashable(index)
    }
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


extension LevelMapDataSource {
    public func levelID(at index: Int) -> AnyHashable { AnyHashable(index) }
}

/// A random-access collection adapted to map offsets, retaining each element's identity.
/// Collection indices need not start at zero. IDs must be unique and stable across updates.
public struct LevelMapCollection<Elements: RandomAccessCollection, ID: Hashable>: LevelMapDataSource {
    private let elements: Elements
    private let id: KeyPath<Elements.Element, ID>

    public init(_ elements: Elements, id: KeyPath<Elements.Element, ID>) {
        self.elements = elements
        self.id = id
    }

    public var levelCount: Int? { elements.count }
    public func level(at index: Int) -> Elements.Element {
        elements[elements.index(elements.startIndex, offsetBy: index)]
    }
    public func levelID(at index: Int) -> AnyHashable { AnyHashable(level(at: index)[keyPath: id]) }
}

private func erasedLevelID<Item: Identifiable>(_ item: Item) -> AnyHashable {
    AnyHashable(item.id)
}
