// Quali app lavorano di più: tempo di CPU e memoria di ogni processo (proc_pid_rusage), sommati per app; con l'attrezzo
// App aperto anche disco, energia e rete. Gli aiutanti dentro un bundle (Google Chrome Helper, gli aiutanti di
// Electron) contano per l'app che li contiene.
// I processi di sistema di root non si leggono senza privilegi: restano fuori, ed è un limite noto.

import Darwin
import Foundation

final class ProcessReader {
    private struct Counters {
        var cpu: UInt64
        var diskRead: UInt64
        var diskWrite: UInt64
        var energy: UInt64
    }

    private var previous: [pid_t: Counters] = [:]
    private var names: [pid_t: (name: String, bundle: String?)] = [:]
    private var lastTime: UInt64 = 0
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(1, info.numer)), UInt64(max(1, info.denom)))
    }()

    /// - detailed: l'attrezzo App è aperto. Oltre a CPU e memoria, disco ed energia di ogni app (dagli stessi
    ///   contatori, nessuna chiamata in più) e la rete, se `network` porta le velocità per processo; nell'elenco
    ///   entrano anche le prime per energia, disco e rete.
    func read(limit: Int = 12, detailed: Bool = false,
              network: [pid_t: (down: Double, up: Double)]? = nil) -> [ProcessUsage] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBufferPointer {
            Int(proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.stride)))
        }
        guard count > 0 else { return [] }

        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = lastTime > 0 ? Double(now - lastTime) : 0
        var counters: [pid_t: Counters] = [:]
        var byApp: [String: ProcessUsage] = [:]

        for pid in pids.prefix(count) where pid > 0 {
            // V6 porta anche l'energia (nanojoule); i campi di V2 sono gli stessi, nello stesso posto.
            var info = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            guard result == 0 else { continue }
            // Su Apple silicon i tempi sono in unità mach, non in nanosecondi.
            let c = Counters(cpu: (info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom,
                             diskRead: info.ri_diskio_bytesread, diskWrite: info.ri_diskio_byteswritten,
                             energy: info.ri_energy_nj)
            counters[pid] = c

            var cpu = 0.0
            let before = previous[pid]
            if elapsed > 0, let before, c.cpu >= before.cpu {
                cpu = Double(c.cpu - before.cpu) / elapsed * 100
            }
            let app = names[pid] ?? appName(pid)
            names[pid] = app
            var usage = byApp[app.name] ?? ProcessUsage(name: app.name, cpu: 0, memory: 0, bundlePath: app.bundle)
            usage.cpu += cpu
            usage.memory += info.ri_phys_footprint
            if usage.bundlePath == nil { usage.bundlePath = app.bundle }
            if detailed {
                // Al secondo: differenza tra due letture. Un processo appena nato conta da zero.
                func rate(_ a: UInt64, _ b: UInt64?) -> Double {
                    guard elapsed > 0, let b, a >= b else { return 0 }
                    return Double(a - b) / elapsed * 1e9
                }
                usage.diskRead = (usage.diskRead ?? 0) + rate(c.diskRead, before?.diskRead)
                usage.diskWrite = (usage.diskWrite ?? 0) + rate(c.diskWrite, before?.diskWrite)
                // nanojoule per nanosecondo = watt
                var watts = 0.0
                if elapsed > 0, let before, c.energy >= before.energy { watts = Double(c.energy - before.energy) / elapsed }
                usage.energy = (usage.energy ?? 0) + watts
                if let network {
                    let n = network[pid]
                    usage.netIn = (usage.netIn ?? 0) + (n?.down ?? 0)
                    usage.netOut = (usage.netOut ?? 0) + (n?.up ?? 0)
                }
            }
            byApp[app.name] = usage
        }

        previous = counters
        names = names.filter { counters[$0.key] != nil }
        lastTime = now

        let all = Array(byApp.values)
        var lists = [all.sorted { $0.cpu > $1.cpu }.prefix(limit), all.sorted { $0.memory > $1.memory }.prefix(limit)]
        if detailed {
            lists.append(all.sorted { ($0.energy ?? 0) > ($1.energy ?? 0) }.prefix(limit))
            lists.append(all.sorted { $0.disk > $1.disk }.prefix(limit))
            if network != nil { lists.append(all.sorted { $0.net > $1.net }.prefix(limit)) }
        }
        // Le prime di ogni classifica, senza doppioni: servono tutte.
        var seen = Set<String>()
        return lists.flatMap { Array($0) }.filter { seen.insert($0.name).inserted }
    }

    /// Il nome dell'app più esterna che contiene l'eseguibile (con il percorso dell'app, per chiuderla), altrimenti il
    /// nome del processo.
    private func appName(_ pid: pid_t) -> (name: String, bundle: String?) {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            if let range = path.range(of: ".app/") {
                let bundle = path[..<range.lowerBound]
                if let slash = bundle.lastIndex(of: "/") {
                    return (String(bundle[bundle.index(after: slash)...]), String(bundle) + ".app")
                }
            }
            if let last = path.split(separator: "/").last { return (String(last), nil) }
        }
        var short = [CChar](repeating: 0, count: 64)
        proc_name(pid, &short, UInt32(short.count))
        let name = String(cString: short)
        return (name.isEmpty ? "pid \(pid)" : name, nil)
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
