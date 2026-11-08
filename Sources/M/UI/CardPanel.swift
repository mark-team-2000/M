import SwiftUI

struct CardPanel: View {
    @ObservedObject var model: AppModel
    @Binding var draft: CardDraft
    @State private var confirmingCancellation = false
    var body: some View {
        Surface(padding: 23) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 13) {
                    Image(systemName: "sdcard.fill").font(.system(size: 25, weight: .light)).foregroundStyle(Theme.accent)
                        .frame(width: 49, height: 49).background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(draft.volume.name).font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if draft.phase != .copying {
                        Button { model.eject(draft.volume) } label: { Label("Espelli", systemImage: "eject") }.buttonStyle(.borderless).font(.caption).help("Espelli in sicurezza")
                    }
                }
                switch draft.phase {
                case .scanning:
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cerco le cartelle con i tuoi media…").font(.subheadline)
                            Text("Nessuna modifica alla scheda durante la scansione.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 18)
                case .ready: readyContent
                case .copying: copyingContent
                case .finished: finishedContent
                case .failed:
                    Label(draft.message ?? "Impossibile leggere la scheda.", systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange).textSelection(.enabled)
                    Button("Riprova la scansione") { model.rescan(draft.id) }
                }
            }
        }
        .confirmationDialog("Annullare lo scaricamento?", isPresented: $confirmingCancellation, titleVisibility: .visible) {
            Button("Annulla scaricamento", role: .destructive) { model.cancelCopy() }
            Button("Continua", role: .cancel) {}
        } message: { Text("I file già verificati restano salvati. Il file incompleto verrà rimosso; potrai riprendere senza ricopiare i file registrati.") }
    }
    private var subtitle: String {
        switch draft.phase {
        case .scanning: return "Scheda rilevata · scansione in corso"
        case .ready: return "Pronta per lo scaricamento"
        case .copying: return "Scaricamento in corso · non rimuovere la scheda"
        case .finished: return "Scaricamento terminato"
        case .failed: return "La scheda richiede attenzione"
        }
    }
    @ViewBuilder private var readyContent: some View {
        if let scan = draft.scan, !scan.folders.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CARTELLE DA SCARICARE").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                    Spacer()
                    Text("File / GB").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                ForEach(scan.folders) { folder in
                    FolderSelection(model: model, volume: draft.volume, folder: folder, selected: Binding(get: { draft.selected.contains(folder.id) }, set: { if $0 { draft.selected.insert(folder.id) } else { draft.selected.remove(folder.id) } }))
                }
                Text("Viene copiato l’intero contenuto delle cartelle selezionate, inclusi sottocartelle e file non multimediali. I percorsi di sistema sono esclusi.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 8) {
                Text("NOME CARTELLA TESSERA").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                TextField("Es. Matrimonio-Giorno1", text: $draft.folderName).textFieldStyle(.roundedBorder).controlSize(.large)
                if let session = model.activeSession {
                    Text("\(session.folderURL.path)/\(FolderNaming.sanitize(draft.folderName, volumeName: draft.volume.name))")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(2).truncationMode(.middle)
                }
                Text("Se il nome esiste già, M aggiunge un suffisso (2, 3…). Nessuna sovrascrittura.").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .center) {
                let selected = scan.folders.filter { draft.selected.contains($0.id) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(selected.flatMap(\.files).count) file · \(Theme.gb(selected.reduce(0) { $0 + $1.byteCount }))").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    Text(model.isCopying ? "Un altro scaricamento è in corso" : "Verifica di dimensione dopo ogni copia").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.startCopy(draft.id) } label: { Label("Scarica", systemImage: "arrow.down.to.line") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(draft.selected.isEmpty || model.activeSession == nil || model.isCopying)
                    .opacity(draft.selected.isEmpty || model.isCopying ? 0.45 : 1)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Nessun file multimediale trovato", systemImage: "doc.text.magnifyingglass").font(.headline)
                Text("Non ci sono foto, video o file WAV nelle cartelle leggibili di questa scheda. Nessun file è stato copiato.").font(.caption).foregroundStyle(.secondary)
                Button("Ripeti scansione") { model.rescan(draft.id) }
            }.padding(.vertical, 10)
        }
    }
    private var copyingContent: some View {
        let progress = model.progress
        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(progress.fraction * 100))%").font(.system(size: 36, weight: .light, design: .rounded)).monospacedDigit()
                Text("\(Theme.bytes(progress.processedBytes)) di \(Theme.bytes(progress.totalBytes))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text(String(format: "%.1f MB/s", progress.bytesPerSecond / 1_000_000)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(Theme.accent)
            }
            ProgressView(value: progress.fraction).tint(Theme.accent).accessibilityLabel("Progresso totale dello scaricamento")
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(progress.currentFile).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Text("File corrente: \(Theme.bytes(progress.currentFileBytes)) / \(Theme.bytes(progress.currentFileSize))").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 10)
                Button("Annulla", role: .destructive) { confirmingCancellation = true }.controlSize(.small)
            }
            HStack {
                Label("\(progress.fileCount) / \(progress.totalFiles) verificati", systemImage: "checkmark.shield").foregroundStyle(Theme.success)
                if progress.failedCount > 0 { Label("\(progress.failedCount) errori", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                Spacer()
                if progress.skippedCount > 0 { RedTag(count: progress.skippedCount) }
            }.font(.system(size: 10))
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz")
                Text("M mantiene il Mac sveglio fino alla fine dello scaricamento.")
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
    @ViewBuilder private var finishedContent: some View {
        if let card = model.card(draft.recordID) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 11) {
                    Image(systemName: card.status == .completata ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 27)).foregroundStyle(card.status == .completata ? Theme.success : .orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(card.status == .completata ? "Tutto al sicuro." : "Scaricamento da controllare.").font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text("\(card.fileCount) file copiati e verificati · \(Theme.bytes(card.copiedBytes))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if card.skippedCount > 0 { RedTag(count: card.skippedCount) }
                }
                if card.skippedCount > 0 {
                    Text("I file con tag rosso erano già nel registro di M e non sono stati ricopiati. Il registro vale per tutte le sessioni.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                }
                if !card.errors.isEmpty {
                    Text(card.errors.prefix(3).joined(separator: "\n")).font(.caption).foregroundStyle(.orange).lineLimit(5).textSelection(.enabled)
                }
                HStack {
                    Button { model.eject(draft.volume) } label: { Label("Espelli in sicurezza", systemImage: "eject.fill") }.buttonStyle(PrimaryButtonStyle())
                    Button("Apri cartella") { model.reveal(card.destPath) }
                    Spacer(minLength: 0)
                    Button("Nuovo controllo") { model.rescan(draft.id) }.font(.caption).buttonStyle(.borderless)
                }
            }.padding(.top, 2)
        }
    }
}

struct FolderSelection: View {
    @ObservedObject var model: AppModel
    let volume: MountedCard
    let folder: MediaFolder
    @Binding var selected: Bool
    @State private var showingFiles = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle(isOn: $selected) {
                    Label(folder.displayName, systemImage: folder.relativePath.isEmpty ? "sdcard" : "folder.fill").font(.system(size: 12, weight: .semibold))
                }.toggleStyle(.checkbox)
                Spacer(minLength: 10)
                Text("\(folder.files.count) file · \(Theme.gb(folder.byteCount))").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                Button { showingFiles.toggle() } label: { Image(systemName: showingFiles ? "chevron.up" : "chevron.down").font(.system(size: 10)) }.buttonStyle(.borderless).accessibilityLabel(showingFiles ? "Nascondi i file" : "Mostra i file")
            }
            let skipped = model.skipped(in: folder, volume: volume)
            HStack {
                Text("\(folder.mediaCount) media · inclusi tutti i file di supporto").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                if skipped > 0 { RedTag(count: skipped) }
            }
            if showingFiles {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(folder.files) { file in
                            HStack(spacing: 8) {
                                let copied = model.alreadyCopied(file, volume: volume)
                                Image(systemName: copied ? "circle.fill" : "doc").font(.system(size: copied ? 7 : 10)).foregroundStyle(copied ? Theme.accent : .secondary).frame(width: 12)
                                Text(file.relativePath).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if copied { Text("già scaricato").font(.system(size: 9)).foregroundStyle(Theme.accent) }
                                Text(Theme.bytes(file.size)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.accessibilityElement(children: .combine)
                        }
                    }.padding(.vertical, 4)
                }.frame(maxHeight: 220)
            }
        }.padding(13).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
