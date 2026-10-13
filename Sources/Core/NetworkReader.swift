// Traffico di rete dai contatori delle interfacce (getifaddrs). Contano solo le interfacce fisiche (en*, pdp_ip*):
// le VPN (utun*) ripeterebbero lo stesso traffico due volte.

import Darwin
import Foundation

final class NetworkReader {
    private var previous: [String: (input: UInt32, output: UInt32)] = [:]
    private var lastTime: UInt64 = 0
    private var sessionIn: UInt64 = 0
    private var sessionOut: UInt64 = 0

    /// `withAddress`: legge anche l'indirizzo IP locale (solo il pannello lo mostra).
    func read(withAddress: Bool) -> NetworkSample? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }

        var counters: [String: (input: UInt32, output: UInt32)] = [:]
        var ip: String?
        var ipInterface: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let addr = entry.pointee.ifa_addr else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }

            switch Int32(addr.pointee.sa_family) {
            case AF_LINK:
                if let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                    counters[name] = (data.ifi_ibytes, data.ifi_obytes)
                }
            case AF_INET where withAddress && ip == nil:
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let text = String(cString: host)
                    if !text.hasPrefix("169.254.") { ip = text; ipInterface = name }
                }
            default:
                break
            }
        }

        let now = DispatchTime.now().uptimeNanoseconds
        defer { previous = counters; lastTime = now }
        guard lastTime > 0 else { return nil }
        let seconds = Double(now - lastTime) / 1e9
        guard seconds > 0.05 else { return nil }

        var inBytes: UInt64 = 0, outBytes: UInt64 = 0
        for (name, value) in counters {
            guard let before = previous[name] else { continue }
            // I contatori sono a 32 bit: la sottrazione con &- regge il giro dopo 4 GB.
            inBytes += UInt64(value.input &- before.input)
            outBytes += UInt64(value.output &- before.output)
        }
        sessionIn += inBytes
        sessionOut += outBytes
        return NetworkSample(download: Double(inBytes) / seconds, upload: Double(outBytes) / seconds,
                             sessionIn: sessionIn, sessionOut: sessionOut, localIP: ip, interface: ipInterface)
    }
}
