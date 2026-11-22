import LevelMap
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A theme the editor can offer, with the name your app uses for it.
///
/// The name goes into the exported code, so use the name of the static property that declares
/// the theme in your app: `NamedTheme("meadow", .meadow)` exports as `LevelMapTheme.meadow`.
public struct NamedTheme: Sendable, Identifiable {
    public let name: String
    public let theme: LevelMapTheme
    public var id: String { name }

    public init(_ name: String, _ theme: LevelMapTheme) {
        self.name = name
        self.theme = theme
    }
}

/// A debug tool for designing a level map: drag the road's control points on the live map,
/// add and arrange segments, pick spacing and themes, then copy the result as Swift code or JSON.
///
/// ```swift
/// #if DEBUG
/// LevelMapEditor(route: .myWorld, themes: [NamedTheme("meadow", .meadow), NamedTheme("snow", .snow)])
/// #endif
/// ```
/// Ship the exported code, not the editor.
public struct LevelMapEditor: View {
    private let external: Binding<LevelMapDesign>?
    @State private var local: LevelMapDesign
    private let themes: [NamedTheme]

    @State private var selection: SegmentRef?
    @State private var tab: Tab = .segments

    enum Tab: String, CaseIterable, Identifiable {
        case segments = "Segments", look = "Look", export = "Export"
        var id: Self { self }
    }

    /// Edits a design you own, for example one you save between launches.
    public init(design: Binding<LevelMapDesign>, themes: [NamedTheme] = []) {
        self.external = design
        self._local = State(initialValue: design.wrappedValue)
        self.themes = themes
    }

    /// Starts from a route. Routes with segment types of your own cannot be edited, so the
    /// editor starts from ``LevelMapDesign/starterRoute`` instead.
    public init(route: LevelRoute? = nil, name: String = "myWorld", themes: [NamedTheme] = []) {
        self.external = nil
        let json = route.flatMap { try? RouteJSON($0) } ?? LevelMapDesign.starterRoute
        self._local = State(initialValue: LevelMapDesign(name: name, route: json,
                                                         themes: themes.first.map { [$0.name] } ?? []))
        self.themes = themes
    }

    private var design: Binding<LevelMapDesign> { external ?? $local }

    public var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 700 {
                HStack(spacing: 0) {
                    map
                    Divider()
                    inspector.frame(width: min(400, proxy.size.width * 0.42))
                }
            } else {
                VStack(spacing: 0) {
                    map.frame(height: proxy.size.height * 0.55)
                    Divider()
                    inspector
                }
            }
        }
    }

    // MARK: Map

    @ViewBuilder
    private var map: some View {
        let design = design.wrappedValue
        if let route = try? design.buildRoute() {
            themed(
                LevelMap(0..<design.previewLevelCount, route: route, startsAtEnd: design.startsAtEnd) { _, index, _ in
                    Text("\(index + 1)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .levelMapSpacing(design.spacing)
                .levelMapUnlockAnimation(nil)
                .levelMapOverlay { context in
                    ControlPointOverlay(route: self.design.route, selection: $selection,
                                        overlay: context, spacing: design.spacing)
                },
                design: design)
            // Reopen at level 1 when the direction changes.
            .id(design.startsAtEnd)
        } else {
            ContentUnavailableView("This route can't be built", systemImage: "exclamationmark.triangle",
                                   description: Text("Every segment needs at least one level and one point."))
        }
    }

    @ViewBuilder
    private func themed(_ map: some View, design: LevelMapDesign) -> some View {
        let looks = design.themes.map { name in themes.first { $0.name == name }?.theme ?? .plain }
        if design.usesChapters, let length = design.chapterLength {
            map.levelMapChapters(every: length) { looks[$0 % looks.count] }
        } else {
            map.levelMapTheme(looks.first ?? .plain)
        }
    }

    // MARK: Inspector

    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            switch tab {
            case .segments: SegmentsPanel(design: design, selection: $selection)
            case .look: LookPanel(design: design, themes: themes)
            case .export: ExportPanel(design: design.wrappedValue)
            }
        }
    }
}

// MARK: - Segments

