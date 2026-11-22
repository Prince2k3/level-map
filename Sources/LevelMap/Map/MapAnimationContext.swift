import SwiftUI

/// Captures the incoming update without publishing another view update.
@MainActor
final class MapAnimationContext {
    var transaction = Transaction()

    func resolved(fallback: Animation?, reduceMotion: Bool) -> Transaction {
        var result = transaction
        if reduceMotion || result.disablesAnimations {
            result.animation = nil
            result.disablesAnimations = true
        } else if result.animation == nil {
            result.animation = fallback
        }
        return result
    }
}

/// A value animation is a fallback, rather than an override of the caller's transaction.
struct MapDefaultAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(animation, value: value).transaction { transaction in
            if transaction.animation != nil { transaction.disablesAnimations = true }
        }
    }
}
