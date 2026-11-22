import LevelMap
import SwiftUI

/// A course path in the style of language-learning apps: no visible road, chunky buttons that
/// weave down the screen, a banner opening each unit, and illustrations beside the path.
///
/// Every unit takes ten slots on the route: the first holds the unit's banner, drawn in a layer
/// across the full width, and the other nine are its lessons.
struct LessonsMap: View {
    /// Lessons completed so far.
    let completed: Int

    nonisolated static let slotsPerUnit = 10
    nonisolated static let lessonsPerUnit = slotsPerUnit - 1

    /// The route slot of a lesson, skipping each unit's banner slot.
    static func slot(ofLesson lesson: Int) -> Int {
        lesson / lessonsPerUnit * slotsPerUnit + 1 + lesson % lessonsPerUnit
    }

    var body: some View {
        LevelMap(EndlessLevels(), route: .lessons, current: Self.slot(ofLesson: completed)) { _, index, state, placement in
            if index % Self.slotsPerUnit == 0 {
                // The banner is drawn in a layer, across the map.
                Color.clear.frame(width: 1, height: 1)
            } else {
                LessonButton(index: index, state: state)
            }
        }
        .levelMapTheme(.lessons)
        .levelSpacing(112)
        .levelMapEdgeInset(48)
        .levelMapLayer(.belowRoad) { map in
            LessonIllustrations(map: map, currentUnit: Self.slot(ofLesson: completed) / Self.slotsPerUnit)
        }
        .levelMapLayer(.aboveNodes) { map in
            ForEach(map.levels.filter { $0 % Self.slotsPerUnit == 0 }, id: \.self) { slot in
                if let point = map.point(atLevel: Double(slot)) {
                    UnitBanner(unit: slot / Self.slotsPerUnit)
                        .frame(width: map.size.width - 32)
                        .position(x: map.size.width / 2, y: point.y)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { LessonStatsBar() }
    }
}

extension LevelRoute {
    /// Each unit starts in the middle, swings out to one side and then the other, and comes back.
    static let lessons = LevelRoute {
        Start(x: 0.5)
        Repeat { Serpentine(levels: LessonsMap.slotsPerUnit, amplitude: 0.2, halfWaves: 2) }
    }
}

extension LevelMapTheme {
    /// A plain white page with no road: the buttons themselves make the path.
    static let lessons = LevelMapTheme(
        background: .color(.white),
        road: RoadStyle(width: 0, color: .clear, completedColor: .clear))
}

// MARK: - Units

struct LessonUnit {
    let title: String
    let color: Color

    static func at(_ unit: Int) -> LessonUnit {
        let units = [
            LessonUnit(title: "Say hello and introduce yourself", color: Color(red: 0.33, green: 0.62, blue: 0.98)),
            LessonUnit(title: "Order at a café", color: Color(red: 0.95, green: 0.47, blue: 0.40)),
            LessonUnit(title: "Ask for directions around town", color: Color(red: 0.66, green: 0.42, blue: 0.96)),
            LessonUnit(title: "Talk about your family", color: Color(red: 0.14, green: 0.74, blue: 0.62)),
            LessonUnit(title: "Plan a weekend away", color: Color(red: 0.96, green: 0.62, blue: 0.18)),
        ]
        return units[unit % units.count]
    }
}

struct UnitBanner: View {
    let unit: Int

    var body: some View {
        let info = LessonUnit.at(unit)
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Unit \(unit + 1)").font(.title3.weight(.heavy))
                Text(info.title).font(.subheadline.weight(.semibold)).opacity(0.9)
            }
            Spacer()
            Image(systemName: "book.closed.fill")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.18), in: .rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.12), lineWidth: 2) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(info.color, in: .rect(cornerRadius: 16))
        .background { RoundedRectangle(cornerRadius: 16).fill(info.color).overlay(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.2))).offset(y: 4) }
    }
}

// MARK: - Buttons

struct LessonButton: View {
    let index: Int
    let state: LevelState

