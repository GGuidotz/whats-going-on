// Carico della CPU dai contatori del kernel (host_processor_info): la differenza tra due letture, per core.

import Darwin

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
