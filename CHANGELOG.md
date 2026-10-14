# Novità

Formato: `## <versione> · <data>`, poi `### Novità`, `### Miglioramenti`, `### Correzioni`, una riga `- ` per
cambiamento. L'app mostra la sezione della sua versione in Impostazioni › Aggiornamenti (Sources/App/Changelog.swift).

## 0.5.0 · 2026-10-14

Gli attrezzi: quando il disco è pieno o il Mac rallenta, vedi perché e sistemi da qui.

### Novità
- Attrezzi › Spazio: una mappa del disco come GrandPerspective, con tutti i livelli insieme: ogni rettangolo è grande quanto lo spazio che occupa e colorato per tipo (app, documenti, foto e video, sviluppo, cache, sistema), le cartelle hanno il nome in testa. Zoom avanti e indietro, Indietro, livello su e giù, Apri, Quick Look (spazio), Mostra nel Finder, Cestino e Cerca, che evidenzia i risultati nella mappa.
- Accanto alla mappa, le voci più grandi della cartella e i file più grandi lì sotto, con barre e percentuali; in alto una frase dice dove si concentra lo spazio.
- Consigli per liberare spazio: cache delle app, progetti fermi (node_modules, .build, DerivedData), installer già usati, supporto dispositivi di Xcode, backup di iPhone, file grandi non aperti da 6 mesi, Cestino, allegati di Messaggi, libreria di Foto. Quello che togli va nel Cestino, sempre con conferma.
- Attrezzi › App: le app che pesano in memoria o fanno lavorare la CPU, adesso, con Chiudi e Forza chiusura, e una frase su cosa conviene fare.
- Mole dentro l'app: anteprima e pulizia con `mo clean`, manutenzione con `mo optimize`. Se Mole non c'è, si installa con Homebrew da un pulsante.
- Consigli di Apple Intelligence (sperimentale, da Impostazioni › Generale): il modello sul Mac legge un riassunto e propone cosa fare. Niente esce dal Mac.
- Dagli avvisi agli attrezzi: la notifica "Disco quasi pieno" apre la mappa, quelle di memoria e CPU aprono le app. Gli attrezzi si aprono anche dal pannello (⌘T e i pulsanti nelle righe Disco, Memoria e CPU) e dal clic destro sulla voce nella barra.

### Miglioramenti
- Firma con un'identità locale stabile, quando c'è: l'Accesso completo al disco dato agli attrezzi resta dopo gli aggiornamenti.
- Gli attrezzi non lavorano finché non li apri; chiusa la finestra, la mappa se ne va dalla memoria.
- Lettura del disco con getattrlistbulk, più veloce di una lettura file per file; la mappa si disegna una volta in un'immagine, così passare con il puntatore e cercare non costano nulla.

## 0.4.1 · 2026-10-13

Più leggera e più semplice, con una guida per cominciare.

### Novità
- Guida al primo avvio in quattro passi: cosa fa l'app, cosa vedere nella barra, dove arrivano gli avvisi (con il permesso per le notifiche chiesto lì), come si usa. Si rivede da Impostazioni › Generale.
- Impostazioni › Generale mostra quanto pesa What's Going On adesso, CPU e memoria.
- Impostazioni › Avvisi: ogni quanto leggere la temperatura a pannello chiuso (10 s, 30 s, 1 min, 2 min; di base 30 s).

### Miglioramenti
- A pannello chiuso l'app legge solo ciò che mostri nella barra e ciò che serve agli avvisi accesi: temperature solo dai sensori del chip e solo se servono, elenco delle app ogni 10 secondi, niente indirizzo IP.
- Con un'app a schermo intero o la barra nascosta, la voce non si ridisegna. A schermi spenti o Mac bloccato, una lettura ogni 10 secondi; gli avvisi continuano.
- Grafici e barre dei core disegnati in un colpo solo: il pannello aperto costa molto meno.
- Lo storico in memoria si ferma a 60 valori per misura, quelli che i grafici mostrano.
- Disco: al posto delle velocità di lettura e scrittura, una barra con lo spazio occupato. Nessuna lettura continua dei dischi.

## 0.4.0 · 2026-10-13

Prima versione pubblica.

### Novità
- Barra dei menu piccola e colorata: per ogni misura una sigla in colonna, una lettera sotto l'altra (C/P/U, R/A/M…), e il valore accanto in cifre alte e strette, con il % alto quanto le cifre, dal verde al rosso con il carico. La rete ha due righe, upload e download, con colori propri e la freccia davanti. Spazio tra le voci e tra sigla e valore regolabili.
- Colori a scelta: la scala rosso-verde, oppure tre colori tuoi (di partenza verde, bianco e rosso), per la barra e per il pannello. Sulla barra chiara e su quella scura i colori restano leggibili.
- Pannello con la frase che dice cosa succede e una scheda per misura, con grafico e dettagli: CPU, memoria, rete, temperatura, GPU, disco, batteria e consumo.
- App più attive per CPU e per memoria, con gli aiutanti sommati all'app che li contiene.
- Avvisi con soglie nell'isola di Cocaine o come notifiche di macOS.
- Liquid Glass su macOS 26: pannello con i pulsanti in una barra di vetro sotto cui il contenuto scorre e sfuma, schede del pannello con un velo chiaro e un filo di luce, finestra delle impostazioni traslucida, barra delle schede di vetro. Icona a strati: un MacBook Air argento su fondo chiaro, con un grafico che sale dal verde al rosso.
- Leggera: a pannello chiuso la barra si ridisegna solo quando cambia, l'elenco delle app si legge una volta su tre, e pannello e impostazioni chiusi non tengono viste al lavoro.
- Feedback: segnala un problema o suggerisci un'idea su GitHub, scrivi un'email, copia o salva il report di diagnostica.
- Aggiornamenti: controllo automatico ogni 6 ore, novità della nuova versione e comando pronto, anche "Aggiorna nel Terminale".
- Clic destro sulla voce nella barra: impostazioni, novità, feedback, esci.
- Modalità avanzata: GPU, carico di ogni core, tutti i sensori, più app nei dettagli.
- Italiano e inglese.

### Correzioni
- Avvisi verso Cocaine: Cocaine li mostra solo quando sei lontano dal Mac (o con "Anche al Mac" acceso), non in pausa e con il Lampeggio acceso. Negli altri casi ora arriva anche una notifica di macOS, e Impostazioni › Avvisi spiega cosa cambiare in Cocaine.
- Le notifiche si vedono anche con le impostazioni aperte.
