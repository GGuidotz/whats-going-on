# Novità

Formato: `## <versione> · <data>`, poi `### Novità`, `### Miglioramenti`, `### Correzioni`, una riga `- ` per
cambiamento. L'app mostra la sezione della sua versione in Impostazioni › Aggiornamenti (Sources/App/Changelog.swift).

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
