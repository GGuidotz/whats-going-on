# What's Going On

Cosa succede nel tuo Mac, in una frase. [English](README.en.md)

What's Going On vive nella barra dei menu di macOS e mostra CPU, memoria e rete in poco spazio: per ogni misura una
sigla in colonna, una lettera sotto l'altra, e il valore accanto, colorato dal verde al rosso con il carico. La rete ha due righe, upload
e download, ognuna col suo colore. Aprendo il pannello, in cima c'è una frase che dice la cosa più importante adesso:
"Tutto tranquillo", oppure "Google Chrome usa il 180% della CPU da 4 min". Sotto, una scheda per ogni misura con il
grafico degli ultimi secondi; un clic apre i dettagli.

È un progetto companion di [Cocaine](https://github.com/Mattiakart/cocaine): gli avvisi possono arrivare nella sua
isola. Progetto indipendente, non affiliato a Cocaine. Ispirato a [Stats](https://mac-stats.com).

## Perché è lento?

Il pulsante **Perché è lento?** sotto la frase cerca le cause di adesso con regole fisse e le mette in ordine, ognuna
con i numeri e cosa fare: memoria che non basta (swap che cresce, memoria compressa), un processo che lavora da molto
(anche di macOS e di root), Spotlight che indicizza, disco sotto il 15% con la stima di quando sarà pieno, calore
secondo macOS, app che intercettano la tastiera, elementi di avvio orfani, giorni dall'ultimo riavvio. La stessa
situazione dà sempre la stessa risposta. Con Apple Intelligence accesa (macOS 26), un clic la riscrive in parole
semplici, sul Mac.

## Cosa mostra

| Misura | Dettagli |
|---|---|
| CPU | utente e sistema, processore, carico medio, da quanto è acceso, stato termico di macOS, Spotlight che indicizza, processi che lavorano da molto (anche di sistema), carico di ogni core (modalità avanzata), app più attive |
| Memoria | pressione, app, riservata, compressa e dati che contiene, swap con la variazione degli ultimi 30 minuti e la velocità di scrittura, app che usano più memoria (compressa inclusa) |
| Rete | velocità di download e upload, traffico da quando è aperta, indirizzo locale |
| Temperatura | chip e GPU; tutti i sensori in modalità avanzata |
| GPU | utilizzo e memoria (modalità avanzata) |
| Disco | spazio libero e occupato, quando sarà pieno al ritmo degli ultimi giorni |
| Batteria e consumo | livello, tempo rimasto, salute, capacità, cicli; alimentatore e flusso di energia (quanto entra, quanto va alla batteria); consumo del Mac dove macOS lo espone |
| Cronologia | 24 ore e 7 giorni di CPU, memoria, swap e spazio libero: un punto al minuto, solo numeri, salvati sul Mac e cancellabili da Impostazioni › Generale |

Nella barra dei menu, di predefinito: CPU, RAM e RETE. In Impostazioni › Barra dei menu scegli moduli, ordine e stile
(numeri, o numeri con un piccolo grafico a barre), gli spazi e i colori (scala rosso-verde o tre colori a scelta), con
l'anteprima su barra chiara e scura. Clic destro sulla voce:
impostazioni, novità, feedback, esci.

Su macOS 26 e successivi pannello, schede e pulsanti sono di Liquid Glass, e l'icona è un'icona Liquid Glass a strati
(Icon Composer). Su macOS 14 e 15 gli stessi elementi usano i materiali di sistema.

## Leggera

L'obiettivo è restare sotto l'1% di CPU. A pannello chiuso l'app legge solo ciò che mostri nella barra e ciò che serve
agli avvisi accesi: le temperature, la lettura più pesante, solo dai sensori del chip e di base ogni 30 secondi; l'elenco
delle app ogni 10; tutti i processi, anche quelli di sistema, con `ps` una volta al minuto (circa 35 ms ogni volta). La
cronologia lunga prende un punto al minuto dalle stesse letture. Con la barra nascosta non disegna nulla, a schermi spenti rallenta. Quanto pesa davvero lo vedi in
Impostazioni › Generale. Al primo avvio una guida breve aiuta a scegliere cosa vedere e dove ricevere gli avvisi.

## Attrezzi

Su richiesta, in una finestra loro (⌘T dal pannello, i pulsanti nelle righe Disco, Memoria e CPU, il clic su un avviso):

- **Spazio**: una mappa del disco come [GrandPerspective](https://grandperspective.sourceforge.net), ogni rettangolo
  grande quanto lo spazio che occupa, colorato per tipo (clic su un tipo nella legenda per vedere solo quello), o un
  elenco da ordinare con le caselle per il Cestino. Legge tutto il disco usando tutti i core, o solo una cartella. A
  destra i consigli: cache delle app, cartelle dei progetti riconosciute dal file di progetto (node_modules, target,
  .venv, DerivedData…) con lo strumento e il comando che le rifà, cache degli strumenti da sviluppatore (npm, pip, Cargo, Gradle,
  Homebrew…), installer già usati, backup di iPhone, file grandi non aperti da 6 mesi. Quello che togli va nel Cestino,
  sempre con conferma. Con l'Accesso completo al disco la mappa vede anche Mail, Messaggi, Safari e i backup. In più,
  Cerca su tutto il Mac: i file per nome con Spotlight, anche senza leggere il disco.
- **App**: chi pesa in memoria, chi fa lavorare la CPU, chi consuma energia, chi lavora sul disco e chi usa la rete,
  con Chiudi e Forza chiusura.
- **Avvio**: cosa parte da solo (LaunchAgents dell'utente e di tutti gli utenti, LaunchDaemons), con gli orfani: file
  vuoti, programmi che non ci sono più, app disinstallate. Gli agenti orfani del tuo utente si disattivano o vanno nel
  Cestino, con conferma; quelli in /Library chiedono la password di amministratore e qui si mostrano soltanto.
- **Tastiera**: le app che intercettano i tasti adesso, in modo attivo (ogni tasto aspetta la loro risposta) o solo in
  ascolto, con il ritardo misurato da macOS. Senza permessi.
- **Disinstalla**: le app installate con peso e ultimo uso; per ognuna ciò che ha lasciato nella Libreria (dati, cache,
  preferenze, contenitori, avvio automatico, anche nella cartella del produttore). App e avanzi scelti vanno nel Cestino, con conferma.
- **Mole**: se hai [Mole](https://github.com/tw93/Mole) (`brew install mole`), anteprima e pulizia con `mo clean` e
  manutenzione con `mo optimize`, dentro l'app. Mole è un programma a parte (GPL-3.0): lo chiamiamo, non lo includiamo.
- **Apple Intelligence** (sperimentale): consigli scritti dal modello sul Mac, senza rete.

Gli attrezzi non leggono nulla finché non li apri.

## Avvisi

Con soglie che scegli tu: CPU alta, memoria sotto pressione, swap in crescita, disco quasi pieno (sotto il 15%), chip
caldo, un'app che consuma troppo, un processo fuori controllo (anche di sistema, da oltre 10 minuti). Un avviso scatta
quando la condizione dura abbastanza, una volta sola, e torna solo dopo che il valore è sceso. Elementi di avvio orfani,
giorni di accensione e calore lieve non avvisano: restano nel pannello e nella frase. Chi aggiorna da una versione
precedente trova i tipi nuovi spenti, da accendere in Impostazioni › Avvisi.

Se scegli l'isola di Cocaine, l'avviso va a Cocaine con il suo link `cocaine://alert` e resta nei suoi avvisi recenti.
Cocaine però lo mostra solo quando sei lontano dal Mac da almeno 20 secondi, a meno che in Cocaine sia acceso
**Avvisi AI › Quando › Anche al Mac**, e non lo mostra se gli avvisi sono in pausa o il Lampeggio è spento. In quei casi
What's Going On manda anche una notifica di macOS, così non perdi niente. Impostazioni › Avvisi dice in che caso sei e
ha due prove: subito, e "da lontano" (parte dopo 25 secondi, il tempo di staccare le mani dal Mac).

## Installazione

```sh
brew install --cask gguidotz/tap/whats-going-on
```

Homebrew scarica il DMG dalla release, copia l'app in Applicazioni e toglie la quarantena (l'app non è notarizzata),
quindi niente "Apri comunque". Aggiornare: `brew upgrade --cask whats-going-on`. Disinstallare:
`brew uninstall --cask whats-going-on` (`--zap` cancella anche le preferenze).

Oppure compila dal codice: servono macOS 14+ e gli strumenti a riga di comando (`xcode-select --install`); con Xcode
installato si compila anche l'icona Liquid Glass.

```sh
git clone https://github.com/GGuidotz/whats-going-on.git
cd whats-going-on
./build.sh --install
```

L'app non chiede permessi di privacy: legge solo contatori di sistema. Controlla da sola gli aggiornamenti (ogni 6 ore,
si può spegnere) e in Impostazioni › Aggiornamenti mostra le novità e il comando per aggiornare.

## Feedback

Impostazioni › Feedback (o clic destro sulla voce nella barra › Invia un feedback):

- **Segnala un problema** o **Suggerisci un'idea**: apre una issue su GitHub con versione, macOS e modello del Mac già
  scritti. È il canale preferito; le issue sono pubbliche, quindi niente dati personali.
- **Scrivi un'email**: a giulioguidotz@yahoo.com, con gli stessi dati in fondo.
- **Diagnostica**: un report da copiare o salvare e allegare. Dice versione, Mac, quali letture funzionano, le tue
  scelte e gli ultimi avvisi; niente nomi di app, file o indirizzi.

## Limiti onesti

- Le temperature su Apple silicon passano da funzioni di IOKit non documentate (le stesse usate da Stats). Se un
  aggiornamento di macOS le cambia, la riga Temperatura sparisce invece di mostrare dati sbagliati.
- I processi di root non si leggono con le funzioni del kernel senza privilegi (proc_pid_rusage restituisce -1). Per
  CPU e durata si usa `ps`, che macOS installa con i privilegi per leggerli: dà una media mobile su circa un minuto.
  Memoria, disco ed energia di quei processi restano fuori dall'elenco delle app.
- Spotlight non dice a che punto è l'indicizzazione: si capisce dal lavoro dei suoi processi.
- Il ritardo dei tap della tastiera è quello che riporta macOS; oltre un secondo non si mostra, perché su macOS 27
  compaiono valori così anche per tap mai misurati. Chi ha il permesso Accessibilità o Monitoraggio dell'input senza
  usarlo sta in un database protetto: non si legge.
- L'elenco Elementi login di Impostazioni di Sistema richiede la password di amministratore: la scheda Avvio mostra i
  file LaunchAgents e LaunchDaemons e apre Elementi login con un pulsante.
- Il consumo totale del Mac c'è solo dove l'SMC lo espone; energia per app e flusso dell'alimentatore solo su Apple
  silicon.
- La rete per app viene da `nettop` di macOS, chiamato solo con l'attrezzo App aperto.
- Niente ventole: sui Mac recenti non servono, e controllarle richiederebbe privilegi di amministratore.
- L'app non è notarizzata: niente account Apple Developer. Le versioni pubblicate sono firmate con un'identità locale
  stabile, così macOS ricorda l'Accesso completo al disco tra un aggiornamento e l'altro.
- La mappa non legge `/System` (il volume di sistema sigillato) né gli snapshot di Time Machine: quello spazio compare
  come "Non visibile".

## Struttura

| Cartella | Cosa contiene |
|---|---|
| `Sources/Core` | Il motore: lettori (CPU, memoria, rete, disco, batteria, processi anche di sistema, sensori, GPU, tastiera, avvio), cronologia breve e lunga, frase, "Perché è lento?", avvisi, scala del carico, lettura del disco e consigli degli attrezzi. Solo Foundation, IOKit e CoreGraphics |
| `Sources/Island` | Le viste SwiftUI della pagina "Sistema": le usa il pannello e sono pensate per l'isola di Cocaine |
| `Sources/App` | Avvio AppKit, voce colorata nella barra, pannello, impostazioni, avvisi, aggiornamenti, feedback; in `Tools` gli attrezzi (mappa, app, Mole, Apple Intelligence) |
| `Resources/Icon` | Icona Liquid Glass (`WhatsGoingOn.icon`, Icon Composer) e icona classica di ripiego |
| `Localization` | Italiano (la chiave è il testo) e inglese |
| `tools` | Controllo delle traduzioni, disegno dell'icona, controllo dell'icona compilata |

Pubblicare una versione: aumenta `VERSION`, aggiungi la sezione in `CHANGELOG.md`, poi `./release.sh` (release su
GitHub con il DMG e aggiornamento del cask nel tap).

## Autore

Sviluppato da **gguidotz**: [github.com/GGuidotz/whats-going-on](https://github.com/GGuidotz/whats-going-on) ·
giulioguidotz@yahoo.com. Per segnalazioni e idee, meglio le [issue](https://github.com/GGuidotz/whats-going-on/issues).

## Licenza

MIT. © 2026 GGuidotz.
