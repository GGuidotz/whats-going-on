// Misure su un'icona disegnata: quanta parte si vede e quanto è diversa dall'icona generica delle app. Le usa il
// controllo di build.sh (tools/icon-check), che compila questo file insieme al suo, come in Nod.

import AppKit
import UniformTypeIdentifiers

enum IconMetrics {
    static let side = 256

    /// Disegna l'immagine in una bitmap RGBA quadrata.
    static func render(_ image: NSImage, side: Int = side) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: side * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: side, height: side))
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Frazione dei pixel visibili (alfa oltre il 10%): un'icona Liquid Glass normale sta intorno a 0,6.
    static func coverage(_ rep: NSBitmapImageRep) -> Double {
        guard let data = rep.bitmapData else { return 0 }
        let count = rep.pixelsWide * rep.pixelsHigh
        var visible = 0
        for i in 0..<count where data[i * 4 + 3] > 25 { visible += 1 }
        return Double(visible) / Double(count)
    }

    /// Differenza media tra due bitmap della stessa misura (0 = identiche, 1 = opposte).
    static func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
        guard let x = a.bitmapData, let y = b.bitmapData, a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return 1 }
        let bytes = a.pixelsWide * a.pixelsHigh * 4
        var total = 0
        for i in 0..<bytes { total += abs(Int(x[i]) - Int(y[i])) }
        return Double(total) / Double(bytes * 255)
    }

    /// L'icona generica che macOS mostra quando quella dell'app non si carica.
    static var genericAppIcon: NSImage { NSWorkspace.shared.icon(for: .applicationBundle) }

    /// Vuota: quasi trasparente, oppure uguale all'icona generica.
    static func looksEmpty(coverage: Double, differenceFromGeneric: Double) -> Bool {
        coverage < 0.3 || differenceFromGeneric < 0.03
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}
