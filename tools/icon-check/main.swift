// Controlla che l'icona dell'app si disegni davvero, come la disegnerà il Dock (IconServices), su una copia dell'app in
// un percorso nuovo, così la cache delle icone non conta. Lo esegue build.sh:
//   swiftc tools/icon-check/main.swift tools/icon-check/IconMetrics.swift -o build/icon-check
//   build/icon-check "build/What's Going On.app" build/icon-out build
// Scrive build/icon-preview.png (e build/icon-actool.png dall'.icns generato da actool), stampa una riga di misure.
// Uscita: 0 icona a posto, 1 icona vuota (build.sh passa alla classica), 2 controllo non riuscito.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("uso: icon-check <What's Going On.app> <cartella di actool> <cartella per le anteprime>")
    exit(2)
}
let app = URL(fileURLWithPath: arguments[1])
let actoolOut = URL(fileURLWithPath: arguments[2])
let previews = URL(fileURLWithPath: arguments[3])
let fm = FileManager.default

func savePNG(_ rep: NSBitmapImageRep, _ name: String) {
    try? rep.representation(using: .png, properties: [:])?.write(to: previews.appendingPathComponent(name))
}

let scratch = fm.temporaryDirectory.appendingPathComponent("wgo-icon-check-\(UUID().uuidString)", isDirectory: true)
let copy = scratch.appendingPathComponent("What's Going On.app")
do {
    try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
    try fm.copyItem(at: app, to: copy)
} catch {
    print("copia non riuscita: \(error.localizedDescription)")
    exit(2)
}

let icon = NSWorkspace.shared.icon(forFile: copy.path)
guard let rep = IconMetrics.render(icon), let generic = IconMetrics.render(IconMetrics.genericAppIcon) else {
    try? fm.removeItem(at: scratch)
    print("disegno non riuscito")
    exit(2)
}
try? fm.removeItem(at: scratch)
savePNG(rep, "icon-preview.png")

let coverage = IconMetrics.coverage(rep)
let difference = IconMetrics.difference(rep, generic)
var note = "copertura \(IconMetrics.percent(coverage)), diversa dall'icona generica \(IconMetrics.percent(difference))"

// L'.icns che actool ricava da WhatsGoingOn.icon per i macOS precedenti: se è vuoto anche lui, il problema è nel file .icon.
if let icns = (try? fm.contentsOfDirectory(at: actoolOut, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension == "icns" }),
   let image = NSImage(contentsOf: icns), let flat = IconMetrics.render(image) {
    savePNG(flat, "icon-actool.png")
    note += ", icns di actool \(IconMetrics.percent(IconMetrics.coverage(flat)))"
}

let empty = IconMetrics.looksEmpty(coverage: coverage, differenceFromGeneric: difference)
print(note)
exit(empty ? 1 : 0)
