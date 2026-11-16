import Foundation

/// Pure state gate enforcing the Anti-Old-Gallery shield across pre-catalog enumeration,
/// live PTP notifications, and Android Smart Delta Watcher polling.
package struct TetherBaselineGate: Sendable {
    package let connectedAtTimestamp: Date
    package private(set) var isCatalogComplete: Bool = false
    package private(set) var baselineKeys: Set<String> = []
    package private(set) var downloadedOrInFlightKeys: Set<String> = []
    package private(set) var baselineMaxDeviceDate: Date?

    package init(connectedAtTimestamp: Date = Date()) {
        self.connectedAtTimestamp = connectedAtTimestamp
    }

    package static func itemKey(
        ptpHandle: UInt32,
        filename: String,
        fileSize: Int64
    ) -> String {
        "h:\(ptpHandle)|n:\(filename.lowercased())|s:\(fileSize)"
    }

    /// Indexes pre-existing SD card or phone roll items without ever triggering a download.
    package mutating func recordPreCatalogItem(key: String, itemDate: Date?) {
        baselineKeys.insert(key)
        guard let itemDate else { return }
        if let currentMax = baselineMaxDeviceDate {
            if itemDate > currentMax {
                baselineMaxDeviceDate = itemDate
            }
        } else {
            baselineMaxDeviceDate = itemDate
        }
    }

    package mutating func markCatalogComplete() {
        isCatalogComplete = true
    }

    /// Decides whether a candidate item represents a brand-new capture made after USB connection.
    package mutating func shouldDownloadLiveItem(
        key: String,
        itemDate: Date?,
        wasAddedAfterCatalog: Bool
    ) -> Bool {
        guard isCatalogComplete else {
            recordPreCatalogItem(key: key, itemDate: itemDate)
            return false
        }
        guard !baselineKeys.contains(key), !downloadedOrInFlightKeys.contains(key) else {
            return false
        }

        if wasAddedAfterCatalog {
            downloadedOrInFlightKeys.insert(key)
            return true
        }

        // Smart Delta Watcher path (Android PTP batching): tolerate 2s clock skew against
        // either the newest pre-existing item or the Mac's connection timestamp.
        let skewTolerance: TimeInterval = 2.0
        let isNewerThanBaseline: Bool
        if let itemDate {
            let afterConnection = itemDate >= connectedAtTimestamp.addingTimeInterval(-skewTolerance)
            let afterMaxPreexisting = baselineMaxDeviceDate.map {
                itemDate >= $0.addingTimeInterval(-skewTolerance)
            } ?? true
            isNewerThanBaseline = afterConnection || afterMaxPreexisting
        } else {
            isNewerThanBaseline = true
        }

        if isNewerThanBaseline {
            downloadedOrInFlightKeys.insert(key)
            return true
        } else {
            baselineKeys.insert(key)
            return false
        }
    }
}
