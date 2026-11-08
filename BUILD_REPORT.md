# Report finale BUILDER — M

## Esito e stato della consegna

Implementazione dell’app SwiftPM nativa completata nel repository. **Debug, release, 17 test, bundle, firma ad-hoc e identificazione Mach-O sono risultati verdi nell’ultima verifica completa eseguita.**

**Blocco finale da non nascondere:** dopo tale verifica è stata cambiata soltanto la scritta di branding della sidebar, da `MEMORY INGEST` a `SCARICO SCHEDE`, in `Sources/M/UI/ContentView.swift`. Il tentativo di rieseguire l’intera verifica sull’ultimissimo stato dei sorgenti è stato fermato dal sistema di approvazioni prima di eseguire alcun comando. Non ho aggirato né rilanciato la richiesta. Il bundle già prodotto corrisponde quindi allo stato immediatamente precedente a questa sola modifica testuale. Il padre deve autorizzare/eseguire l’ultima riverifica e rigenerazione del bundle prima di dichiarare verificata l’identità esatta sorgenti/bundle.

Non è stata avviata la GUI. Non sono stati montati, espulsi, scansionati o modificati volumi rimovibili reali. Nessun comando git è stato eseguito e `docs/` non è stato modificato.

## Funzionalità implementate

- Sessioni con destinazione selezionata tramite NSOpenPanel, sidebar selezionabile e disattivazione della sessione attiva.
- Rilevamento tramite notifiche NSWorkspace e polling ogni 2 secondi; scansione asincrona cancellabile e protezione contro risultati obsoleti dopo un reinserimento.
- Raggruppamento per directory di primo livello contenenti media; promozione alla radice quando vi sono media direttamente alla radice; esclusione ricorsiva delle directory di sistema.
- Copia dell’albero completo delle cartelle selezionate, inclusi sidecar, file di supporto nascosti e directory vuote; collegamenti simbolici conservati come collegamenti, senza seguirne i target.
- CopyEngine actor con gate FIFO, stream a chunk da 1 MiB, progresso reale per file e totale, velocità, cancellazione, staging e confronto delle dimensioni dopo chiusura dei flussi.
- Controllo che la sorgente non sia cambiata dopo la scansione; nessuna sovrascrittura di file esistenti; blocco della destinazione interna alla scheda sorgente.
- Registro globale persistente indicizzato per volume/path/dimensione/data-modifica; pallini e contatori rossi sui file già scaricati; Finder label rossa best-effort sui file regolari sorgenti.
- JSON atomico in Application Support/M, salvataggio iniziale/finale e timer di checkpoint ogni 3 secondi durante la copia; backup `store.corrupt.json` e recovery; record interrotti recuperati come parziali al riavvio.
- Rimozione/rimontaggio durante copia con record `fallita`, annullamento del task e messaggio chiaro. Eventi sintetici di questo flusso verificati su fixture temporanee, senza avviare CardWatcher.
- Assertion IOKit anti-sonno durante la copia e rilascio finale; disabilitata nei test insieme ai tag Finder.
- Sanitize e collisioni esclusive tramite mkdir (` 2`, ` 3`…), mantenendo il limite di 80 caratteri anche con suffisso.
- Controllo destinazione esistente/scrivibile e capacità disponibile prima della copia; report Markdown e selezione nel Finder; espulsione tramite NSWorkspace solo quando non si sta copiando quella scheda.
- UI dark-first con materiali, card arrotondate, accento rosso, tipografia gerarchica, stati vuoti, indicatore pulsante, dettagli dei file e delle segnalazioni, conferma annullamento e protezione dall’uscita durante copia. Aspetto chiaro/sistema selezionabile.
- Icona M disegnata con NSImage a runtime, senza asset catalog o risorse binarie.
- Script idempotente di assemblaggio bundle e firma ad-hoc, eseguito più di una volta con esito positivo.

## File nuovi creati

