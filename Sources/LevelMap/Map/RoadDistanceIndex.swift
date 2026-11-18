import CoreGraphics
import os

/// The road through a layer, for ``LevelMapGeometry/distanceToRoad(from:)``.
///
/// Built on first use rather than with the geometry: the map makes a fresh geometry whenever it
/// redraws its layers, and most layers never ask how far the road is. Segments are bucketed into a
/// grid, so a terrain layer that tests thousands of points looks at a few nearby segments for each
/// instead of the whole road.
final class RoadDistanceIndex: Sendable {
    private struct Grid: Sendable {
        let points: [CGPoint]
        let origin: CGPoint
        let columns: Int
        let rows: Int
        /// Segment indices (the segment ending at `points[index]`) for each cell, row by row.
        let cells: [[Int]]
    }

    private static let cellSize: CGFloat = 48

    private let build: @Sendable () -> [CGPoint]
    private let grid = OSAllocatedUnfairLock<Grid?>(initialState: nil)

    init(build: @escaping @Sendable () -> [CGPoint]) {
        self.build = build
    }

    /// How far `point` is from the nearest part of the road, or infinity when there is no road.
    func distance(from point: CGPoint) -> CGFloat {
        let grid = resolvedGrid()
        let points = grid.points
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return (point - first).length }

        let size = Self.cellSize
        let column = Int(((point.x - grid.origin.x) / size).rounded(.down))
        let row = Int(((point.y - grid.origin.y) / size).rounded(.down))
        // Rings of cells around the point, nearest first. Once the best distance found is no more
        // than the gap to the next ring, nothing further out can beat it.
        let maxRing = max(abs(column), abs(column - grid.columns), abs(row), abs(row - grid.rows)) + 1
        var best = CGFloat.infinity
        for ring in 0...maxRing {
            let reach = CGFloat(max(ring - 1, 0)) * size
            if best <= reach * reach { break }
            for r in (row - ring)...(row + ring) where r >= 0 && r < grid.rows {
                let edgeRow = r == row - ring || r == row + ring
                let step = edgeRow ? 1 : 2 * ring
                var c = column - ring
                while c <= column + ring {
                    if c >= 0 && c < grid.columns {
                        for index in grid.cells[r * grid.columns + c] {
                            best = min(best, Self.distanceSquared(from: point, segment: points[index - 1], points[index]))
                        }
                    }
                    c += max(step, 1)
                }
            }
        }
        return best.squareRoot()
    }

    private func resolvedGrid() -> Grid {
        if let grid = grid.withLock({ $0 }) { return grid }
        let made = Self.makeGrid(build())
        return grid.withLock { stored in
            if let stored { return stored }
            stored = made
            return made
        }
    }

    private static func makeGrid(_ points: [CGPoint]) -> Grid {
        guard let first = points.first else {
            return Grid(points: [], origin: .zero, columns: 0, rows: 0, cells: [])
        }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        let columns = Int(((maxX - minX) / cellSize).rounded(.down)) + 1
        let rows = Int(((maxY - minY) / cellSize).rounded(.down)) + 1
        var cells = Array(repeating: [Int](), count: columns * rows)
        for index in points.indices.dropFirst() {
            let a = points[index - 1], b = points[index]
            let lowColumn = Int(((min(a.x, b.x) - minX) / cellSize).rounded(.down))
            let highColumn = Int(((max(a.x, b.x) - minX) / cellSize).rounded(.down))
            let lowRow = Int(((min(a.y, b.y) - minY) / cellSize).rounded(.down))
            let highRow = Int(((max(a.y, b.y) - minY) / cellSize).rounded(.down))
            for r in lowRow...highRow {
                for c in lowColumn...highColumn {
                    cells[r * columns + c].append(index)
                }
            }
        }
        return Grid(points: points, origin: CGPoint(x: minX, y: minY), columns: columns, rows: rows, cells: cells)
    }

    private static func distanceSquared(from point: CGPoint, segment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let segment = b - a
        let lengthSquared = segment.lengthSquared
        let t = lengthSquared > 0
            ? min(max(((point.x - a.x) * segment.dx + (point.y - a.y) * segment.dy) / lengthSquared, 0), 1)
            : 0
        let closest = CGPoint(x: a.x + segment.dx * t, y: a.y + segment.dy * t)
        return (point - closest).lengthSquared
    }
}
