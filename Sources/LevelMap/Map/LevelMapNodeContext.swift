/// The model and presentation information supplied to a level map's node content builder.
///
/// `index` is a zero-based road offset, independent of collection indices and model identity.
/// The map creates a fresh context when its inputs change. Keep durable node state in the model.
public struct LevelMapNodeContext<Level> {
    /// The model at this position on the road.
    public let level: Level
    /// The zero-based position along the road.
    public let index: Int
    /// Whether this node is completed, current or locked.
    public let state: LevelState
    /// The node's side, heading, axis and layout direction.
    public let placement: LevelPlacement

    /// Creates a context for a node, for example when previewing node content independently.
    public init(level: Level, index: Int, state: LevelState, placement: LevelPlacement) {
        self.level = level
        self.index = index
        self.state = state
        self.placement = placement
    }
}

extension LevelMapNodeContext: Sendable where Level: Sendable {}
extension LevelMapNodeContext: Equatable where Level: Equatable {}
extension LevelMapNodeContext: Hashable where Level: Hashable {}
