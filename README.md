# What's Going On

Cosa succede nel tuo Mac, in una frase. [English](README.en.md)

What's Going On vive nella barra dei menu di macOS e mostra CPU, memoria e rete in poco spazio: per ogni misura una
sigla in colonna, una lettera sotto l'altra, e il valore accanto, colorato dal verde al rosso con il carico. La rete ha due righe, upload
e download, ognuna col suo colore. Aprendo il pannello, in cima c'è una frase che dice la cosa più importante adesso:
"Tutto tranquillo", oppure "Google Chrome usa il 180% della CPU da 4 min". Sotto, una scheda per ogni misura con il
grafico degli ultimi secondi; un clic apre i dettagli.

È un progetto companion di [Cocaine](https://github.com/Mattiakart/cocaine): gli avvisi possono arrivare nella sua
isola. Progetto indipendente, non affiliato a Cocaine. Ispirato a [Stats](https://mac-stats.com).

## Cosa mostra

| Misura | Dettagli |
|---|---|
| CPU | utente e sistema, carico di ogni core (modalità avanzata), app più attive |
| Memoria | pressione, app, riservata, compressa, swap, app che usano più memoria |
| Rete | velocità di download e upload, traffico da quando è aperta, indirizzo locale |
| Temperatura | chip e GPU; tutti i sensori in modalità avanzata |
| GPU | utilizzo e memoria (modalità avanzata) |
| Disco | spazio libero, letture e scritture |
| Batteria e consumo | livello, tempo rimasto, salute, cicli, watt; consumo del Mac dove macOS lo espone |

Nella barra dei menu, di predefinito: CPU, RAM e RETE. In Impostazioni › Barra dei menu scegli moduli, ordine e stile
(numeri, o numeri con un piccolo grafico a barre), con l'anteprima su barra chiara e scura. Clic destro sulla voce:
impostazioni, novità, feedback, esci.

Su macOS 26 e successivi pannello, schede e pulsanti sono di Liquid Glass, e l'icona è un'icona Liquid Glass a strati
(Icon Composer). Su macOS 14 e 15 gli stessi elementi usano i materiali di sistema.

## Avvisi

Con soglie che scegli tu: CPU alta, memoria sotto pressione, disco quasi pieno, chip caldo, un'app che consuma troppo.
Un avviso scatta quando la condizione dura abbastanza, una volta sola, e torna solo dopo che il valore è sceso.

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
- I processi di sistema che girano come root non si leggono senza privilegi: nell'elenco delle app non compaiono.
- Il consumo totale del Mac c'è solo dove l'SMC lo espone.
- Niente ventole: sui Mac recenti non servono, e controllarle richiederebbe privilegi di amministratore.
- L'app è firmata ad hoc e non notarizzata: niente account Apple Developer.

## Struttura

| Cartella | Cosa contiene |
|---|---|
| `Sources/Core` | Il motore: lettori (CPU, memoria, rete, disco, batteria, processi, sensori, GPU), cronologia, frase, avvisi, scala del carico. Solo Foundation e IOKit |
| `Sources/Island` | Le viste SwiftUI della pagina "Sistema": le usa il pannello e sono pensate per l'isola di Cocaine |
| `Sources/App` | Avvio AppKit, voce colorata nella barra, pannello, impostazioni, avvisi, aggiornamenti, feedback |
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
