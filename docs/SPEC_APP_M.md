# SPEC VINCOLANTE — App «M» (macOS, memory card ingesting)

> Questo file è il CONTRATTO. Qualsiasi divergenza va dichiarata nel report finale del builder.
> Founder: Mark. Lingua UI: italiano. Stato: APPROVATA (default confermati dal founder).

## RULING ITERAZIONE — V1 (08/11, founder; PREVALE su tutto ciò che segue)
Testo letterale del founder: «l'app deve creare una cartella con il nome della sessione all'interno di quella che ora è la cartella di destinazione che si può scegliere il volumes dove possono andare.»
1. La cartella scelta dall'utente è il **contenitore** (in genere un volume): la selezione via pannello non cambia, il volume si sceglie lì.
2. Alla creazione della sessione M crea `<contenitore>/<nome sessione>/` — nome sanitizzato secondo §5; collisione ⇒ suffisso ` 2`, ` 3`… (stessa regola delle tessere).
3. Le cartelle delle tessere e il REPORT stanno **dentro** la cartella sessione: `<contenitore>/<sessione>/<tessera>/…`.
4. Le sessioni salvate prima della modifica (senza percorso registrato) adottano `<contenitore>/<nome sanitizzato>/` alla prima copia e il percorso effettivo viene persistito nel registro (`folderPath`).
5. Se un **file** (non cartella) occupa quel nome: alla creazione di una nuova sessione M usa il suffisso ` 2` e il file non viene toccato; per una sessione già salvata con quel nome (percorso registrato) la copia si ferma con errore chiaro di rinomina.

## 1. Scopo
App nativa macOS chiamata **M** per fotografi/videomaker: inserisci una scheda (SD, microSD, CFexpress, XQD, CompactFlash, qualsiasi volume rimovibile) e M fa l'ingest automaticamente dentro una **Sessione** con una cartella nominata per la tessera, copiando **tutto il contenuto** delle cartelle che contengono i file multimediali, con verifica di integrità **per dimensione** e **anti-ripetizione**: una scheda già scaricata non ricopia i file già copiati (il «tag rosso»).

## 2. Flusso approvato (non negoziabile)
1. L'utente apre M, crea una **Sessione di Scarico**: nome + cartella destinazione (NSOpenPanel, `canChooseDirectories`).
2. La sessione selezionata nella vista dettaglio è la **sessione attiva**: le schede inserite vanno lì. Se nessuna sessione è attiva, la scheda viene rilevata ma nulla viene copiato (banner «Nessuna sessione attiva»).
3. **All'inserimento di un volume rimovibile** (NSWorkspace `didMountNotification` + polling di sicurezza ogni 2s su `mountedVolumeURLs` con `.removableVolume`/`.removable`): M scansiona la scheda e mostra un pannello con:
   - le **cartelle con media** trovate (checkbox, tutte spuntate di default) con conteggio file e GB;
   - un campo **nome cartella tessera** precompilato con l'etichetta del volume (es. `EOS_DIGITAL`), modificabile — è il nome che l'utente digita (es. `Matrimonio-Giorno1`);
   - pulsante **Scarica** (primario, grande).
4. Al via: copia di **tutto il contenuto** delle cartelle scelte (alberi completi, sottocartelle incluse, file non-media dentro una cartella-media inclusi) in
   `<destinazione sessione>/<nome tessera>/<stesso path relativo della scheda>`.
5. Verifica **dimensione file sorgente == dimensione file destinazione** dopo ogni copia. Fine: report in UI + badge di stato.
6. **Anti-ripetizione («tag rosso»)**: M mantiene un registro persistente delle copie per `(volumeUUID, percorso relativo, dimensione, data-modifica sorgente)`. Rigiocando la stessa scheda, i file già nel registro vengono **saltati** («già scaricati»); si copiano **solo i file nuovi**. La UI mostra un **pallino/etichetta rossa** sui file già scaricati. Dopo ogni copia riuscita M tenta anche di apporre il **tag Finder rosso** sul file sulla scheda (`URLResourceValues.label = .red`); su volumi che non lo supportano (exFAT) il fallimento è **ignorato silenziosamente** — il registro interno è la fonte di verità.
7. Pulsante **Espelli in sicurezza** per scheda/volume (`NSWorkspace.unmountAndEjectDevice`), attivo a copia conclusa (o sempre, con conferma se copia in corso).

