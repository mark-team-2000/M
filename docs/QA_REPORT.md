# QA_REPORT — Audit di sicurezza/robustezza App «M»

## RULINGS DEL PADRE (08/11, prevalgono sul corpo del report)
- **Finding 1 (ALTA) — RISOLTO dal padre.** `validateSymbolicLink` in CopyEngine: containment check del target risolto dentro la scheda prima di `createSymbolicLink`; link uscenti = errore per-file, copia continua. Test `rejectsSymbolicLinksPointingOutsideTheCard` aggiunto; `preservesSymbolicLinksWithoutReadingTheirTargets` riscritto (il vecchio fixture pinava il comportamento insicuro; nome test conservato, dichiarazione di riscrittura qui). Ruling di contratto emendato in SPEC §3 con marker EMENDATO.
- **Finding 2 (MEDIA) — NON-FIX per v1, motivato:** le schede reali (FAT32/exFAT/NTFS) sono case-insensitive anche in lettura su macOS e i percorsi relativi mantengono l'identità di directory; il collisionamento richiede un filesystem sorgente case-sensitive (raro, es. ext4 via macFUSE) e degrada a un errore visibile in report, mai perdita silenziosa. Da considerare se un caso reale si presenta.
- **Finding 3 (BASSA) — accettato come debito di performance futuro** (save su coda background / compattazione ledger). Nessuna modifica v1: prematura senza dati d'uso reali.
- **Finding 4 (BASSA) — NON-FIX:** il contratto chiede letteralmente il backup singolo `store.corrupt.json`; il test existing lo pinà. Il warning UI copre l'evidenza dell'evento. Da emendare nel contratto insieme al test se serve il timestamp.

