import SwiftUI

/// Centralized typographic tokens pairing native SF Pro hierarchy with
/// tabular SF Mono numerals for studio counters and EXIF metadata.
package enum AppTypography {
    package static let displayTitle = Font.system(size: 26, weight: .semibold, design: .default)
    package static let heroSymbol = Font.system(size: 24, weight: .medium, design: .default)
    package static let pageTitle = Font.system(size: 20, weight: .semibold, design: .default)
    package static let sectionTitle = Font.system(size: 15, weight: .semibold, design: .default)
    package static let cardTitle = Font.system(size: 14, weight: .medium, design: .default)
    package static let body = Font.system(size: 13, weight: .regular, design: .default)
    package static let bodyMedium = Font.system(size: 13, weight: .medium, design: .default)
    package static let caption = Font.system(size: 11.5, weight: .regular, design: .default)
    package static let captionMedium = Font.system(size: 11.5, weight: .medium, design: .default)
    package static let micro = Font.system(size: 10.5, weight: .medium, design: .default)

    // MARK: - Monospaced Tabular Tokens
    package static let monoCounter = Font.system(size: 13, weight: .semibold, design: .monospaced)
        .monospacedDigit()
    package static let monoCaption = Font.system(size: 11.5, weight: .medium, design: .monospaced)
        .monospacedDigit()
    package static let monoMicro = Font.system(size: 10.5, weight: .semibold, design: .monospaced)
        .monospacedDigit()
    package static let monoPath = Font.system(size: 11.5, weight: .regular, design: .monospaced)
}
