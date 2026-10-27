import Foundation
import UIKit

/// Result copies remain on this device and expire after five minutes.
enum SecureClipboard {
    static func copy(_ value: String) {
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": value]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)]
        )
    }
}

/// Run only at launch so that a share sheet cannot lose a file mid-transfer.
enum TemporaryExportCleanup {
    static func removeOldExports(
        now: Date = Date(),
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        let base = baseDirectory ?? fileManager.temporaryDirectory
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        let ownedDirectories = ["PhaseXpertExports", "PhaseXpertPhaseDiagrams"]
        for name in ownedDirectories {
            let directory = base.appendingPathComponent(name, isDirectory: true)
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: resourceKeys
            ) else { continue }
            for item in contents where isOld(item, cutoff: cutoff) {
                try? fileManager.removeItem(at: item)
            }
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: base, includingPropertiesForKeys: resourceKeys
        ) else { return }
        for item in contents {
            let name = item.lastPathComponent
            let owned = name.hasPrefix("PhaseXpert-MultiSweep-")
                || name.hasPrefix("PhaseXpert-Sweep-")
                || name == "PhaseXpert-Case-Comparison.csv"
                || name == "PhaseXpert-Case-Comparison.pdf"
            if owned && isOld(item, cutoff: cutoff) {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    private static func isOld(_ url: URL, cutoff: Date) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate else { return false }
        return modified < cutoff
    }
}
