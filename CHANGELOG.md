# Novità

Formato: `## <versione> · <data>`, poi `### Novità`, `### Miglioramenti`, `### Correzioni`, una riga `- ` per
cambiamento. L'app mostra la sezione della sua versione in Impostazioni › Aggiornamenti (Sources/App/Changelog.swift).

## 0.4.0 · 2026-10-13

Prima versione pubblica.

### Novità
- Barra dei menu piccola e colorata: per ogni misura una sigla in verticale (CPU, RAM, RETE…) e il valore accanto, dal verde al rosso con il carico. La rete ha due righe, upload e download, con colori propri e la freccia davanti.
- Pannello con la frase che dice cosa succede e una scheda per misura, con grafico e dettagli: CPU, memoria, rete, temperatura, GPU, disco, batteria e consumo.
- App più attive per CPU e per memoria, con gli aiutanti sommati all'app che li contiene.
- Avvisi con soglie nell'isola di Cocaine o come notifiche di macOS.
- Liquid Glass su macOS 26: pannello, barra delle schede e pulsanti; nuova icona a strati con un MacBook Air e un grafico che sale dal verde al rosso.
- Feedback: segnala un problema o suggerisci un'idea su GitHub, scrivi un'email, copia o salva il report di diagnostica.
- Aggiornamenti: controllo automatico ogni 6 ore, novità della nuova versione e comando pronto, anche "Aggiorna nel Terminale".
- Clic destro sulla voce nella barra: impostazioni, novità, feedback, esci.
- Modalità avanzata: GPU, carico di ogni core, tutti i sensori, più app nei dettagli.
- Italiano e inglese.

### Correzioni
- Avvisi verso Cocaine: Cocaine li mostra solo quando sei lontano dal Mac (o con "Anche al Mac" acceso), non in pausa e con il Lampeggio acceso. Negli altri casi ora arriva anche una notifica di macOS, e Impostazioni › Avvisi spiega cosa cambiare in Cocaine.
- Le notifiche si vedono anche con le impostazioni aperte.
