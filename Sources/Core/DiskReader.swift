// Spazio sul disco di avvio. Cambia piano: il campionatore lo chiede una volta al minuto.

import Foundation

final class DiskReader {
    func read() -> DiskSample? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        return DiskSample(total: Int64(total), free: values.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}
