// Carico della CPU dai contatori del kernel (host_processor_info): la differenza tra due letture, per core.

import Darwin
import Foundation

final class CPUReader {
    private struct Ticks {
        var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    }

    private var previous: [Ticks] = []

    func read() -> CPUSample? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let current: [Ticks] = (0..<Int(count)).map { i in
            let base = i * Int(CPU_STATE_MAX)
            return Ticks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                         system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                         idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                         nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
        defer { previous = current }
        guard previous.count == current.count else { return nil }   // prima lettura: serve una differenza

        var perCore: [Double] = []
        var user = 0.0, system = 0.0, busy = 0.0, all = 0.0
        for (now, before) in zip(current, previous) {
            let u = Double(now.user &- before.user) + Double(now.nice &- before.nice)
            let s = Double(now.system &- before.system)
            let i = Double(now.idle &- before.idle)
            let total = u + s + i
            perCore.append(total > 0 ? (u + s) / total : 0)
            user += u; system += s; busy += u + s; all += total
        }
        guard all > 0 else { return nil }
        return CPUSample(total: busy / all, user: user / all, system: system / all, perCore: perCore)
    }
}

/// Carico medio e da quanto è acceso il Mac: due chiamate al kernel, solo a pannello aperto.
enum LoadReader {
    static func read() -> LoadSample? {
        var averages = [Double](repeating: 0, count: 3)
        guard getloadavg(&averages, 3) == 3 else { return nil }
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        var uptime: TimeInterval = 0
        if sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 {
            uptime = max(0, Date().timeIntervalSince1970 - Double(boot.tv_sec))
        }
        return LoadSample(one: averages[0], five: averages[1], fifteen: averages[2], uptime: uptime)
    }

    /// "Apple M2", "Intel(R) Core(TM) i7…": il nome del processore, letto una volta.
    static let processorName: String? = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return nil }
        let name = String(cString: buffer).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }()
}
