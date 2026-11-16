import SwiftUI

/// Animation curves and gesture physics calibrated for zero-lag studio culling.
package enum AppMotion {
    /// Press scale for pointer buttons (responds on pointer-down).
    package static let pressScale: CGFloat = 0.97

    /// Fast tactile button response.
    package static let buttonPress = Animation.easeOut(duration: 0.12)

    /// Subtle UI state & pill transitions.
    package static let quickEaseOut = Animation.easeOut(duration: 0.16)

    /// Modal/sheet and banner entry curve.
    package static let panelTransition = Animation.spring(response: 0.28, dampingFraction: 1.0)

    /// Critically damped snap-back when a swipe drag falls short of threshold.
    package static let cardSnapBack = Animation.spring(response: 0.28, dampingFraction: 1.0)

    /// Momentum-driven card throw exit after trackpad/mouse swipe commit.
    package static let cardCommitThrow = Animation.spring(response: 0.24, dampingFraction: 0.86)

    /// Horizontal displacement required to commit a swipe without high velocity.
    package static let swipeDistanceThreshold: CGFloat = 110

    /// Projected velocity multiplier (Apple Designing Fluid Interfaces momentum projection).
    package static let projectionSeconds: CGFloat = 0.18

    /// Projects resting X offset from current offset and horizontal gesture velocity.
    package static func projectedOffsetX(current: CGFloat, velocityX: CGFloat) -> CGFloat {
        current + velocityX * projectionSeconds
    }

    /// Progressive rubber-band resistance beyond swipe limits.
    package static func rubberBand(_ delta: CGFloat, limit: CGFloat = 240) -> CGFloat {
        let absDelta = abs(delta)
        let damped = (absDelta * limit * 0.55) / (limit + 0.55 * absDelta)
        return delta >= 0 ? damped : -damped
    }

    /// Chooses gentle crossfade or nil when Reduce Motion is enabled.
    package static func resolve(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : animation
    }
}