    private var unit: LessonUnit { LessonUnit.at(index / LessonsMap.slotsPerUnit) }
    private var position: Int { index % LessonsMap.slotsPerUnit }

    private var symbol: String {
        switch (state, position) {
        case (_, LessonsMap.lessonsPerUnit): "trophy.fill"
        case (_, 6): "shippingbox.fill"
        case (.completed, _): "checkmark"
        case (.current, _): "star.fill"
        case (.locked, 3): "book.fill"
        case (.locked, _): "lock.fill"
        }
    }

    private var face: Color {
        switch state {
        case .completed: Color(red: 1.0, green: 0.78, blue: 0.16)
        case .current: unit.color
        case .locked: Color(white: 0.88)
        }
    }

    var body: some View {
        ZStack {
            Ellipse().fill(face).overlay(Ellipse().fill(.black.opacity(0.22))).offset(y: 7)
            Ellipse().fill(face)
            Ellipse().fill(.white.opacity(0.25)).padding(10).offset(x: -6, y: -6).blur(radius: 4)
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(state == .locked ? Color(white: 0.68) : .white)
                .shadow(color: .black.opacity(state == .locked ? 0 : 0.15), radius: 0, y: 2)
        }
        .frame(width: 66, height: 58)
        .overlay {
            if state == .current {
                Circle().stroke(Color(white: 0.9), lineWidth: 7).frame(width: 88, height: 88).offset(y: 3)
                Circle().trim(from: 0, to: 0.3)
                    .stroke(Color(red: 1.0, green: 0.78, blue: 0.16), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 88, height: 88).offset(y: 3)
            }
        }
        .overlay(alignment: .top) {
            if state == .current {
                StartCallout(color: unit.color).offset(y: -50)
            }
        }
    }
}

struct StartCallout: View {
    let color: Color
    @State private var bob = false

    var body: some View {
        Text("START")
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.white, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.88), lineWidth: 2) }
            .overlay(alignment: .bottom) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(180))
                    .offset(y: 9)
            }
            .fixedSize()
            .offset(y: bob ? -4 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever()) { bob = true }
            }
    }
}

// MARK: - Illustrations

/// A character beside the path twice per unit, on the side away from the nearby lessons.
/// Units the player hasn't reached are drawn in grey.
struct LessonIllustrations: View {
    let map: LevelMapGeometry
    let currentUnit: Int

    private static let figures = ["figure.wave", "figure.socialdance", "figure.walk", "figure.2.and.child.holdinghands",
                                  "figure.hiking", "figure.mind.and.body"]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(map.levels.filter { [3, 7].contains($0 % LessonsMap.slotsPerUnit) }, id: \.self) { slot in
                if let point = map.point(atLevel: Double(slot) + 0.5),
                   let placement = map.placement(ofLevel: Double(slot) + 0.5) {
                    let unit = slot / LessonsMap.slotsPerUnit
                    let reached = unit <= currentUnit
                    let color = reached ? LessonUnit.at(unit).color : Color(white: 0.8)
                    Image(systemName: Self.figures[(slot / 4) % Self.figures.count])
                        .font(.system(size: 64, weight: .medium))
                        .foregroundStyle(color)
                        .frame(width: 120, height: 120)
                        .background(color.opacity(0.12), in: .circle)
                        .position(x: placement.side == .trailing ? map.size.width * 0.24 : map.size.width * 0.76,
                                  y: point.y)
                }
            }
        }
        .frame(width: map.size.width, height: map.size.height, alignment: .topLeading)
    }
}

// MARK: - Stats bar

struct LessonStatsBar: View {
    var body: some View {
        HStack {
            stat("globe.europe.africa.fill", "", .blue)
            Spacer()
            stat("flame.fill", "12", .orange)
            Spacer()
            stat("diamond.fill", "500", Color(red: 0.2, green: 0.7, blue: 0.95))
            Spacer()
            stat("heart.fill", "5", .red)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.9)).frame(height: 2) }
    }

    private func stat(_ symbol: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            if !value.isEmpty { Text(value).foregroundStyle(color) }
        }
        .font(.system(size: 18, weight: .heavy))
    }
}
