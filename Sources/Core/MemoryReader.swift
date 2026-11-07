// Memoria come la conta Monitoraggio Attività: usata = memoria delle app + wired + compressa.

import Darwin
import Foundation

final class MemoryReader {
    private let total = ProcessInfo.processInfo.physicalMemory
    /// Pagine scritte e lette dallo swap finora (dal kernel), per la velocità tra due letture.
    private var previousSwap: (outs: UInt64, ins: UInt64, at: UInt64)?

    func read() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let cached = (UInt64(stats.external_page_count) + purgeable) * page
        // Quanto la memoria compressa rappresenta: pagine originali dentro il compressore.
        let uncompressed = UInt64(stats.total_uncompressed_pages_in_compressor) * page

        // Velocità dello swap: è il segnale che il Mac sta rallentando adesso, non solo che è pieno.
        let now = DispatchTime.now().uptimeNanoseconds
        var swapOut: Double?, swapIn: Double?
        if let p = previousSwap, now > p.at, stats.swapouts >= p.outs, stats.swapins >= p.ins {
            let seconds = Double(now - p.at) / 1e9
            swapOut = Double((stats.swapouts - p.outs) * page) / seconds
            swapIn = Double((stats.swapins - p.ins) * page) / seconds
        }
        previousSwap = (stats.swapouts, stats.swapins, now)

        return MemorySample(total: total,
                            used: min(total, app + wired + compressed),
                            app: app, wired: wired, compressed: compressed, cached: cached,
                            swapUsed: swapUsed(),
                            pressure: pressure(),
                            uncompressed: uncompressed, swapOutRate: swapOut, swapInRate: swapIn)
    }

    private func pressure() -> MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }

    private func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }
}
