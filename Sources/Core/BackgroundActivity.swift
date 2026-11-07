// Chi lavora da molto, anche tra i processi di sistema: un servizio di macOS bloccato al 95% non compare tra le app.
//
// Perché /bin/ps. Per i processi di root e degli utenti di sistema (_spotlight, _coreaudiod) proc_pid_rusage
// restituisce -1, e falliscono anche proc_pidinfo(PROC_PIDTASKINFO) e kinfo_proc.p_pctcpu (sempre 0): provato su
// macOS 27.2. /bin/ps è setuid root e li legge tutti. Costa circa 35 ms di CPU a lettura (misurati, ps compreso), per
// questo si chiama una volta al minuto a pannello chiuso (circa lo 0,06% di un core) e ogni 10 s a pannello aperto.
// La %CPU di ps è una media mobile del kernel, che si smorza in circa un minuto: va bene per dire "da quanto", non
// per i picchi di un secondo (quelli li dà ProcessReader).
// Spotlight: mdutil dice solo se l'indicizzazione è attiva, non se sta lavorando; lo si capisce dal lavoro dei suoi
// processi (mds_stores, mdworker), che sono proprio tra quelli di sistema.

import Darwin
import Foundation

/// Un processo qualunque, anche di root, come lo vede ps.
struct SystemProcess: Equatable {
    var pid: Int32
    var uid: UInt32
    /// Percento di un core, media mobile del kernel.
    var cpu: Double
    var path: String

    var name: String { path.split(separator: "/").last.map(String.init) ?? path }

    /// Un processo di macOS, non un'app installata o un suo servizio.
    var isMacOS: Bool { SystemProcess.isMacOS(path: path) }

    /// /usr/local e Homebrew stanno sotto /usr o /opt ma non sono di macOS.
    static func isMacOS(path: String) -> Bool {
        if path.hasPrefix("/usr/local/") { return false }
        return ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    /// L'app (fuori da /System) che contiene l'eseguibile: "Google Chrome" per i suoi aiutanti. nil per i servizi.
    var appName: String? {
        guard !isMacOS, let range = path.range(of: ".app/") else { return nil }
        let bundle = path[..<range.lowerBound]
        return bundle.split(separator: "/").last.map(String.init)
    }
}

enum SystemProcessReader {
    /// I processi che lavorano almeno un po' (≥ 1% di un core). nil se ps non risponde.
    static func read() -> [SystemProcess]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,uid=,pcpu=,comm="]
        // Con una lingua italiana ps scriverebbe "12,5": serve il punto.
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    static func parse(_ text: String) -> [SystemProcess] {
        let me = getpid()
        var out: [SystemProcess] = []
        for line in text.split(separator: "\n") {
            // pid uid %cpu percorso (il percorso può contenere spazi: è tutto il resto della riga)
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int32(fields[0]), let uid = UInt32(fields[1]),
                  let cpu = Double(fields[2]), cpu >= 1, pid > 0, pid != me else { continue }
            let path = String(fields[3]).trimmingCharacters(in: .whitespaces)
            if path == "/bin/ps" || path == "ps" { continue }
            out.append(SystemProcess(pid: pid, uid: uid, cpu: cpu, path: path))
        }
        return out
    }
}

/// Un processo che lavora molto da un po'.
struct RunawayProcess: Equatable, Identifiable {
    var pid: Int32
    var name: String
    var cpu: Double
    var since: Date
    var isMacOS: Bool
    /// L'app che lo contiene, se è un suo aiutante.
    var appName: String?
    var id: Int32 { pid }

    func minutes(at now: Date) -> Int { max(0, Int(now.timeIntervalSince(since) / 60)) }

    /// Che cosa è, in parole, per chi non conosce il nome: "un processo di macOS", "un servizio in background".
    var kind: String {
        if isMacOS { return L("un processo di macOS") }
        if appName != nil { return L("un aiutante di un'app") }
        return L("un servizio in background")
    }
}

/// Spotlight al lavoro: quanto e da quando.
struct SpotlightActivity: Equatable {
    /// Percento di un core, sommato tra i processi di Spotlight.
    var cpu: Double
    var since: Date

    func minutes(at now: Date) -> Int { max(0, Int(now.timeIntervalSince(since) / 60)) }
}

/// Tiene "da quando" per ogni PID (non per nome: un solo aiutante impazzito non si confonde con gli altri).
struct BackgroundActivityTracker {
    /// Da qui un processo "lavora molto" e si comincia a contare.
    static let threshold = 50.0
    /// Spotlight lavora se i suoi processi insieme superano questo valore.
    static let spotlightThreshold = 15.0
    static let spotlightNames: Set<String> = ["mds", "mds_stores", "mdworker", "mdworker_shared", "mdsync",
                                              "corespotlightd", "mdbulkimport"]

    private var hot: [Int32: (name: String, since: Date)] = [:]
    private var spotlightSince: Date?

    mutating func update(_ list: [SystemProcess], now: Date) -> (runaways: [RunawayProcess], spotlight: SpotlightActivity?) {
        var runaways: [RunawayProcess] = []
        var next: [Int32: (name: String, since: Date)] = [:]
        for p in list where p.name != "kernel_task" {
            // Isteresi: chi era già sopra resta finché non scende sotto i tre quarti della soglia.
            let previous = hot[p.pid].flatMap { $0.name == p.name ? $0 : nil }
            guard p.cpu >= Self.threshold || (previous != nil && p.cpu >= Self.threshold * 0.75) else { continue }
            let since = previous?.since ?? now
            next[p.pid] = (p.name, since)
            runaways.append(RunawayProcess(pid: p.pid, name: p.name, cpu: p.cpu, since: since, isMacOS: p.isMacOS,
                                           appName: p.appName))
        }
        hot = next

        let spotlightCPU = list.filter { Self.spotlightNames.contains($0.name) }.reduce(0) { $0 + $1.cpu }
        var spotlight: SpotlightActivity?
        if spotlightCPU >= Self.spotlightThreshold || (spotlightSince != nil && spotlightCPU >= Self.spotlightThreshold / 2) {
            let since = spotlightSince ?? now
            spotlightSince = since
            spotlight = SpotlightActivity(cpu: spotlightCPU, since: since)
        } else {
            spotlightSince = nil
        }
        return (runaways.sorted { $0.cpu > $1.cpu }, spotlight)
    }
}

/// Lo stato termico secondo macOS: dice quando il sistema sta davvero limitando le prestazioni, anche senza sensori.
enum ThermalLevel: Int, Equatable, Comparable {
    case nominal, fair, serious, critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    static var current: ThermalLevel { ThermalLevel(ProcessInfo.processInfo.thermalState) }

    static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .nominal: L("Normale")
        case .fair: L("Tiepido")
        case .serious: L("Caldo: prestazioni ridotte")
        case .critical: L("Molto caldo: prestazioni molto ridotte")
        }
    }
}

enum BootTime {
    /// Quando si è acceso il Mac: non cambia, si legge una volta.
    static let date: Date? = {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(boot.tv_sec))
    }()

    static func uptime(at now: Date) -> TimeInterval? { date.map { max(0, now.timeIntervalSince($0)) } }
}