private struct SegmentsPanel: View {
    @Binding var design: LevelMapDesign
    @Binding var selection: SegmentRef?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $design.name)
                    .autocorrectionDisabled()
                LabeledSlider(title: "Start x", value: $design.route.start, range: 0...1)
            }
            section(.main, title: "Segments", footer: "Played once, in order.")
            section(.repeating, title: "Repeat",
                    footer: design.route.repeating == nil ? "Empty: the map ends after the last segment."
                                                          : "Repeated forever after the segments above.")
        }
    }

    private func section(_ section: RouteSection, title: String, footer: String) -> some View {
        Section {
            ForEach(Array(design.route.segments(in: section).enumerated()), id: \.offset) { index, segment in
                let ref = SegmentRef(section: section, index: index)
                SegmentRow(segment: segment, number: index + 1, selected: ref == selection) {
                    selection = selection == ref ? nil : ref
                } menu: {
                    rowMenu(ref)
                }
                if ref == selection, let binding = Binding($design.route[ref]) {
                    SegmentControls(segment: binding)
                }
            }
            Menu {
                ForEach(SegmentKind.allCases) { kind in
                    Button(kind.rawValue, systemImage: kind.symbol) {
                        selection = design.route.append(kind.template, to: section)
                    }
                }
            } label: {
                Label("Add segment", systemImage: "plus.circle.fill")
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    @ViewBuilder
    private func rowMenu(_ ref: SegmentRef) -> some View {
        Button("Move up", systemImage: "arrow.up") { selection = design.route.move(ref, by: -1) }
        Button("Move down", systemImage: "arrow.down") { selection = design.route.move(ref, by: 1) }
        Button(ref.section == .main ? "Move to Repeat" : "Move to Segments", systemImage: "arrow.left.arrow.right") {
            selection = design.route.switchSection(ref)
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            if let segment = design.route[ref] { selection = design.route.append(segment, to: ref.section) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            design.route.remove(ref)
            selection = nil
        }
    }
}

private struct SegmentRow<MenuContent: View>: View {
    let segment: RouteJSON.Segment
    let number: Int
    let selected: Bool
    let select: () -> Void
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack {
            Button(action: select) {
                HStack {
                    Image(systemName: segment.kind.symbol).frame(width: 24)
                    Text("\(number). \(segment.kind.rawValue)")
                    Spacer()
                    Text("\(segment.levelCount) levels").foregroundStyle(.secondary).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fontWeight(selected ? .semibold : .regular)
            Menu(content: menu) {
                Image(systemName: "ellipsis.circle").imageScale(.large)
            }
            .accessibilityLabel("Segment actions")
        }
    }
}

/// Controls for the values the handles on the map don't cover.
private struct SegmentControls: View {
    @Binding var segment: RouteJSON.Segment

    var body: some View {
        Stepper("Levels: \(segment.levelCount)", value: $segment.levelCount, in: 1...99)
        switch segment {
        case let .straight(levels, toX):
            Toggle("Move across", isOn: Binding(
                get: { toX != nil },
                set: { segment = .straight(levels: levels, toX: $0 ? 0.5 : nil) }))
            if let toX {
                LabeledSlider(title: "End x", value: Binding(
                    get: { toX }, set: { segment = .straight(levels: levels, toX: $0) }), range: 0...1)
            }
        case let .serpentine(levels, amplitude, halfWaves), let .zigzag(levels, amplitude, halfWaves):
            let zigzag = segment.kind == .zigzag
            let make = { (a: CGFloat, h: Int) -> RouteJSON.Segment in
                zigzag ? .zigzag(levels: levels, amplitude: a, halfWaves: h)
                       : .serpentine(levels: levels, amplitude: a, halfWaves: h)
            }
            LabeledSlider(title: "Amplitude", value: Binding(
                get: { amplitude }, set: { segment = make($0, halfWaves) }), range: 0...0.5)
            Stepper("Swings: \(halfWaves)", value: Binding(
                get: { halfWaves }, set: { segment = make(amplitude, $0) }), in: 1...20)
        case let .detour(side, levels, inset):
            Picker("Side", selection: Binding(
                get: { side }, set: { segment = .detour(side: $0, levels: levels, inset: inset) })) {
                Text("Leading").tag(RouteSide.leading)
                Text("Trailing").tag(RouteSide.trailing)
            }
            .pickerStyle(.segmented)
            LabeledSlider(title: "Inset", value: Binding(
                get: { inset }, set: { segment = .detour(side: side, levels: levels, inset: $0) }), range: 0...0.5)
        case let .polyline(levels, points, smooth):
            pointButtons
            Toggle("Smooth", isOn: Binding(
                get: { smooth }, set: { segment = .polyline(levels: levels, points: points, smooth: $0) }))
        case .spline:
            pointButtons
        }
    }

    private var pointButtons: some View {
        HStack {
            Text("\(segment.points.count) points · drag them on the map").foregroundStyle(.secondary)
            Spacer()
            Button("Remove point", systemImage: "minus.circle") { segment.removePoint() }
                .disabled(segment.points.count < 2)
            Button("Add point", systemImage: "plus.circle") { segment.addPoint() }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.footnote)
    }
}

// MARK: - Look

private struct LookPanel: View {
    @Binding var design: LevelMapDesign
    let themes: [NamedTheme]

    var body: some View {
        Form {
            Section("Layout") {
                LabeledSlider(title: "Spacing", value: $design.spacing, range: 60...200, step: 5, decimals: 0)
                Toggle("Level 1 at the bottom", isOn: $design.startsAtEnd)
            }
            if themes.isEmpty {
                Section("Themes") {
                    Text("Pass themes to the editor to try them here: LevelMapEditor(themes: [NamedTheme(\"meadow\", .meadow)])")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Toggle("Chapters", isOn: Binding(
                        get: { design.chapterLength != nil },
                        set: { design.chapterLength = $0 ? 20 : nil }))
                    if let length = design.chapterLength {
                        Stepper("Every \(length) levels", value: Binding(
                            get: { length }, set: { design.chapterLength = $0 }), in: 5...200, step: 5)
                    }
                    ForEach(Array(design.themes.enumerated()), id: \.offset) { index, name in
                        Picker(design.chapterLength == nil ? "Theme" : "Chapter \(index + 1)", selection: Binding(
                            get: { name }, set: { design.themes[index] = $0 })) {
                            ForEach(themes) { Text($0.name).tag($0.name) }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { design.themes.remove(at: index) }
                        }
                    }
                    if design.chapterLength != nil || design.themes.isEmpty {
                        Menu {
                            ForEach(themes) { theme in
                                Button(theme.name) { design.themes.append(theme.name) }
                            }
                        } label: {
                            Label(design.themes.isEmpty ? "Choose a theme" : "Add chapter theme", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    Text("Themes")
                } footer: {
                    Text(design.chapterLength == nil ? "One look for the whole map."
                         : design.themes.count < 2 ? "Chapters need at least two themes."
                         : "Chapters take turns through these themes. Swipe to remove one.")
                }
            }
        }
    }
}

// MARK: - Export

private struct ExportPanel: View {
    let design: LevelMapDesign
    @State private var format: Format = .swift
    @State private var copied = false

    enum Format: String, CaseIterable, Identifiable {
        case swift = "Swift", json = "JSON"
        var id: Self { self }
    }

    var body: some View {
        let text = format == .swift ? LevelMapExporter.swift(design) : LevelMapExporter.json(design)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Format", selection: $format) {
                    ForEach(Format.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
                Spacer()
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    copy(text)
                    copied = true
                }
                .buttonStyle(.borderedProminent)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Text(format == .swift ? "Paste into your app. Theme names must match themes your app declares."
                                  : "Load with JSONDecoder().decode(RouteJSON.self, from: data).route().")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .onChange(of: text) { copied = false }
        .onChange(of: format) { copied = false }
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Shared controls

private struct LabeledSlider: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var step: CGFloat = 0.01
    var decimals = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(decimals))).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

// MARK: - Preview

#Preview("Editor") {
    LevelMapEditor(route: LevelRoute {
        Start(x: 0.5)
        Straight(levels: 2)
        Spline(levels: 6, through: [.init(x: 0.2, y: 0.3), .init(x: 0.8, y: 0.7), .init(x: 0.5, y: 1)])
        Repeat { Serpentine(levels: 6, halfWaves: 2) }
    }, themes: [
        NamedTheme("grass", LevelMapTheme(background: .color(.green.opacity(0.4)))),
        NamedTheme("sand", LevelMapTheme(background: .color(.orange.opacity(0.3)))),
    ])
}
