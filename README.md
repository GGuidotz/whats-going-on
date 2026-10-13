# What's Going On

Cosa succede nel tuo Mac, in una frase.

What's Going On vive nella barra dei menu di macOS e mostra CPU, memoria e rete. Aprendo il pannello, in cima c'è una
frase che dice la cosa più importante adesso: "Tutto tranquillo", oppure "Google Chrome usa il 180% della CPU da 4 min".
Sotto, una riga per ogni misura con il grafico degli ultimi secondi; un clic apre i dettagli.

È un progetto companion di [Cocaine](https://github.com/Mattiakart/cocaine): se Cocaine è aperto, gli avvisi arrivano
nella sua isola. Progetto indipendente, non affiliato a Cocaine. Ispirato a [Stats](https://mac-stats.com).

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

Nella barra dei menu, di predefinito: CPU, memoria e velocità della rete. In Impostazioni scegli moduli, ordine e stile
(numeri o piccoli grafici).

## Avvisi

Con soglie che scegli tu: CPU alta, memoria sotto pressione, disco quasi pieno, chip caldo, un'app che consuma troppo.
Un avviso scatta quando la condizione dura abbastanza, una volta sola, e torna solo dopo che il valore è sceso.
Arrivano nell'isola di Cocaine (`cocaine://alert`) se Cocaine è aperto, altrimenti come notifiche di macOS.

## Installazione

```sh
brew install --cask gguidotz/tap/whats-going-on
```

Oppure compila dal codice: servono macOS 14+ e gli strumenti a riga di comando (`xcode-select --install`).

```sh
git clone https://github.com/GGuidotz/whats-going-on.git
cd whats-going-on
./build.sh --install
```

L'app non chiede permessi di privacy: legge solo contatori di sistema.

## Limiti onesti

- Le temperature su Apple silicon passano da funzioni di IOKit non documentate (le stesse usate da Stats). Se un
  aggiornamento di macOS le cambia, la riga Temperatura sparisce invece di mostrare dati sbagliati.
- I processi di sistema che girano come root non si leggono senza privilegi: nell'elenco delle app non compaiono.
- Il consumo totale del Mac c'è solo dove l'SMC lo espone.
- Niente ventole: sui Mac recenti non servono, e controllarle richiederebbe privilegi di amministratore.

## Struttura

| Cartella | Cosa contiene |
|---|---|
| `Sources/Core` | Il motore: lettori (CPU, memoria, rete, disco, batteria, processi, sensori, GPU), cronologia, frase, avvisi. Solo Foundation e IOKit |
| `Sources/Island` | Le viste SwiftUI della pagina "Sistema": le usa il pannello e sono pensate per l'isola di Cocaine |
| `Sources/App` | Barra dei menu, pannello, impostazioni, consegna degli avvisi |
| `Localization` | Italiano (la chiave è il testo) e inglese |
| `tools` | Controllo delle traduzioni, disegno dell'icona |

Pubblicare una versione: aumenta `VERSION`, aggiungi la sezione in `CHANGELOG.md`, poi `./release.sh`.

## Licenza

MIT. © 2026 GGuidotz.
