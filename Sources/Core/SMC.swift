// Lettura del System Management Controller (AppleSMC), in sola lettura: consumo totale del Mac (PSTR) e, sui Mac
// Intel, la temperatura della CPU. Struttura e comandi sono quelli usati da anni dagli strumenti open source
// (Stats, smcFanControl): la memoria va disposta esattamente come in C, 80 byte. Se non torna, l'SMC resta spento.

import Foundation
import IOKit

final class SMC {
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimitData { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo {
        var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0
        // In C la struttura occupa 12 byte: senza questi tre il campo dopo finirebbe al posto sbagliato.
        var pad0: UInt8 = 0, pad1: UInt8 = 0, pad2: UInt8 = 0
    }
    private typealias Bytes32 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct Param {
        var key: UInt32 = 0
        var version = Version()
        var pLimit = PLimitData()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                              0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let handleYPCEvent: UInt32 = 2
    private static let readKey: UInt8 = 5
    private static let getKeyInfo: UInt8 = 9

    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: KeyInfo] = [:]

    init?() {
        guard MemoryLayout<Param>.size == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Il valore numerico di una chiave di quattro lettere ("PSTR", "TC0P"), nei tipi che usiamo.
    func value(_ key: String) -> Double? {
        guard let code = Self.fourCC(key) else { return nil }
        let info: KeyInfo
        if let cached = infoCache[code] {
            info = cached
        } else {
            var input = Param()
            input.key = code
            input.data8 = Self.getKeyInfo
            guard let output = call(&input) else { return nil }
            info = output.keyInfo
            infoCache[code] = info
        }
        guard info.dataSize > 0, info.dataSize <= 32 else { return nil }

        var input = Param()
        input.key = code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Self.readKey
        guard let output = call(&input) else { return nil }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return Self.decode(bytes, type: Self.string(info.dataType))
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var outputSize = MemoryLayout<Param>.stride
        let kr = IOConnectCallStructMethod(connection, Self.handleYPCEvent, &input, MemoryLayout<Param>.stride,
                                           &output, &outputSize)
        guard kr == KERN_SUCCESS, output.result == 0 else { return nil }
        return output
    }

    private static func decode(_ b: [UInt8], type: String) -> Double? {
        switch type {
        case "flt " where b.count >= 4:
            // Apple silicon: Float little-endian.
            let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            return Double(Float(bitPattern: bits))
        case "sp78" where b.count >= 2:
            // Intel: virgola fissa con segno, big-endian, 8 bit di parte frazionaria.
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case "fpe2" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case "ui8 " where b.count >= 1:
            return Double(b[0])
        case "ui16" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32" where b.count >= 4:
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default:
            return nil
        }
    }

    private static func fourCC(_ s: String) -> UInt32? {
        let scalars = Array(s.utf8)
        guard scalars.count == 4 else { return nil }
        return scalars.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func string(_ code: UInt32) -> String {
        let bytes = [UInt8(code >> 24 & 0xff), UInt8(code >> 16 & 0xff), UInt8(code >> 8 & 0xff), UInt8(code & 0xff)]
        return String(decoding: bytes, as: UTF8.self)
    }
}