Auditor read-only. Nessun file modificato/creato oltre questo report. Nessun comando `git`,
nessuna GUI avviata, nessun volume montato/espulso. Comandi eseguiti: `swift test` e
`swift build -c release` (consentiti, scrivono solo in `.build/`), più un piccolo script
di riproduzione in una directory temporanea (`mktemp -d`, rimossa a fine prova) per
dimostrare empiricamente il finding ALTA #1. `bash scripts/make_app.sh` **non** è stato
eseguito per non toccare `dist/M.app` (non esplicitamente autorizzato per l'auditor).

## Verifica preliminare dei claim di BUILD_REPORT.md

BUILD_REPORT.md segnalava come "bloccato" un'ultima riverifica dopo la sola modifica
del branding sidebar (`MEMORY INGEST` → `SCARICO SCHEDE` in `ContentView.swift`).
Ho rieseguito io stesso debug/test/release sullo stato attuale dei sorgenti:

```
swift build --cache-path ... --config-path ... --security-path ...   → Build complete! (exit 0)
swift build -c release ...                                            → Build complete! (exit 0)
swift test ...                                                        → Test run with 17 tests passed after 0.024s (0 failures)
```

**Esito: confermato.** 17/17 test verdi, debug e release verdi, sull'ultimo stato dei
sorgenti (branding incluso). Il blocco segnalato dal builder è risolto: l'identità
sorgenti/ultima-verifica è ora accertata dall'auditor. Resta non ri-verificato da me
il solo rebundle (`dist/M.app` + codesign), per il motivo di scope indicato sopra.

Altri claim puntuali verificati per grep/lettura diretta del codice (tutti **veri**):
IOPMAssertionCreateWithName in CopyEngine.swift; `labelNumber = 6` (non `.label/.red`)
in CopyEngine.swift; `notificationCenter` (non `notificationQueue`) in CardWatcher.swift;
`.macOS("15.0")` in Package.swift; mkdir esclusiva in FolderNaming.swift; checkpoint
Timer da 3s in AppModel.swift; NSOpenPanel `canChooseDirectories` in ContentView.swift;
set di estensioni media in ScanEngine.swift identico a quello del contratto §3.
Nessun claim funzionale del report è risultato falso/assente nel codice.

---

## FINDING 1 — ALTA: i symlink della scheda vengono ricreati a destinazione con il target letterale, non validato → traversal/arbitrary-symlink

**Ancore:**
- `Sources/M/Engine/ScanEngine.swift`: `symbolicLinkTarget: try fm.destinationOfSymbolicLink(atPath: url.path)` — il target del link viene letto e memorizzato **senza alcuna validazione** (si valida solo che la *posizione* del symlink sia dentro la scheda: `guard path.hasPrefix(prefix)`).
- `Sources/M/Engine/CopyEngine.swift`: `try FileManager.default.createSymbolicLink(atPath: staging.path, withDestinationPath: link)` — il link viene ricreato a destinazione con la **stessa stringa target letterale** presa dalla scheda, qualunque essa sia (percorso assoluto, oppure relativo con `../../..`).

**Perché è un problema reale (non teorico):** l'ho riprodotto concretamente. Una scheda
(anche solo "strana", non necessariamente malevola — es. prodotta da un tool Linux, un
backup incompleto, o scheda deliberatamente craftata per colpire un fotografo) può
contenere un symlink con target relativo tipo `../../outside_the_card.txt` o assoluto
tipo `/Users/vittima/.ssh/id_rsa`. Il contratto §2.4 impone `<dest sessione>/<tessera>/
<stesso path relativo della scheda>`: la posizione del symlink copiato cambia, ma M
riscrive **lo stesso testo del link** a quella nuova posizione. Risultato dimostrato
con una prova in `mktemp -d` (rimossa a fine test):

```
symlink sulla scheda:  card/DCIM/100EOS/link.txt -> ../../outside_the_card.txt
                        (risolve, finché resta sulla scheda, a un file FUORI dalla scheda:
                         comportamento già "off-card" di per sé, ma inerte perché nessuno
                         lo segue durante la scansione)
stesso link ricreato alla destinazione contrattuale:
  dest/Sessione A/EOS_DIGITAL/DCIM/100EOS/link.txt -> ../../outside_the_card.txt
  → si risolve a: dest/Sessione A/EOS_DIGITAL/outside_the_card.txt
    cioè DENTRO l'albero della sessione ma a un percorso/file che l'utente non ha mai
    scelto di copiare.
```

Con un target assoluto il problema è anche più diretto: il link finale nella libreria
foto dell'utente punta esattamente a quell'assoluto (es. `/etc/passwd`, un'altra
sessione di M, file di sistema), indipendentemente da dove si trovi la destinazione.
E con un numero di `../` sufficiente anche un target *relativo* raggiunge qualunque
percorso assoluto (la risalita oltre `/` è un no-op POSIX), quindi "relativo" non è
una mitigazione. Una volta nella libreria foto dell'utente, un link del genere diventa
innesco per chiunque/qualunque software segua symlink senza avviso (Spotlight,
anteprime Finder, sync iCloud/Dropbox, backup, archiviazione zip/tar): lettura di file
sensibili o, se il target è scrivibile, un vettore di sovrascrittura indiretta.

Aggravante di superficie d'attacco: lo stesso `isMedia` per i symlink (ScanEngine,
riga che calcola `isMedia: mediaExtensions.contains(url.pathExtension.lowercased())`
anche per i link) fa sì che un singolo symlink alla radice con estensione media (es.
`root_link.jpg -> ../../../../Users/vittima/.ssh`) **promuove l'intera radice a media
folder**, selezionata **di default spuntata** per §3 del contratto: l'attacco non
richiede alcuna azione particolare dell'utente oltre cliccare "Scarica".

