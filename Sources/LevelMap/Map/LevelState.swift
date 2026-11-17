/// Where a level stands relative to the player's current level.
public enum LevelState: Sendable, Hashable {
    case completed
    case current
    case locked

    public init(level index: Int, current: Int) {
        self = index < current ? .completed : index == current ? .current : .locked
    }
}
