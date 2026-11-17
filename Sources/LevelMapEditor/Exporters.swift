import Foundation
import LevelMap

/// Turns a ``LevelMapDesign`` into code or data you can paste into an app.
public enum LevelMapExporter {
    /// A Swift file that declares the route and a modifier for the look.
    ///
    /// The route becomes `LevelRoute.<name>` and the look becomes `View.<name>Look()`. Themes are
    /// written by name (`LevelMapTheme.meadow`), so the app must declare themes with those names.
    public static func swift(_ design: LevelMapDesign) -> String {
        let name = identifier(design.name)
        var lines = [
            "// Made with LevelMapEditor.",
            "import LevelMap",
            "import SwiftUI",
            "",
            "extension LevelRoute {",
            "    static let \(name) = LevelRoute {",
            "        Start(x: \(number(design.route.start)))",
        ]
        lines += design.route.segments.flatMap { segmentLines($0, indent: 8) }
        if let repeating = design.route.repeating, !repeating.isEmpty {
            lines.append("        Repeat {")
            lines += repeating.flatMap { segmentLines($0, indent: 12) }
            lines.append("        }")
        }
        lines += [
            "    }",
            "}",
            "",
            "extension View {",
            "    /// Spacing and themes for `LevelRoute.\(name)`.",
            "    func \(name)Look() -> some View {",
        ]
        lines += lookLines(design)
        lines += [
            "    }",
            "}",
            "",
            "// Usage:",
            "// LevelMap(levels, route: .\(name)\(design.startsAtEnd ? ", startsAtEnd: true" : "")) { level, index, state in",
            "//     ...",
            "// }",
            "// .\(name)Look()",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The route as `RouteJSON`, pretty-printed with sorted keys.
    public static func json(_ design: LevelMapDesign) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(design.route) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Pieces

    private static func lookLines(_ design: LevelMapDesign) -> [String] {
        var lines = ["        levelSpacing(\(number(design.spacing)))"]
        let themes = design.themes.map(identifier)
        if design.usesChapters, let length = design.chapterLength {
            let list = themes.enumerated().map { $0.offset == 0 ? "LevelMapTheme.\($0.element)" : ".\($0.element)" }
            lines += [
                "            .levelMapChapters(every: \(length)) { chapter in",
                "                [\(list.joined(separator: ", "))][chapter % \(themes.count)]",
                "            }",
            ]
        } else if let theme = themes.first {
            lines.append("            .levelMapTheme(.\(theme))")
        }
        return lines
    }

    private static func segmentLines(_ segment: RouteJSON.Segment, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        switch segment {
        case let .straight(levels, toX):
            return [pad + "Straight(levels: \(levels)\(toX.map { ", toX: \(number($0))" } ?? ""))"]
        case let .serpentine(levels, amplitude, halfWaves):
            return [pad + "Serpentine(levels: \(levels), amplitude: \(number(amplitude)), halfWaves: \(halfWaves))"]
        case let .zigzag(levels, amplitude, halfWaves):
            return [pad + "Zigzag(levels: \(levels), amplitude: \(number(amplitude)), halfWaves: \(halfWaves))"]
        case let .detour(side, levels, inset):
            let insetText = abs(inset - 0.12) < 0.0005 ? "" : ", inset: \(number(inset))"
            return [pad + "Detour(around: .\(side == .leading ? "leading" : "trailing"), levels: \(levels)\(insetText))"]
        case let .spline(levels, points):
            return pointLines(pad + "Spline(levels: \(levels), through: ", points: points, suffix: ")", pad: pad)
        case let .polyline(levels, points, smooth):
            return pointLines(pad + "Polyline(levels: \(levels), points: ", points: points,
                              suffix: smooth ? ")" : ", smooth: false)", pad: pad)
        }
    }

    /// Short point lists stay on one line; longer ones get a line per point.
    private static func pointLines(_ head: String, points: [RoutePoint], suffix: String, pad: String) -> [String] {
        let items = points.map { ".init(x: \(number($0.x)), y: \(number($0.y)))" }
        if items.count <= 3 {
            return [head + "[" + items.joined(separator: ", ") + "]" + suffix]
        }
        return [head + "["] + items.map { pad + "    " + $0 + "," } + [pad + "]" + suffix]
    }

    /// Up to three decimals, without trailing zeros: `0.5`, `0.333`, `2`.
    static func number(_ value: CGFloat) -> String {
        var text = String(format: "%.3f", Double(value))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// A Swift identifier from a name a designer typed: `"Forest world"` becomes `forestWorld`.
    static func identifier(_ name: String) -> String {
        let words = name.split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init)
        guard let first = words.first else { return "myWorld" }
        var result = first.prefix(1).lowercased() + first.dropFirst()
        for word in words.dropFirst() { result += word.prefix(1).uppercased() + word.dropFirst() }
        if result.first?.isNumber == true { result = "_" + result }
        return result
    }
}
