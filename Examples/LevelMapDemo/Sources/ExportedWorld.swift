// Made with LevelMapEditor.
import LevelMap
import SwiftUI

extension LevelRoute {
    static let tidewater = LevelRoute {
        Start(x: 0.5)
        Straight(levels: 2)
        Serpentine(levels: 10, amplitude: 0.32, halfWaves: 3)
        Detour(around: .leading, levels: 3)
        Zigzag(levels: 6, amplitude: 0.25, halfWaves: 2)
        Repeat {
            Serpentine(levels: 6, amplitude: 0.3, halfWaves: 2)
        }
    }
}

extension View {
    /// Spacing and themes for `LevelRoute.tidewater`.
    func tidewaterLook() -> some View {
        levelSpacing(110)
            .levelMapChapters(every: 20) { chapter in
                [LevelMapTheme.meadow, .desert, .snow][chapter % 3]
            }
    }
}

// Usage:
// LevelMap(levels, route: .tidewater, startsAtEnd: true) { level, index, state in
//     ...
// }
// .tidewaterLook()
