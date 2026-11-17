import CoreGraphics

/// A decoration placed on the map.
struct PlacedDecoration: Sendable, Equatable {
    /// Index into the theme's ``LevelMapTheme/decorations``.
    let kind: Int
    let position: CGPoint
    /// The decoration's longer side, in points.
    let size: CGFloat
}

enum Scenery {
    /// Attempts per decoration before giving up on it, so crowded areas end up sparser instead of overlapping.
    static let attempts = 12

    /// Scatters decorations over `area`, keeping them clear of the road and of each other.
    ///
    /// The result depends only on the arguments, so the same seed always gives the same scenery.
    /// - Parameters:
    ///   - road: The road's centre line, densely sampled, in the same coordinates as `area`.
    ///   - keepOut: The minimum distance from the road's centre line to the edge of any decoration.
    static func scatter(_ decorations: [Decoration], density: Double, in area: CGRect,
                        avoiding road: [CGPoint], keepOut: CGFloat, seed: UInt64) -> [PlacedDecoration] {
        let totalWeight = decorations.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0, density > 0, area.width > 0, area.height > 0 else { return [] }
        let target = Int((Double(area.width * area.height) / 10_000 * density).rounded())
        guard target > 0 else { return [] }

        let largest = decorations.map(\.size.upperBound).max() ?? 0
        let reach = keepOut + largest
        let nearby = road.filter { $0.y >= area.minY - reach && $0.y <= area.maxY + reach }

        var random = SeededRandom(seed: seed)
        var placed: [PlacedDecoration] = []
        placed.reserveCapacity(target)
        for _ in 0..<target {
            for _ in 0..<attempts {
                // Draw every random value up front so each attempt uses the same amount of the sequence.
                let pick = random.unit() * totalWeight
                let sizeRoll = random.unit()
                let xRoll = CGFloat(random.unit())
                let yRoll = CGFloat(random.unit())

                let kind = Self.kind(at: pick, in: decorations)
                let bounds = decorations[kind].size
                let size = bounds.lowerBound + CGFloat(sizeRoll) * (bounds.upperBound - bounds.lowerBound)
                guard size < area.width, size < area.height else { continue }
                let radius = size / 2
                let point = CGPoint(x: area.minX + radius + xRoll * (area.width - size),
                                    y: area.minY + radius + yRoll * (area.height - size))

                let clearance = keepOut + radius
                guard distanceSquared(from: point, to: nearby) >= clearance * clearance else { continue }
                let overlaps = placed.contains {
                    let gap = (radius + $0.size / 2) * 0.9
                    return (point - $0.position).lengthSquared < gap * gap
                }
                guard !overlaps else { continue }
                placed.append(PlacedDecoration(kind: kind, position: point, size: size))
                break
            }
        }
        return placed
    }

    private static func kind(at pick: Double, in decorations: [Decoration]) -> Int {
        var remaining = pick
        for (index, decoration) in decorations.enumerated() where decoration.weight > 0 {
            remaining -= decoration.weight
            if remaining < 0 { return index }
        }
        return decorations.lastIndex { $0.weight > 0 } ?? 0
    }

    /// Squared distance from `point` to the nearest point of a polyline (infinity for an empty one).
    static func distanceSquared(from point: CGPoint, to polyline: [CGPoint]) -> CGFloat {
        guard let first = polyline.first else { return .infinity }
        guard polyline.count > 1 else { return (point - first).lengthSquared }
        var best = CGFloat.infinity
        for index in 1..<polyline.count {
            let a = polyline[index - 1]
            let b = polyline[index]
            let segment = b - a
            let lengthSquared = segment.lengthSquared
            let t = lengthSquared > 0
                ? min(max(((point.x - a.x) * segment.dx + (point.y - a.y) * segment.dy) / lengthSquared, 0), 1)
                : 0
            let closest = CGPoint(x: a.x + segment.dx * t, y: a.y + segment.dy * t)
            best = min(best, (point - closest).lengthSquared)
        }
        return best
    }
}
