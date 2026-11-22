import CoreGraphics
import SwiftUI
import Testing
@testable import LevelMap

@Suite("Placement layout direction")
struct PlacementDirectionTests {
    @Test func physicalCoordinatesResolveToSemanticSides() {
        let leftLTR = LevelPlacement(physicalCrossFraction: 0.2, heading: .zero)
        let leftRTL = LevelPlacement(physicalCrossFraction: 0.2, heading: .zero, layoutDirection: .rightToLeft)
        #expect(leftLTR.side == .leading)
        #expect(leftRTL.side == .trailing)
        #expect(leftLTR.physicalSide == .left)
        #expect(leftRTL.physicalSide == .left)
        #expect(abs(leftRTL.crossFraction - 0.8) < 0.0001)
        #expect(abs(leftRTL.physicalCrossFraction - 0.2) < 0.0001)
        let rightRTL = LevelPlacement(physicalCrossFraction: 0.8, heading: .zero, layoutDirection: .rightToLeft)
        #expect(rightRTL.side == .leading)
        #expect(rightRTL.physicalSide == .right)
    }

    @Test func existingLogicalInitializerKeepsItsMeaning() {
        let old = LevelPlacement(crossFraction: 0.2, heading: .zero)
        let rtl = LevelPlacement(crossFraction: 0.2, heading: .zero, layoutDirection: .rightToLeft)
        #expect(old.side == .leading)
        #expect(rtl.side == .leading)
        #expect(old.physicalSide == .left)
        #expect(rtl.physicalSide == .right)
        #expect(abs(rtl.physicalCrossFraction - 0.8) < 0.0001)
        #expect(old != rtl)
    }

    @Test func horizontalCrossAxisIsNotReversedByLanguageOrAlongAxisMirroring() {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let top = LevelPlacement(physicalCrossFraction: 0.2, heading: .zero, axis: .horizontal,
                                     layoutDirection: direction)
            let bottom = LevelPlacement(physicalCrossFraction: 0.8, heading: .zero, axis: .horizontal,
                                        layoutDirection: direction)
            #expect(top.side == .leading)
            #expect(top.physicalSide == .top)
            #expect(bottom.side == .trailing)
            #expect(bottom.physicalSide == .bottom)
            #expect(LevelMapMarkPlacement.outside().direction(at: top) == -1)
        }
    }

    @Test func geometryPropagatesDirectionWithoutDoubleMirroringCoordinates() throws {
        let layout = ChunkLayout(road: LevelRoute.straight.resolved(width: 100, spacing: 100),
                                 dataCount: 10, chunkSize: 10)
        for axis in [Axis.vertical, .horizontal] {
            for mirrored in [false, true] {
                func geometry(_ direction: LayoutDirection) -> LevelMapGeometry {
                    LevelMapGeometry(size: CGSize(width: 100, height: 1000), axis: axis, layout: layout,
                                     levels: 0..<10, originAlong: 0, mirrored: mirrored, zoom: 1,
                                     layoutDirection: direction)
                }
                let ltr = geometry(.leftToRight), rtl = geometry(.rightToLeft)
                #expect(rtl.layoutDirection == .rightToLeft)
                #expect(ltr.point(atLevel: 3) == rtl.point(atLevel: 3))
                let placement = try #require(rtl.placement(ofLevel: 3))
                #expect(placement.layoutDirection == .rightToLeft)
                #expect(placement.axis == axis)
                #expect(ltr.heading(atLevel: 3) == rtl.heading(atLevel: 3))
            }
        }
    }

    @Test @MainActor func swiftUIRoadAndNodeRenderingMatchSemanticSide() throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let placement = LevelPlacement(crossFraction: 0.2, heading: .zero, layoutDirection: direction)
            let view = ZStack(alignment: .topLeading) {
                Color.black
                // A path layer and a positioned node must mirror together.
                Path(ellipseIn: CGRect(x: 15, y: 15, width: 10, height: 10)).fill(.green)
                Color.red.frame(width: 10, height: 10).position(x: 20, y: 50)
            }.frame(width: 100, height: 100).environment(\.layoutDirection, direction)
            let pixels = try pixels(of: view)
            let nodeX = try #require(center(of: .red, in: pixels)).x
            let roadX = try #require(center(of: .green, in: pixels)).x
            #expect(abs(nodeX - roadX) < 1)
            #expect((nodeX < 50) == (placement.physicalSide == .left))
            #expect(placement.side == .leading)
        }
    }

    @Test @MainActor func semanticLabelsStayTowardsTheCentreInBothDirections() throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let placement = LevelPlacement(physicalCrossFraction: 0.2, heading: .zero, layoutDirection: direction)
            let view = ZStack(alignment: .topLeading) {
                Color.black
                Color.red.frame(width: 10, height: 10)
                    .overlay(alignment: placement.side == .leading ? .leading : .trailing) {
                        Color.green.frame(width: 10, height: 10)
                            .offset(x: placement.side == .leading ? 15 : -15)
                    }
                    .position(x: placement.crossFraction * 100, y: 50)
            }.frame(width: 100, height: 100).environment(\.layoutDirection, direction)
            let pixels = try pixels(of: view)
            let node = try #require(center(of: .red, in: pixels))
            let label = try #require(center(of: .green, in: pixels))
            #expect(abs(node.x - 19.5) < 1)
            #expect(label.x > node.x)
        }
    }

    @Test @MainActor func outsideMarksRenderTowardsThePhysicalEdgeInBothDirections() throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let placement = LevelPlacement(crossFraction: 0.2, heading: .zero, layoutDirection: direction)
            let view = MarkLayout(axis: .vertical, scale: 1) {
                Color.red.frame(width: 10, height: 10)
                    .layoutValue(key: MarkSpotKey.self,
                                 value: MarkSpot(point: CGPoint(x: 20, y: 50),
                                                 direction: LevelMapMarkPlacement.outside().direction(at: placement),
                                                 spacing: 5))
            }.frame(width: 100, height: 100).background(.black).environment(\.layoutDirection, direction)
            let x = try #require(center(of: .red, in: pixels(of: view))).x
            #expect(abs(x - (direction == .leftToRight ? 9.5 : 89.5)) < 1)
        }
    }

    private enum Ink { case red, green }

    @MainActor private func pixels(of view: some View) throws -> [UInt8] {
        let image = try #require(ImageRenderer(content: view).cgImage)
        #expect(image.width == 100 && image.height == 100)
        var bytes = [UInt8](repeating: 0, count: 100 * 100 * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 100, height: 100, bitsPerComponent: 8,
                                    bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        return bytes
    }

    private func center(of ink: Ink, in bytes: [UInt8]) -> CGPoint? {
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<100 { for x in 0..<100 {
            let i = (y * 100 + x) * 4
            let matches = ink == .red ? bytes[i] > 200 && bytes[i + 1] < 100
                                     : bytes[i + 1] > 140 && bytes[i] < 100
            if matches { xs.append(x); ys.append(y) }
        } }
        guard !xs.isEmpty else { return nil }
        return CGPoint(x: Double(xs.reduce(0, +)) / Double(xs.count),
                       y: Double(ys.reduce(0, +)) / Double(ys.count))
    }
}