Il BUILD_REPORT dichiara onestamente la scelta ("collegamenti simbolici conservati
come collegamenti, senza seguirne i target... il contratto non specificava una
politica per i link") e il test `preservesSymbolicLinksWithoutReadingTheirTargets`
copre solo che *la scansione* non legga il contenuto del target — non che il link
*ricreato a destinazione* sia sicuro. Il claim è letteralmente vero ma **omette la
conseguenza di sicurezza**: "non seguire il target" durante la scansione non impedisce
di piantare un link pericoloso nella libreria foto dell'utente.

**Fix minimo consigliato:** in `CopyEngine.run`, prima di `createSymbolicLink`,
risolvere il target del link rispetto alla directory del file (stessa logica già
presente in `safeURL`/`validateRoots`) e, se il percorso risolto non resta dentro
`request.sourceRoot` risolto, **non creare il link**: trattarlo come un errore di
file (append a `outcome.errors`, non incrementare `fileCount`) esattamente come già
avviene per i mismatch di dimensione. In alternativa più conservativa: non ricreare
mai symlink a destinazione, copiare il *contenuto* del target solo se risolve dentro
la scheda, altrimenti segnalare errore. Qualunque delle due chiude il buco con poche
righe, senza cambiare l'architettura.

---

## FINDING 2 — MEDIA: collisione di nome su filesystem di destinazione case-insensitive può far "sparire" silenziosamente un file nuovo (segnalato come errore, non perdita silenziosa totale, ma comunque mancata copia)

**Ancora:** `Sources/M/Engine/CopyEngine.swift`: `guard !FileManager.default.fileExists(atPath: target.path) else { throw IngestError.message("Il file di destinazione esiste già; non è stato sovrascritto.") }`.

**Perché è un problema reale:** la destinazione (APFS, il default su macOS) è
case-insensitive per default; se la scheda sorgente è case-sensitive (filesystem non
FAT/exFAT, es. schede formattate ext4/HFSX in flusso di lavoro non standard, o
semplicemente due media-folder diversi che contengono per coincidenza `IMG_0001.JPG`
e un file `img_0001.jpg` legittimamente distinto altrove nello stesso albero
selezionato) `fileExists` userà la risoluzione case-insensitive del filesystem di
destinazione e il secondo file, mai copiato prima, verrà rifiutato come "esiste già"
pur essendo nuovo e diverso. Non è perdita silenziosa (finisce in `outcome.errors` e
in UI/report), ma è una copia **incompleta non motivata da un vero conflitto**, in
contrasto con la promessa contrattuale "copia tutto il contenuto". Caso limite, ma
reale e non testato (nessun test esercita nomi che differiscono solo per maiuscole).

**Fix minimo consigliato:** quando il confronto case-insensitive segnala un
"esistente" che in realtà non corrisponde byte-per-byte al path case-sensitive
richiesto (`FileManager.default.fileExists` seguito da un confronto esplicito tra
`target.lastPathComponent` e il nome reale sul disco via `contentsOfDirectory`),
trattare il conflitto come collisione di nome (suffisso, come già fatto per le
cartelle in `FolderNaming.reserve`) invece che come errore bloccante.

---

## FINDING 3 — BASSA: il ledger/registro cresce senza limiti e senza compattazione

**Ancora:** `Sources/M/Models/Store.swift` (`var ledger: [LedgerEntry] = []`) e
`Sources/M/Models/StoreRepository.swift` (`try encoder.encode(store).write(to: url,
options: .atomic)` eseguito sincronamente sul MainActor ogni checkpoint da 3s durante
la copia, oltre che a fine sessione/card).

**Perché è un problema reale (minore, ma degrada nel tempo):** per un workflow di
fotografia/video reale con migliaia di scariche su mesi/anni, `store.ledger` cresce
senza mai essere compattato o archiviato; ogni salvataggio (incluso il checkpoint ogni
3s durante una copia lunga) serializza/riscrive **l'intero** file JSON in modo
sincrono sul thread principale (`@MainActor`), quindi un registro molto grande rallenta
progressivamente ogni copia e può introdurre micro-freeze della UI. Non è una
violazione di contratto (il contratto non impone retention policy), ma è un rischio di
robustezza a lungo termine non menzionato nel BUILD_REPORT.

**Fix minimo consigliato:** nessuna urgenza immediata; se diventa un problema reale,
spostare `save()` su una coda background con write atomico, o introdurre una
retention/compattazione del ledger (es. per `volumeUUID` non più visto da N mesi).

---

## FINDING 4 — BASSA: `store.corrupt.json` viene sovrascritto ad ogni nuova corruzione

**Ancora:** `Sources/M/Models/StoreRepository.swift`: `try data.write(to: backup,
options: .atomic)` con `backup` sempre lo stesso path fisso `store.corrupt.json`.

**Perché è un problema reale (minore):** se il file si corrompe due volte in momenti
diversi (es. due crash separati nel tempo), il secondo evento sovrascrive il backup
del primo: si perde la copia forense del primo incidente. Il contratto richiede solo
"backup del file corrotto in store.corrupt.json" (singolare, quindi tecnicamente
conforme), ma per un registro che è "fonte di verità" anti-ripetizione vale la pena
nominare i backup con timestamp per non perdere evidenza in caso di corruzioni
ricorrenti.

**Fix minimo consigliato:** nominare il backup con timestamp (es.
`store.corrupt.<ISO8601>.json`) invece di un nome fisso.

---

## Punti verificati e risultati CONFORMI (nessun difetto)

Per completezza, elenco le aree del focus dell'audit dove il codice **rispetta** il
contratto ed è stato verificato attivamente (lettura + test esistenti + in alcuni casi
riesecuzione):

- **Non sovrascrittura mai**: `FileManager.default.moveItem` non sovrascrive mai
  (CocoaError se la destinazione esiste) ed è comunque preceduto da un controllo
  esplicito `fileExists`; confermato dal test
  `rejectsDestinationInsideSourceAndNeverOverwritesExistingFiles`.
- **Destinazione mai dentro la scheda sorgente**: doppio controllo, sia in
  `AppModel.startCopy` (`guard source != destination, !destination.hasPrefix(source +
  "/")`) sia in `CopyEngine.validateRoots`; stesso test di sopra lo esercita.
- **Confronto dimensione dopo copia**: `destinationSize(staging) == file.size` prima
  dello `moveItem`; verificato anche dal test
  `simulatedSizeMismatchDoesNotRegisterAndKeepsSourceIntact` (mismatch simulato ⇒
  nessuna entry nel ledger, file sorgente intatto, nessun file parziale a destinazione).
- **Cancellazione → `parziale`, file incompleto rimosso**: confermato dal test
  `cancellationKeepsVerifiedFilesAndRemovesIncompleteFile`.
- **Path traversal via `relativePath` (voci `..`, path assoluti)**: bloccato da
  `safeURL` sia per sorgente sia per destinazione (segmenti vuoti, `.`, `..` e path
  assoluti rigettati). Non risultano test dedicati a stringhe `relativePath` malformate
  iniettate direttamente (il percorso realistico è sempre popolato dall'enumeratore,
  quindi il rischio pratico è basso), ma il controllo in codice è corretto e ridondante
  col Finding 1, che resta l'unico varco reale dimostrato.
- **Ledger anti-ripetizione** per `(volumeUUID, relativePath, size, sourceModified)`,
  globale tra sessioni come richiesto dal contratto §2.6: confermato da
  `exactIdentitySkipsButChangedSizeDateOrVolumeCopies` e da
  `copiesWholeTreeAndSkipsRegisteredFiles` (seconda esecuzione: skip completo).
- **Media folder massimi §3**: branch di primo livello con media nel sottoalbero,
  promozione a radice se media diretti sulla radice, esclusione `.`/`lost+found`/
  `__MACOSX` anche sotto promozione radice: confermato da
  `topLevelMediaFoldersIncludeSidecarsAndIgnoreSystem`,
  `rootMediaPromotesRootAndPreservesHiddenSupportFiles`,
  `noMediaHasAnEmptyResultAndWavIsRecognized`. Elenco estensioni media identico a
  quello letterale del contratto.
- **Sanitize nome tessera e collisioni**: caratteri vietati sostituiti, trim, limite
  80 char **anche con suffisso**, fallback `SCHEDE`, collisione via `mkdir` esclusiva
  (niente TOCTOU tra due card scaricate "in parallelo" con lo stesso nome): confermato
  da `sanitizesAndAllocatesCollisionSuffixes`.
- **Persistenza Store**: round-trip JSON, scrittura atomica (`.atomic`), recovery da
  corruzione con backup e ripartenza vuota senza crash, record `inCorso` recuperati come
  `parziale` al riavvio: confermati da `jsonRoundTripAndCorruptionBackup` e
  `interruptedRecordIsRecoveredAsPartialOnNextLaunch`.
- **Nessuna copia senza sessione attiva**: `startCopy` verifica `activeSession` prima
  di ogni altra cosa; confermato da
  `noActiveSessionNeverCopiesAndLedgerSurvivesAcrossSessions`.
- **Race scheda rimossa/rimontata durante copia**: `CardWatcher` tratta un remount con
  `volumeUUID` diverso (o notifica di mount) come unmount+mount; `AppModel.didUnmount`
  cancella la copia attiva e marca la card `fallita` con messaggio chiaro, senza
  corrompere il draft della nuova card; confermato da
  `syntheticUnmountAndRemountMarksRunningCardFailedWithoutCorruptingNewDraft`.
- **Nessun tocco a volumi non rimovibili**: `MountedCard.read` filtra su
  `volumeIsRemovable || volumeIsEjectable`; il disco di avvio tipico non soddisfa né
  l'uno né l'altro, quindi non genera mai un `CardDraft`. Nota minore non bloccante:
  un disco esterno non-removibile ma marcato "ejectable" (es. un SSD Thunderbolt in un
  dock) verrebbe trattato come scheda; è coerente con l'intento "qualunque volume
  rimovibile" del contratto e con il significato che macOS stesso dà a "ejectable", non
  lo considero un difetto.
- **Spazio insufficiente e destinazione mancante/non scrivibile**: bloccati da
  `DestinationCheck.validate` prima di avviare la copia e prima di scrivere il report;
  confermato da `missingDestinationAndInsufficientSpaceAreRejected`.
- **Uscita dall'app durante una copia**: `NSApplicationDelegate.
  applicationShouldTerminate` chiede conferma, annulla la copia e attende
  `waitForCurrentCopy()` prima di terminare davvero (`.terminateLater` +
  `reply(toApplicationShouldTerminate:)`), coerente con "non crasha" del contratto §5.

## Esiti letterali dei comandi eseguiti dall'auditor

```
$ swift build --cache-path ... --config-path ... --security-path ...
Build complete! (0.14s)   # exit 0

$ swift build -c release --cache-path ... --config-path ... --security-path ...
Build complete! (0.11s)   # exit 0

$ swift test --cache-path ... --config-path ... --security-path ...
...
✔ Test run with 17 tests passed after 0.024 seconds.   # exit 0, 17 tests, 0 failures
```

## Conclusione

Nessun difetto di severità ALTA preesistente nella logica "core" di copia/ledger/
persistenza a parte il Finding 1 (symlink non validati): la gestione di
non-sovrascrittura, confronto dimensione, cancellazione, destinazione-dentro-la-scheda,
anti-ripetizione, media folder §3, sanitize/collisioni, persistenza atomica e recovery,
race scheda rimossa/rimontata e blocco "nessuna sessione attiva" sono tutte
implementate correttamente e coperte da test che effettivamente esercitano lo scenario
descritto (non solo "happy path"). Il Finding 1 è l'unico problema con potenziale impatto
di sicurezza reale (non ipotetico: riprodotto) ed è anche l'unico che tocca
direttamente il focus esplicito "path traversal da nomi file sulla scheda — symlink o
entry `..`" richiesto da questo audit. I Finding 2–4 sono rifiniture di robustezza a
basso impatto. Tutti i claim funzionali verificabili del BUILD_REPORT risultano veri;
il suo unico punto aperto (riverifica dopo il cambio di branding) è stato chiuso da
questo audit con esecuzione reale e verde di debug/release/test sullo stato attuale.
