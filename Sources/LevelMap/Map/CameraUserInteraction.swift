import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Observes scroll ownership without replacing the scroll view's gestures.
struct CameraUserInteraction: ViewModifier {
    @Environment(\.isScrollEnabled) private var isScrollEnabled
    let action: @MainActor () -> Void
    let accessibilityScroll: @MainActor (Edge) -> Void

    func body(content: Content) -> some View {
        observed(content)
            .accessibilityScrollAction { edge in
                guard isScrollEnabled else { return }
                accessibilityScroll(edge)
            }
    }

    @ViewBuilder private func observed(_ content: Content) -> some View {
        if #available(iOS 18, macOS 15, visionOS 2, *) {
            content.onScrollPhaseChange { _, phase in
                if isScrollEnabled, Self.isUserScroll(phase) { action() }
            }
        } else {
            content
                .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in if isScrollEnabled { action() } })
                #if os(macOS)
                .background(LegacyWheelObserver(action: { if isScrollEnabled { action() } }))
                #endif
        }
    }

    @available(iOS 18, macOS 15, visionOS 2, *)
    static func isUserScroll(_ phase: ScrollPhase) -> Bool {
        phase == .interacting || phase == .decelerating
    }
}

/// A measured chunk position used to page the existing ScrollView for accessibility actions.
struct CameraScrollSnapshot: Equatable {
    let index: Int
    let origin: CGFloat
    let extent: CGFloat

    func pageAnchor(direction: CGFloat, viewport: CGFloat) -> CGFloat? {
        let denominator = viewport - extent
        guard abs(denominator) > 0.001 else { return nil }
        return (origin - direction * viewport * 0.8) / denominator
    }
}

@MainActor final class CameraScrollObservation {
    var snapshot: CameraScrollSnapshot?
}

#if os(macOS)
/// Only used on macOS 14, where SwiftUI has no scroll-phase callback.
struct LegacyWheelObserver: NSViewRepresentable {
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> WheelView { WheelView(action: action) }
    func updateNSView(_ view: WheelView, context: Context) { view.action = action }
    static func dismantleNSView(_ view: WheelView, coordinator: ()) { view.stop() }

    final class WheelView: NSView {
        var action: @MainActor () -> Void
        private var monitor: Any?

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated {
                    if let self, let window = self.window, event.window === window,
                       Self.acceptsScroll(at: self.convert(event.locationInWindow, from: nil), in: self.bounds,
                                          delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)) {
                        self.action()
                    }
                }
                return event
            }
        }

        static func acceptsScroll(at point: CGPoint, in bounds: CGRect, delta: CGSize) -> Bool {
            bounds.contains(point) && (delta.width != 0 || delta.height != 0)
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
