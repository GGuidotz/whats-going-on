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