```text
Package.swift
Sources/M/App/AppModel.swift
Sources/M/App/MApp.swift
Sources/M/App/Theme.swift
Sources/M/Engine/CopyEngine.swift
Sources/M/Engine/DestinationCheck.swift
Sources/M/Engine/FolderNaming.swift
Sources/M/Engine/Ledger.swift
Sources/M/Engine/ReportWriter.swift
Sources/M/Engine/ScanEngine.swift
Sources/M/Models/Store.swift
Sources/M/Models/StoreRepository.swift
Sources/M/UI/CardPanel.swift
Sources/M/UI/ContentView.swift
Sources/M/UI/SessionDetail.swift
Sources/M/Watchers/CardWatcher.swift
Tests/MTests/AppModelTests.swift
Tests/MTests/CopyEngineTests.swift
Tests/MTests/CopyFailureTests.swift
Tests/MTests/DestinationAndReportTests.swift
Tests/MTests/LedgerTests.swift
Tests/MTests/NamingTests.swift
Tests/MTests/ScanEngineTests.swift
Tests/MTests/StoreTests.swift
scripts/make_app.sh
BUILD_REPORT.md
```

Artefatti generati: `.build/`, `dist/M.app/Contents/Info.plist`, `dist/M.app/Contents/MacOS/M`, firma in `dist/M.app/Contents/_CodeSignature/` e directory `Resources/` vuota. Tutti i file di progetto sono dentro `/Users/mark/Documents/AI/M`. Le fixture usano esclusivamente `FileManager.default.temporaryDirectory` come richiesto e vengono rimosse alla fine dei test. Lo script è eseguibile.

## Deviazioni dichiarate una per una

1. **Sintassi piattaforma:** `.macOS(.v15)` non compila con `// swift-tools-version: 5.9`: il compilatore segnala che `v15` è introdotto in PackageDescription 6.0. Usata `.macOS("15.0")`, senza cambiare tools-version né deployment target. Verificati `LSMinimumSystemVersion=15.0` e `LC_BUILD_VERSION/minos 15.0` nel binario.
2. **Framework di test:** i CLT installati non forniscono il modulo XCTest. Il primo tentativo reale con `import XCTest` ha prodotto `error: no such module 'XCTest'`. È invece presente il framework Apple Swift Testing, usato per gli stessi test puri/offline. **Il requisito letterale “XCTest” non è soddisfatto** per incompatibilità con questo ambiente CLT-only; non è stato aggiunto alcun pacchetto né scaricato alcun framework. I 17 test eseguiti sono autentici test Swift Testing, non un falso shim XCTest.
3. **Notifiche NSWorkspace:** l’API reale è `NSWorkspace.shared.notificationCenter`, con observer sulla OperationQueue principale, non `notificationQueue` (inesistente nell’header NSWorkspace dei CLT). Semantica richiesta mantenuta.
4. **Finder label:** l’API reale è `URLResourceValues.labelNumber = 6` (rosso), non `.label = .red`. Il fallimento è ignorato silenziosamente come richiesto; il ledger è la fonte di verità. Sui collegamenti simbolici non si tenta un tag che potrebbe essere applicato al target esterno.
5. **Chiavi URL dei volumi:** usate le API disponibili `.volumeIsRemovableKey`, `.volumeIsEjectableKey`, `.volumeUUIDStringKey`, `.volumeTotalCapacityKey`. Per volumi senza UUID persistente viene usato il fallback nome+capacità richiesto, documentato nel codice.
6. **Ultimissima riverifica:** pendente approvazione, come indicato all’inizio. Non si presenta come eseguita una richiesta bloccata prima dell’esecuzione.

## Ambiguità risolte e limiti dichiarati

