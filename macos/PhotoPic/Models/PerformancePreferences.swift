import Foundation

/// Presets balancing offline AI depth, preview dimensions, and host hardware capacity.
package enum PerformanceTier: String, Codable, CaseIterable, Sendable, Identifiable {
    case fullAI
    case balancedAI
    case lightweightNoAI

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .fullAI:
            return "Estudio Completo (GPU + IA Completa)"
        case .balancedAI:
            return "Equilibrado (GPU + Rostros Rápidos)"
        case .lightweightNoAI:
            return "Modo Ligero (Sin IA · Solo Tethering y RAW)"
        }
    }

    package var subtitle: String {
        switch self {
        case .fullAI:
            return "Revelado RAW GPU + conteo de personas, rostros, parpadeo y poses de 19 puntos."
        case .balancedAI:
            return "Revelado RAW GPU + conteo ligero de rostros y ojos, sin esqueleto corporal pesado."
        case .lightweightNoAI:
            return "Desactiva toda la IA en segundo plano para máxima fluidez en equipos modestos."
        }
    }

    package var shortBadge: String {
        switch self {
        case .fullAI: return "IA Completa"
        case .balancedAI: return "IA Ligera"
        case .lightweightNoAI: return "Sin IA"
        }
    }
}

/// Snapshot of physical host hardware capabilities inspected at startup.
package struct HardwareAuditReport: Sendable, Equatable {
    package let cpuBrand: String
    package let architectureLabel: String
    package let isAppleSilicon: Bool
    package let hasAppleNeuralEngine: Bool
    package let activeCores: Int
    package let physicalMemoryGB: Int
    package let gpuName: String
    package let hasMetalGPU: Bool
    package let recommendedTier: PerformanceTier
    package let recommendationReason: String

    package init(
        cpuBrand: String,
        architectureLabel: String,
        isAppleSilicon: Bool,
        hasAppleNeuralEngine: Bool,
        activeCores: Int,
        physicalMemoryGB: Int,
        gpuName: String,
        hasMetalGPU: Bool,
        recommendedTier: PerformanceTier,
        recommendationReason: String
    ) {
        self.cpuBrand = cpuBrand
        self.architectureLabel = architectureLabel
        self.isAppleSilicon = isAppleSilicon
        self.hasAppleNeuralEngine = hasAppleNeuralEngine
        self.activeCores = activeCores
        self.physicalMemoryGB = physicalMemoryGB
        self.gpuName = gpuName
        self.hasMetalGPU = hasMetalGPU
        self.recommendedTier = recommendedTier
        self.recommendationReason = recommendationReason
    }

    package var neuralEngineSummary: String {
        hasAppleNeuralEngine
            ? "Integrado en chip Apple Silicon (ANE)"
            : "No disponible (ejecuta en CPU / GPU)"
    }
}

/// Persisted performance and AI switches configured during setup or in Settings.
package struct PerformancePreferences: Codable, Sendable, Equatable {
    package var tier: PerformanceTier
    package var enableVisionAutoTagging: Bool
    package var detectBodyPoses: Bool
    package var viewportMaxDimension: Double
    package var hasCompletedGuidedSetup: Bool

    package init(
        tier: PerformanceTier,
        enableVisionAutoTagging: Bool,
        detectBodyPoses: Bool,
        viewportMaxDimension: Double,
        hasCompletedGuidedSetup: Bool = false
    ) {
        self.tier = tier
        self.enableVisionAutoTagging = enableVisionAutoTagging
        self.detectBodyPoses = detectBodyPoses
        self.viewportMaxDimension = viewportMaxDimension
        self.hasCompletedGuidedSetup = hasCompletedGuidedSetup
    }

    package static func preset(for tier: PerformanceTier, completedSetup: Bool = false) -> PerformancePreferences {
        switch tier {
        case .fullAI:
            return PerformancePreferences(
                tier: .fullAI,
                enableVisionAutoTagging: true,
                detectBodyPoses: true,
                viewportMaxDimension: 2400,
                hasCompletedGuidedSetup: completedSetup
            )
        case .balancedAI:
            return PerformancePreferences(
                tier: .balancedAI,
                enableVisionAutoTagging: true,
                detectBodyPoses: false,
                viewportMaxDimension: 1920,
                hasCompletedGuidedSetup: completedSetup
            )
        case .lightweightNoAI:
            return PerformancePreferences(
                tier: .lightweightNoAI,
                enableVisionAutoTagging: false,
                detectBodyPoses: false,
                viewportMaxDimension: 1600,
                hasCompletedGuidedSetup: completedSetup
            )
        }
    }
}
