// Accesso completo al disco: senza, la mappa non vede Mail, Messaggi, Safari, i backup e qualche cartella di sistema.
// Non c'è una richiesta da mostrare (macOS non la prevede per questo permesso): si prova ad aprire cartelle che lo
// richiedono e, se serve, si apre il pannello giusto delle Impostazioni di Sistema.
// Il permesso resta da un aggiornamento all'altro solo se l'app è firmata sempre con la stessa identità (build.sh).

import AppKit

enum FullDiskAccess {
    static var granted: Bool {
        let home = NSHomeDirectory()
        let probes = ["/Library/Application Support/com.apple.TCC", home + "/Library/Safari", home + "/Library/Mail",
                      home + "/Library/Messages"]
        for path in probes {
            if let dir = opendir(path) {
                closedir(dir)
                return true
            }
        }
        return false
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