## 3. Riconoscimento «cartelle con i file giusta»
- Estensioni media primarie (minuscole, senza punto): `jpg jpeg heic heif nef cr2 cr3 arw raf dng orf rw2 gpr raw mp4 mov mxf avi` (+ `wav` per audio collegato).
- Regola: una directory è **media folder massimo** se il suo sottoalbero contiene ≥1 file con estensione primaria E nessun **sottoalbero figlio** scelto la contiene già in via esclusiva — in pratica: risali dal file media fino alla radice; aggrega per **directory di livello più alto che ancora contiene media nel sottoalbero**, e copia quell'intera directory (tutto ciò che contiene, anche file non-media).
- Cartelle di sistema da **ignorare sempre**: nomi che iniziano con `.` (`.Trashes`, `.fseventsd`, `.Spotlight-V100`, `.documentRevisions`), `lost+found`, `__MACOSX`. File con estensioni media **diretti sulla radice** della scheda ⇒ si copiano i loro contenitori fino alla radice (in tal caso la radice è il media folder, esclusi i percorsi di sistema).
- La scansione non deve mai scrivere nulla sulla scheda, tranne il best-effort del Finder label (§2.6).
- **EMENDATO (ruling del padre post-audit QA, 08/11):** politica symlink — un collegamento sulla scheda è ricreato a destinazione **solo se il suo target risolto resta dentro la scheda**; i link che escono (catene `..` o target assoluti) **non sono mai creati** a destinazione e compaiono come errore da-file nel report (test: `rejectsSymbolicLinksPointingOutsideTheCard`). Il registro interno resta la fonte di verità dei file copiati.

## 4. Persistenza (niente CoreData, niente DB esterne)
JSON in `~/Library/Application Support/M/store.json` (crea le cartelle se mancanti), model `Store: Codable`, atomico:
- `SessionRecord`: `id: UUID`, `name: String`, `destinationPath: String`, `createdAt: Date`, `cardIDs: [UUID]`.
- `CardRecord`: `id: UUID`, `sessionID: UUID`, `volumeName: String`, `volumeUUID: String`, `folderName: String`, `destPath: String`, `startedAt: Date`, `finishedAt: Date?`, `status: enum { inCorso, completata, parziale, fallita }` (Codable con rawValue leggibile), `fileCount: Int`, `copiedBytes: Int64`, `skippedCount: Int`, `errors: [String]`.
- `LedgerEntry`: `volumeUUID: String`, `relativePath: String`, `size: Int64`, `sourceModified: Date`, `sessionID: UUID`, `copiedAt: Date`.
Salvataggio dopo ogni card conclusa e periodicamente durante la copia (max ogni 5s). Corruzione del JSON ⇒ backup del file corrotto in `store.corrupt.json` e ripartenza vuota (non crash).

## 5. Architettura (Swift 6.1, CLT-only — NO Xcode)
- `Package.swift`: `// swift-tools-version: 5.9`, executable target `M`, `platforms: [.macOS(.v15)]`, **zero dipendenze esterne SPM** (niente network: il build deve funzionare offline).
- Struttura: `Sources/M/` con `App/` (entry, window, theme), `Models/` (Store e record del §4), `Engine/` (`ScanEngine`, `CopyEngine`, `Ledger`), `Watchers/CardWatcher.swift`, `UI/` (SwiftUI views).
- `CardWatcher`: polling 2s su `FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:)` filtrando rimovibili + `NSWorkspace.shared.notificationQueue` per `didMountNotification`/`didUnmountNotification`. Ogni volume rimontato a metà copia ⇒ copia in corso marcata `fallita` con errore chiaro, l'app non crasha.
- `CopyEngine`: actor, coda sequenziale, copy in chunk (`InputStream`/`OutputStream`, buffer 1 MiB) così il progresso per file è reale e cancellabile; dopo ogni file confronto dimensione; `Task`-cancellation = annulla copia corrente e marca `parziale`. Nessun processo figlio, nessuna chiamata shell.
- Anti-sonno durante la copia: `IOPMAssertionCreateWithName` (`kIOPMAssertPreventUserIdleSystemSleep`), rilasciato a fine copia.
- Trova `volumeUUID` con `URL.resourceValues(forKeys: [.volumeUUIDKey? ...])`: usa `volumeIdentifierForResource`/`volumeUUID` se disponibile, altrimenti fallback `volumeName + volumeCapacityBytes` (documenta nel codice). Il registro usa questo identificatore come chiave di stabilità tra inserimenti.
- Nome cartella tessera: sanitize (sostituisce `/ : * ? " < > |` e newline, trim spazi, max 80 char, vuoto ⇒ etichetta volume, fallback `SCHEDE`); collisione nella destinazione ⇒ suffisso ` 2`, ` 3`...

