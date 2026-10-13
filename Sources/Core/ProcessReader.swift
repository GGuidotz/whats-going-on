// Quali app lavorano di più: tempo di CPU e memoria di ogni processo (proc_pid_rusage), sommati per app. Gli aiutanti
// dentro un bundle (Google Chrome Helper, gli aiutanti di Electron) contano per l'app che li contiene.
// I processi di sistema di root non si leggono senza privilegi: restano fuori, ed è un limite noto.

import Darwin
import Foundation

final class ProcessReader {
    private var previousTime: [pid_t: UInt64] = [:]
    private var names: [pid_t: String] = [:]
    private var lastTime: UInt64 = 0
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(1, info.numer)), UInt64(max(1, info.denom)))
    }()

    func read(limit: Int = 12) -> [ProcessUsage] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBufferPointer {
            Int(proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.stride)))
        }
        guard count > 0 else { return [] }

        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastTime > 0 ? Double(now - lastTime) : 0
        var times: [pid_t: UInt64] = [:]
        var byApp: [String: (cpu: Double, memory: UInt64)] = [:]

        for pid in pids.prefix(count) where pid > 0 {
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard result == 0 else { continue }
            // Su Apple silicon i tempi sono in unità mach, non in nanosecondi.
            let cpuTime = (info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom
            times[pid] = cpuTime

            var cpu = 0.0
            if elapsed > 0, let before = previousTime[pid], cpuTime >= before {
                cpu = Double(cpuTime - before) / elapsed * 100
            }
            let name = names[pid] ?? appName(pid)
            names[pid] = name
            let current = byApp[name] ?? (cpu: 0, memory: 0)
            byApp[name] = (current.cpu + cpu, current.memory + info.ri_phys_footprint)
        }

        previousTime = times
        names = names.filter { times[$0.key] != nil }
        lastTime = now

        let all = byApp.map { ProcessUsage(name: $0.key, cpu: $0.value.cpu, memory: $0.value.memory) }
        let byCPU = all.sorted { $0.cpu > $1.cpu }.prefix(limit)
        let byMemory = all.sorted { $0.memory > $1.memory }.prefix(limit)
        // Le prime per CPU e le prime per memoria, senza doppioni: servono entrambe le classifiche.
        var seen = Set<String>()
        return (Array(byCPU) + Array(byMemory)).filter { seen.insert($0.name).inserted }
    }

    /// Il nome dell'app più esterna che contiene l'eseguibile, altrimenti il nome del processo.
    private func appName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            if let range = path.range(of: ".app/") {
                let bundle = path[..<range.lowerBound]
                if let slash = bundle.lastIndex(of: "/") {
                    return String(bundle[bundle.index(after: slash)...])
                }
            }
            if let last = path.split(separator: "/").last { return String(last) }
        }
        var short = [CChar](repeating: 0, count: 64)
        proc_name(pid, &short, UInt32(short.count))
        let name = String(cString: short)
        return name.isEmpty ? "pid \(pid)" : name
    }
}

/// Quanto pesa What's Going On stessa: CPU (percento di un core, come Monitoraggio Attività) e memoria.
/// Una sola chiamata sul proprio processo: costa quasi nulla.
final class OwnUsageReader {
    private var previous: (cpu: UInt64, at: UInt64)?
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(1, info.numer)), UInt64(max(1, info.denom)))
    }()

    func read() -> ProcessUsage? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0) }
        }
        guard result == 0 else { return nil }
        let cpuTime = (info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom
        let now = DispatchTime.now().uptimeNanoseconds
        defer { previous = (cpuTime, now) }
        guard let previous, now > previous.at, cpuTime >= previous.cpu else { return nil }
        let cpu = Double(cpuTime - previous.cpu) / Double(now - previous.at) * 100
        return ProcessUsage(name: "What's Going On", cpu: cpu, memory: info.ri_phys_footprint)
    }
}
