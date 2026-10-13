# What's Going On

App macOS per la barra dei menu (Swift/SwiftUI, macOS 14+), companion di Cocaine. Stesso schema di GGuidotz/nod.

- Compilazione: `./build.sh` (swiftc diretto, niente progetto Xcode, firma ad hoc). Nel cloud Swift non compila:
  ogni modifica la prova Giulio sul Mac con `./build.sh --install`. Rileggi il codice con cura prima di consegnare.
- `Sources/Core` non importa SwiftUI né AppKit: deve poter entrare in Cocaine come pagina dell'isola.
- Testi: chiave = frase italiana, `L("…")`; ogni chiave nuova va in `Localization/en.lproj/Localizable.strings`.
  Controllo: `python3 -I tools/check-strings.py`.
- Versione: `VERSION` + sezione `## <versione> · <data>` in cima a `CHANGELOG.md` (build.sh la richiede).
- Design: Human Interface Guidelines di Apple; colore mai come unico segnale, cifre tabellari, colori semantici.
- Interfaccia e messaggi in italiano, niente emoji.
- Nel cloud c'è almeno un controllo di sintassi: `pip install tree-sitter tree-sitter-swift`, poi un parser che segnala
  i nodi ERROR (SensorReader.swift ne dà uno falso per `@_silgen_name`). Non sostituisce la compilazione.
- Avvio AppKit (`Sources/App/Main.swift`), non `App` di SwiftUI: la voce nella barra è un NSStatusItem perché
  MenuBarExtra disegna l'etichetta come immagine modello, a un colore. Le impostazioni sono una finestra nostra.
- Liquid Glass solo sui controlli che galleggiano (barra delle schede, pulsanti del pannello), sempre dietro
  `if #available(macOS 26, *)`; il contenuto usa riempimenti standard (`Sources/Island/Style.swift`).
- Icona: `Resources/Icon/WhatsGoingOn.icon` (strati da `python3 -I tools/render-icon.py --layers …`), compilata da
  actool in build.sh e controllata da `tools/icon-check`; `AppIcon-1024.png` è il ripiego classico.
- Avvisi a Cocaine: `cocaine://alert` li mostra solo se sei via da 20 s o con "Anche al Mac" (`alertWhenPresent`),
  non in pausa e con `alertFlash`; le preferenze di Cocaine si leggono dal dominio `local.cocaine.toggle`.
