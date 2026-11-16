import Darwin
import Foundation
import Metal

/// Audits the host Mac hardware (CPU, Apple Neural Engine presence, RAM, Metal GPU)
/// and recommends the safest performance/AI profile without blocking modest machines.
package enum HardwareCapabilityAuditor {
    package static func auditCurrentMac() -> HardwareAuditReport {
        let cpuBrand = readSysctlString("machdep.cpu.brand_string") ?? fallbackArchitectureTitle()
        let activeCores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let bytesPerGB: Double = 1024 * 1024 * 1024
        let memoryGB = max(1, Int((Double(ProcessInfo.processInfo.physicalMemory) / bytesPerGB).rounded()))

        #if arch(arm64)
        let isAppleSilicon = true
        let hasNeuralEngine = true
        let archLabel = "Apple Silicon (arm64)"
        #else
        let isAppleSilicon = false
        let hasNeuralEngine = false
        let archLabel = "Intel (x86_64)"
        #endif

        let metalDevice = MTLCreateSystemDefaultDevice()
        let hasMetalGPU = metalDevice != nil
        let gpuName = metalDevice?.name ?? "Renderizado CPU por software"

        let evaluated = evaluateTier(
            isAppleSilicon: isAppleSilicon,
            ramGB: memoryGB,
            cores: activeCores,
            hasMetalGPU: hasMetalGPU
        )

        return HardwareAuditReport(
            cpuBrand: cpuBrand,
            architectureLabel: archLabel,
            isAppleSilicon: isAppleSilicon,
            hasAppleNeuralEngine: hasNeuralEngine,
            activeCores: activeCores,
            physicalMemoryGB: memoryGB,
            gpuName: gpuName,
            hasMetalGPU: hasMetalGPU,
            recommendedTier: evaluated.tier,
            recommendationReason: evaluated.reason
        )
    }

    package static func evaluateTier(
        isAppleSilicon: Bool,
        ramGB: Int,
        cores: Int,
        hasMetalGPU: Bool
    ) -> (tier: PerformanceTier, reason: String) {
        if !hasMetalGPU || ramGB < 8 || cores < 4 {
            return (
                .lightweightNoAI,
                "Detectamos recursos ajustados (\(ramGB) GB RAM, \(cores) núcleos\(hasMetalGPU ? "" : ", sin GPU Metal")). "
                    + "Recomendamos desactivar la IA automática para priorizar el tethering USB y el visor RAW sin tirones."
            )
        }

        if !isAppleSilicon || ramGB < 12 {
            let reason = isAppleSilicon
                ? "Tu Mac cuenta con Neural Engine pero \(ramGB) GB de RAM unificada; el modo Equilibrado analiza rostros y ojos sin saturar memoria con poses de cuerpo completo."
                : "Equipo Intel sin Neural Engine físico dedicado; el modo Equilibrado evita sobrecargar la CPU omitiendo detección corporal de 19 puntos."
            return (.balancedAI, reason)
        }

        return (
            .fullAI,
            "Apple Silicon con Neural Engine integrado, GPU Metal y \(ramGB) GB de RAM: tu equipo ejecuta IA completa de rostros, ojos y poses en tiempo real sin frenar la captura."
        )
    }

    private static func readSysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let decoded = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private static func fallbackArchitectureTitle() -> String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Procesador Intel x86_64"
        #endif
    }
}

/// Persists `PerformancePreferences` cleanly inside `UserDefaults`.
@MainActor
package final class PerformancePreferencesStore {
    private static let storageKey = "photopic.performancePreferences.v1"
    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package func loadOrSeed(from audit: HardwareAuditReport) -> PerformancePreferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(PerformancePreferences.self, from: data) else {
            let seeded = PerformancePreferences.preset(for: audit.recommendedTier, completedSetup: false)
            save(seeded)
            return seeded
        }
        return decoded
    }

    package func save(_ preferences: PerformancePreferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