- “Media folder massimo”: interpretato come ramo di primo livello che contiene media, non l’intera scheda in ogni caso. Se vi sono media direttamente alla radice, viene selezionata unicamente la radice e si includono anche gli altri rami non-media, salvo le directory di sistema. È coperto da test.
- L’esclusione dei nomi che iniziano con punto è applicata alle **directory di sistema**, come dice §3; i file di supporto nascosti dentro un albero selezionato sono copiati.
- I link simbolici vengono conservati senza seguire i target. Non vengono letti contenuti esterni alla scheda. Il contratto non specificava una politica per i link.
- Il ledger è globale tra sessioni: una copia già registrata viene saltata anche se si cambia sessione. La UI lo esplicita nel riepilogo. Non si verifica nuovamente l’esistenza della precedente copia: il contratto definisce il registro come fonte di verità.
- Il fallback nome+capacità può identificare allo stesso modo due schede uguali prive di UUID: limite del fallback richiesto, non occultato.
- Verifica di integrità per dimensione, non checksum, esplicitata in UI e nei report.
- Aspetto grafico, eventi fisici di mount, supporto reale Finder label su exFAT, assertion anti-sonno e reale espulsione non sono stati verificati live: la verifica GUI/hardware è riservata al padre. Non si dichiara un collaudo visivo mai eseguito.

## Output letterali dell’ultima verifica completa eseguita

Per confinare cache/configurazione di compilazione nel repository sono stati usati questi export e i flag locali riportati nei comandi:

```sh
export TMPDIR="$PWD/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
```

### Debug — exit code 0

Comando:

```sh
swift build --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
```

```text
[0/1] Planning build
Building for debugging...
[0/3] Write swift-version--1AB21518FC5DEDBE.txt
Build complete! (0.14s)
```

### Release — exit code 0

