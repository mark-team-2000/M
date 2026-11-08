# M

App nativa macOS per fotografi e videomaker: inserisci una scheda di memoria (SD, microSD, CFexpress, XQD, CompactFlash, qualsiasi volume rimovibile o disco esterno con materiale) e M la scarica dentro una **Sessione**, con cartella nominata per la tessera, verifica di integrità e anti-ripetizione. UI in italiano, dark-first, zero dipendenze esterne.

## Cosa fa

- **Sessioni di scarico**: la sessione crea la sua cartella dentro il contenitore scelto (volume montato selezionabile direttamente); ogni tessera inserita viene copiata in una sottocartella col suo nome.
- **Copia completa e sicura**: copia tutto il contenuto delle cartelle che contengono media, verifica la dimensione di ogni file e blocca i symlink che escono dalla scheda.
- **Anti-ripetizione («tag rosso»)**: i file già scaricati una volta non vengono ricopiati, nemmeno da un'altra sessione; reinserendo la stessa tessera M lo segnala.
- **Report**: `REPORT-<sessione>.md` con esiti e metriche, scritto nella cartella della sessione al pulsante «Fine sessione».
- **Archivio**: «Fine sessione» archivia; le sessioni archiviate si riattivano o si eliminano (solo i registri di M — i file su disco non vengono mai toccati).
- **CapCut**: «Apri CapCut» crea le cartelle `Asset`, `Audio`, `Exports` nella sessione, **crea il progetto CapCut vero e proprio** col nome della sessione (draft reale registrato nell'archivio di CapCut) e apre l'app. Nota: CapCut non espone API pubbliche, quindi l'import dei file nel progetto resta un gesto manuale dentro CapCut (guidato da M).
- **Nome sessione precompilato** con la data `mese.giorno.aa` (es. `11.08.26`).

## Requisiti

- macOS 15 o successivo (Apple Silicon o Intel).
- Per CapCut: CapCut desktop installato (opzionale).

## Installazione (utente finale)

1. Scarica `M-installer.dmg` dalle [Release](../../releases) e aprilo.
2. Trascina **M.app** dentro **Applicazioni**.
3. Prima apertura: M non è firmata con certificato Apple, quindi macOS la bloccherà. Tasto destro su M.app → **Apri** → **Apri** (in alternativa, nel DMG c'è `Apri M alla prima volta.command`, doppio clic e poi apri M normalmente). Dal secondo avvio si apre come qualsiasi app.

## Build dalla sorgente

Serve solo Xcode **Command Line Tools** (`xcode-select --install`), senza Xcode completo e senza rete.

```bash
git clone <repo> && cd M
swift test                 # batteria di test (Swift Testing)
bash scripts/make_app.sh   # bundle dist/M.app firmato ad-hoc
bash scripts/make_distro.sh  # versione distribuibile universale (arm64+x86_64): dist/M-installer.dmg e dist/M.zip
```

## Funzionamento

```
Contenitore scelto (volume/dischi)
└── <nome sessione>/                 ← creata da M
    ├── <tessera 1>/…                ← contenuto della scheda
    ├── <tessera 2>/…
    ├── Asset/  Audio/  Exports/     ← per il flusso CapCut
    └── REPORT-<nome sessione>.md
```

- Le schede sono riconosciute se rimovibili/eiettabili **o** se dischi esterni con cartelle di materiale (i CFexpress Type B spesso risultano dischi esterni fissi). I dischi di destinazione restano ultimi in lista.
- Stato e storico sessioni persistono in `~/Library/Application Support/M/store.json`.

## CapCut: cosa è automatizzato e cosa no

M scrive il progetto CapCut nel suo archivio reale (`~/Movies/CapCut/…`): cartella del draft, `draft_content.json` vuoto derivato dallo schema del progetto più recente, voce nel registro globale (con backup e scrittura atomica). **Con CapCut aperto la creazione è rifiutata** (sovrascriverebbe il suo registro): chiudi CapCut e ripremi il tasto. Dentro CapCut restano manuali «nuovo progetto» e «importa» — CapCut non offre API pubbliche per crearli da fuori.

Utile per prova/debug senza GUI:

```bash
/Applications/M.app/Contents/MacOS/M --capcut-draft "Nome Progetto"
```

## Struttura

```
Sources/M/App          entry point, stato dell'app
Sources/M/Engine       scansione, copia, report, factory draft CapCut
Sources/M/Models       store persistente (JSON)
Sources/M/UI           SwiftUI (sidebar, sessione, pannello tessera)
Sources/M/Watchers     scoperta volumi montati
Tests/MTests           30 test (Swift Testing, nessun volume reale toccato)
docs/SPEC_APP_M.md     contratto funzionale con ruling del fondatore
scripts/               make_app.sh, make_distro.sh, make_icon.swift
```
