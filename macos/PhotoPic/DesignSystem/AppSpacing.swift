import CoreGraphics

/// Consistent 4pt/8pt spatial grid and bar metrics for macOS layouts.
package enum AppSpacing {
    package static let xxs: CGFloat = 4
    package static let xs: CGFloat = 6
    package static let sm: CGFloat = 8
    package static let md: CGFloat = 12
    package static let lg: CGFloat = 16
    package static let xl: CGFloat = 24
    package static let xxl: CGFloat = 32
    package static let xxxl: CGFloat = 48

    // MARK: - Studio Chrome Dimensions
    package static let topBarHeight: CGFloat = 52
    package static let bottomControlBarHeight: CGFloat = 68
    package static let onboardingMaxWidth: CGFloat = 540
    package static let settingsWidth: CGFloat = 680
    package static let settingsHeight: CGFloat = 560
    package static let newSessionSheetWidth: CGFloat = 420
    package static let hairline: CGFloat = 1
    package static let cardGridMinWidth: CGFloat = 264
    package static let archivedGridMinWidth: CGFloat = 156
}