```sh
swift build -c release --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
```

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version--1AB21518FC5DEDBE.txt
Build complete! (0.11s)
```

### Test — exit code 0

```sh
swift test --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
```

```text
[0/1] Planning build
Building for debugging...
[0/4] Write swift-version--1AB21518FC5DEDBE.txt
Build complete! (0.11s)
◇ Test run started.
↳ Testing Library Version: 124.4
↳ Target Platform: arm64e-apple-macos14.0
◇ Suite DestinationAndReportTests started.
◇ Suite AppModelTests started.
◇ Suite CopyEngineTests started.
◇ Suite ScanEngineTests started.
◇ Suite NamingTests started.
◇ Suite StoreTests started.
◇ Suite CopyFailureTests started.
◇ Test missingDestinationAndInsufficientSpaceAreRejected() started.
◇ Test reportIncludesCardsBytesAndErrorsInDestination() started.
◇ Test noMediaHasAnEmptyResultAndWavIsRecognized() started.
◇ Suite LedgerTests started.
◇ Test interruptedRecordIsRecoveredAsPartialOnNextLaunch() started.
◇ Test preservesSymbolicLinksWithoutReadingTheirTargets() started.
◇ Test syntheticUnmountAndRemountMarksRunningCardFailedWithoutCorruptingNewDraft() started.
◇ Test topLevelMediaFoldersIncludeSidecarsAndIgnoreSystem() started.
◇ Test rootMediaPromotesRootAndPreservesHiddenSupportFiles() started.
◇ Test noActiveSessionNeverCopiesAndLedgerSurvivesAcrossSessions() started.
◇ Test simulatedSizeMismatchDoesNotRegisterAndKeepsSourceIntact() started.
◇ Test cancellationKeepsVerifiedFilesAndRemovesIncompleteFile() started.
◇ Test exactIdentitySkipsButChangedSizeDateOrVolumeCopies() started.
◇ Test jsonRoundTripAndCorruptionBackup() started.
◇ Test sanitizesAndAllocatesCollisionSuffixes() started.
◇ Test sourceMutationDuringCopyIsDetectedAfterStreamCloses() started.
◇ Test rejectsDestinationInsideSourceAndNeverOverwritesExistingFiles() started.
◇ Test copiesWholeTreeAndSkipsRegisteredFiles() started.
✔ Test exactIdentitySkipsButChangedSizeDateOrVolumeCopies() passed after 0.001 seconds.
✔ Suite LedgerTests passed after 0.001 seconds.
✔ Test sanitizesAndAllocatesCollisionSuffixes() passed after 0.005 seconds.
✔ Suite NamingTests passed after 0.005 seconds.
✔ Test rejectsDestinationInsideSourceAndNeverOverwritesExistingFiles() passed after 0.007 seconds.
✔ Test noMediaHasAnEmptyResultAndWavIsRecognized() passed after 0.007 seconds.
✔ Test jsonRoundTripAndCorruptionBackup() passed after 0.008 seconds.
✔ Suite StoreTests passed after 0.008 seconds.
✔ Test reportIncludesCardsBytesAndErrorsInDestination() passed after 0.008 seconds.
✔ Test sourceMutationDuringCopyIsDetectedAfterStreamCloses() passed after 0.009 seconds.
✔ Test simulatedSizeMismatchDoesNotRegisterAndKeepsSourceIntact() passed after 0.009 seconds.
✔ Test interruptedRecordIsRecoveredAsPartialOnNextLaunch() passed after 0.010 seconds.
✔ Test rootMediaPromotesRootAndPreservesHiddenSupportFiles() passed after 0.010 seconds.
✔ Test topLevelMediaFoldersIncludeSidecarsAndIgnoreSystem() passed after 0.011 seconds.
✔ Suite ScanEngineTests passed after 0.011 seconds.
✔ Test preservesSymbolicLinksWithoutReadingTheirTargets() passed after 0.011 seconds.
✔ Test missingDestinationAndInsufficientSpaceAreRejected() passed after 0.011 seconds.
✔ Suite DestinationAndReportTests passed after 0.011 seconds.
✔ Test cancellationKeepsVerifiedFilesAndRemovesIncompleteFile() passed after 0.011 seconds.
✔ Suite CopyFailureTests passed after 0.012 seconds.
✔ Test copiesWholeTreeAndSkipsRegisteredFiles() passed after 0.012 seconds.
✔ Suite CopyEngineTests passed after 0.012 seconds.
✔ Test syntheticUnmountAndRemountMarksRunningCardFailedWithoutCorruptingNewDraft() passed after 0.013 seconds.
✔ Test noActiveSessionNeverCopiesAndLedgerSurvivesAcrossSessions() passed after 0.015 seconds.
✔ Suite AppModelTests passed after 0.016 seconds.
✔ Test run with 17 tests passed after 0.016 seconds.
```

Riepilogo: **17 test passati, 0 failures**. La riga nativa è quella Swift Testing riportata sopra; non è stata fabbricata una riga nel formato XCTest `Executed X tests, with 0 failures`.

### Bundle — exit code 0

```sh
bash scripts/make_app.sh
```

```text
[0/1] Planning build
Building for production...
[0/2] Write swift-version--1AB21518FC5DEDBE.txt
Build complete! (0.11s)
/Users/mark/Documents/AI/M/dist/M.app/Contents/Info.plist: OK
/Users/mark/Documents/AI/M/dist/M.app: replacing existing signature
Bundle creato e firma ad-hoc verificata: /Users/mark/Documents/AI/M/dist/M.app
```

### Identificazione binario — exit code 0

```sh
file dist/M.app/Contents/MacOS/M
```

```text
dist/M.app/Contents/MacOS/M: Mach-O 64-bit executable arm64
```

### Verifiche aggiuntive — exit code 0

```sh
bash -n scripts/make_app.sh
codesign --verify --deep --strict --verbose=2 dist/M.app
plutil -lint dist/M.app/Contents/Info.plist
```

```text
dist/M.app: valid on disk
dist/M.app: satisfies its Designated Requirement
dist/M.app/Contents/Info.plist: OK
```

Ispezione effettiva del flag eseguibile, Info.plist e load command Mach-O:

```text
Executable bit: True
CFBundleIdentifier: it.marco.m
CFBundleShortVersionString: 1.0.0
LSMinimumSystemVersion: 15.0
NSPrincipalClass: NSApplication
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform 1
    minos 15.0
      sdk 15.5
   ntools 1
     tool 3
```

## Da chiudere dal padre

1. Autorizzare o rieseguire debug, release, test e `bash scripts/make_app.sh` sull’ultimissima modifica testuale della sidebar, quindi aggiornare questo report se gli esiti cambiano.
2. Eseguire la verifica live della GUI e dell’ingest su hardware, fuori dal compito del builder.
3. Valutare/accettare esplicitamente la deviazione Swift Testing al posto di XCTest imposta dai CLT disponibili.
4. Eseguire gli eventuali comandi git: il builder non ne ha eseguiti.
