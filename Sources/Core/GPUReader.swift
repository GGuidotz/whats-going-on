// Utilizzo della GPU dalle statistiche di IOAccelerator (pubbliche nel registro IOKit, nessun permesso).

import Foundation
import IOKit

final class GPUReader {
    func read() -> GPUSample? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: GPUSample?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let utilization = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
                let memory = (stats["In use system memory"] as? NSNumber)?.uint64Value
                let sample = GPUSample(utilization: min(1, utilization / 100), memoryUsed: memory)
                // Con più GPU (Intel con scheda dedicata) mostriamo la più impegnata.
                if sample.utilization >= (best?.utilization ?? -1) { best = sample }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return best
    }
}