## 6. UI / UX (requirement forte: «bella UI e UX»)
- Stile: dark-first moderno, materiali SwiftUI, accenti netti, card arrotondate, SF Symbols, tipografia gerarchica; deve stare bene anche in light mode. Min window 960×620.
- **Sidebar**: elenco sessioni come card (nome in grassetto, percorso troncato con ellissi, n° tessere, GB totali); pulsante «+ Nuova sessione»; sessione attiva evidenziata con accento.
- **Dettaglio sessione**: header con nome, percorso, totale; **card «Inserisci una scheda»** con indicatore pulsante quando in attesa; quando una scheda viene rilevata: pannello scan (spinner → elenco cartelle trovate con checkbox, contatori file/GB) + campo nome tessera + **Scarica**; durante la copia: barra progresso totale, file corrente, MB/s, contatore saltati «già scaricati»; a fine copia riepilogo verde con pulsante **Espelli in sicurezza**.
- Elenco tessere della sessione: riga per `CardRecord` con badge stato colorato, pallino rosso sui saltati/ridondanti, percorso, clock, dimensione.
- Pulsante **Report** per sessione: scrive `REPORT-<nome sessione>.md` nella cartella destinazione (data, tessere, file, byte, errori) e lo apre col comando `NSWorkspace.shared.activateFileViewerSelecting`.
- Stati vuati curati (nessuna sessione / nessuna scheda / copia finita). Toast/alert per errori (destinazione mancante, spazio insufficiente — controlla `volumeAvailableCapacity` prima di avviare).
- Icona app: disegnata a runtime in apertura (quadrato sfumato rosso scuro con «M» bianca, via `NSImage` drawing) e assegnata a `NSApp.applicationIconImage` — nessuna risorsa binaria nel repo.

## 7. Bundle `.app`
`scripts/make_app.sh`: `swift build -c release`, assembla `dist/M.app/Contents/{MacOS,Resources}`, `Info.plist` (`CFBundleName=M`, `CFBundleIdentifier=it.marco.m`, `CFBundleShortVersionString=1.0.0`, `LSMinimumSystemVersion=15.0`, `NSHighResolutionCapable=YES`, `LSApplicationCategoryType=public.app-category.utilities`, `NSPrincipalClass=NSApplication`), copia binario, `codesign --force --deep -s - dist/M.app` (ad-hoc). Lo script deve essere idempotente.

## 8. Test obbligatori (`swift test`, offline, su directory temporanee — MAI su volumi reali)
1. `ScanEngine`: albero fixture finto (DCIM/100EOS con .CR3/.JPG, MISC/ senza media, .Trashes con .JPG, file mp4 sulla radice, sottocartelle annidate) ⇒ media folder massimi corretti, sistema ignorato, radice con media ⇒ radice scelta.
2. `Ledger`: stesso path+size ⇒ skip; path uguale size diversa ⇒ copia; volumeUUID diverso ⇒ copia.
3. Sanitize nome + collisioni ` 2`.
4. `CopyEngine` su temp dir: copia ok, mismatch di dimensione (simulato) ⇒ errore registrato, file sorgente intatto, cancellazione ⇒ `parziale`.
5. Store: round-trip JSON, file corrotto ⇒ recovery senza crash.

## 9. VERIFICA OBBLIGATORIA DEL BUILDER (output reale nel report, niente claim a vuoto)
- `swift build` (debug) e `swift build -c release`: verdi.
- `swift test`: tutti i test verdi, incolla il riepilogo `X tests, 0 failures`.
- `bash scripts/make_app.sh`: produce `dist/M.app` con binario eseguibile (`file` lo conferma).
- Nessun file fuori da `~/Documents/AI/M`.

## 10. DIVIETI
- Niente `git` (usa lo script chi comanda), niente dipendenze SPM/network, niente Xcode-only API, niente CoreData/GRDB.
- Non avviare mai la GUI del build finale (la verifica live è del padre); non toccare volumi rimovibili reali né file fuori dal repo; nei test nessun mount reale, solo `FileManager.default.temporaryDirectory`.
- Non toccare `Package.swift` per alzare piattaforme sotto macOS 15.

## 11. Report finale del builder (obbligatorio anche a problemi aperti)
Elenco file creati, uscite letterali dei comandi §9, deviazioni dichiarate una per una, ambiguità irrisolte. Terminare senza report è il fallimento più grave.
