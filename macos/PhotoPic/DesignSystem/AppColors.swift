import SwiftUI

/// Centralized darkroom neutral color palette designed to prevent chromatic bias
/// when evaluating RAW skin tones and white balance.
package enum AppColors {
    // MARK: - Neutral Achromatic Surfaces
    package static let stageBackground = Color(red: 0.043, green: 0.043, blue: 0.047)       // #0B0B0C
    package static let windowCanvas = Color(red: 0.067, green: 0.067, blue: 0.071)          // #111112
    package static let panelSurface = Color(red: 0.094, green: 0.094, blue: 0.102)          // #18181A
    package static let elevatedSurface = Color(red: 0.125, green: 0.125, blue: 0.137)       // #202023
    package static let controlHover = Color(red: 0.165, green: 0.165, blue: 0.180)          // #2A2A2E
    package static let hudBackdrop = Color(red: 0.067, green: 0.067, blue: 0.075).opacity(0.88)

    // MARK: - Hairline Borders
    package static let borderSubtle = Color.white.opacity(0.08)
    package static let borderStrong = Color.white.opacity(0.16)
    package static let borderFocus = Color.white.opacity(0.28)

    // MARK: - Typography Ink
    package static let textPrimary = Color(red: 0.957, green: 0.957, blue: 0.965)           // #F4F4F6
    package static let textSecondary = Color(red: 0.659, green: 0.659, blue: 0.690)         // #A8A8B0
    package static let textTertiary = Color(red: 0.451, green: 0.451, blue: 0.486)          // #73737C
    package static let textOnAccent = Color(red: 0.055, green: 0.055, blue: 0.063)          // #0E0E10

    // MARK: - Primary Interactive Neutrals
    package static let primaryActionFill = Color(red: 0.941, green: 0.941, blue: 0.949)     // #F0F0F2
    package static let primaryActionHover = Color.white
    package static let secondaryButtonFill = Color(red: 0.145, green: 0.145, blue: 0.157)   // #252528

    // MARK: - Semantic Studio Feedback
    package static let approveGreen = Color(red: 0.133, green: 0.773, blue: 0.369)          // #22C55E
    package static let approveGreenTint = Color(red: 0.133, green: 0.773, blue: 0.369).opacity(0.16)
    package static let archiveRed = Color(red: 0.937, green: 0.267, blue: 0.267)            // #EF4444
    package static let archiveRedTint = Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.16)
    package static let warningAmber = Color(red: 0.961, green: 0.620, blue: 0.043)          // #F59E0B
    package static let warningAmberTint = Color(red: 0.961, green: 0.620, blue: 0.043).opacity(0.15)
    package static let infoBlue = Color(red: 0.220, green: 0.741, blue: 0.973)              // #38BDF8
    package static let infoBlueTint = Color(red: 0.220, green: 0.741, blue: 0.973).opacity(0.15)
}
