// Spazio sul disco di avvio e letture/scritture di tutti i dischi (statistiche di IOBlockStorageDriver).

import Foundation
import IOKit

final class DiskReader {
    private var lastCapacity: (total: Int64, free: Int64)?
    private var previous: (read: UInt64, write: UInt64)?
    private var lastTime: UInt64 = 0

    /// `refreshCapacity`: lo spazio libero cambia piano e leggerlo costa; il campionatore lo chiede ogni tanto.
    func read(refreshCapacity: Bool) -> DiskSample? {
        if refreshCapacity || lastCapacity == nil {
            let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
            if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
               let total = values.volumeTotalCapacity {
                lastCapacity = (Int64(total), values.volumeAvailableCapacityForImportantUsage ?? 0)
            }
        }
        guard let capacity = lastCapacity else { return nil }

        let now = DispatchTime.now().uptimeNanoseconds
        let counters = ioCounters()
        var readRate = 0.0, writeRate = 0.0
        if let counters, let previous, lastTime > 0 {
            let seconds = Double(now - lastTime) / 1e9
            if seconds > 0.05 {
                readRate = Double(counters.read &- previous.read) / seconds
                writeRate = Double(counters.write &- previous.write) / seconds
                // Un disco staccato fa scendere i totali: meglio zero che un picco assurdo.
                if counters.read < previous.read { readRate = 0 }
                if counters.write < previous.write { writeRate = 0 }
            }
        }
        previous = counters
        lastTime = now
        return DiskSample(total: capacity.total, free: capacity.free, readRate: readRate, writeRate: writeRate)
    }

    private func ioCounters() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0, write: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return (read, write)
    }
}
