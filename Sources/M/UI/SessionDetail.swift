import SwiftUI

struct SessionDetail: View {
    @ObservedObject var model: AppModel
    let session: SessionRecord
    @State private var showDeleteConfirm = false
    var cards: [CardRecord] { model.cards(for: session) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                HStack(spacing: 12) {
                    Surface(padding: 16) { Metric(title: "Tessere nella sessione", value: "\(cards.count)", symbol: "sdcard") }
                    Surface(padding: 16) { Metric(title: "Copiati e verificati", value: Theme.gb(cards.reduce(0) { $0 + $1.copiedBytes }), symbol: "checkmark.shield") }
                    Surface(padding: 16) { Metric(title: "File al sicuro", value: "\(cards.reduce(0) { $0 + $1.fileCount })", symbol: "doc.on.doc") }
                }
                if session.isArchived {
                    Surface(padding: 18) {
                        HStack(spacing: 14) {
                            Image(systemName: "archivebox.fill").font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sessione in archivio").font(.subheadline.weight(.semibold))
                                Text("Storico e report restano consultabili. Premi «Riattiva» per tornare a scaricarci le tessere.").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                } else if model.drafts.isEmpty { WaitingCard() }
                else {
                    ForEach($model.drafts) { $draft in
                        if draft.phase != .copying || model.card(draft.recordID)?.sessionID == session.id {
                            CardPanel(model: model, draft: $draft)
                        }
                    }
                }
                HStack {
                    Text("TESSERE SCARICATE").font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(cards.count)").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 6)
                if cards.isEmpty {
                    Surface {
                        HStack(spacing: 17) {
                            Image(systemName: "tray").font(.system(size: 29, weight: .ultraLight)).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Qui comincia la tua raccolta.").font(.subheadline.weight(.medium))
                                Text("Dopo ogni scaricamento troverai qui stato, destinazione e report.").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 10)
                    }
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(cards) { card in CardHistoryRow(model: model, card: card) }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                    Text("La sorgente non viene mai cancellata. Verifica per dimensione, non checksum.")
                }.font(.system(size: 10)).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.top, 6)
            }.padding(.horizontal, 30).padding(.top, 12).padding(.bottom, 35)
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(session.name).font(.system(size: 31, weight: .semibold, design: .rounded)).tracking(-0.7).textSelection(.enabled)
                    Button { model.reveal(session.folderURL.path) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text(session.folderURL.path).lineLimit(1).truncationMode(.middle)
                            Image(systemName: "arrow.up.right").font(.system(size: 8))
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help("Mostra la destinazione nel Finder")
                }
                Spacer(minLength: 16)
                HStack(spacing: 10) {
                    Button { model.report(session) } label: { Label("Report", systemImage: "doc.text") }.controlSize(.large).help("Esporta il report Markdown nella destinazione e mostralo nel Finder")
                    if session.isArchived {
                        Button { model.restoreSession(session) } label: { Label("Riattiva", systemImage: "arrow.counterclockwise.circle") }.controlSize(.large).help("Riporta la sessione attiva: potrà scaricare nuove tessere")
                        Button { showDeleteConfirm = true } label: { Label("Elimina sessione", systemImage: "trash") }.controlSize(.large).tint(.red)
                            .alert("Eliminare «\(session.name)» da M?", isPresented: $showDeleteConfirm) {
                                Button("Elimina", role: .destructive) { model.deleteSession(session) }
                                Button("Annulla", role: .cancel) { }
                            } message: {
                                Text("Vengono rimossi i registri di M (sessione e tessere). I file su disco NON vengono eliminati e quelli già scaricati non verranno ricopiati in altre sessioni.")
                            }
                    } else {
                        Button { model.prepareCapCutProject(session) } label: { Label("Apri CapCut", systemImage: "film") }.controlSize(.large).help("Prepara Asset/Audio/Exports nella cartella sessione, copia il nome del progetto negli appunti e apre CapCut. In CapCut: nuovo progetto → incolla il nome → importa dalla cartella Asset/Audio (il materiale conta così com'è adesso, anche se l'hai spostato a mano)")
                        Button { model.endSession(session) } label: { Label("Fine sessione", systemImage: "archivebox") }.controlSize(.large).help("Chiude la sessione: report nella cartella della sessione e archiviazione")
                    }
                }
            }
        }
    }
}

struct WaitingCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View {
        Surface(padding: 27) {
            HStack(spacing: 24) {
                ZStack {
                    Circle().stroke(Theme.accent.opacity(0.14), lineWidth: 1).frame(width: 83, height: 83).scaleEffect(pulse ? 1.08 : 0.9).opacity(pulse ? 0.5 : 1)
                    RoundedRectangle(cornerRadius: 18).fill(Theme.accent.opacity(0.09)).frame(width: 65, height: 65)
                    Image(systemName: "sdcard").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Inserisci una scheda").font(.system(size: 19, weight: .semibold, design: .rounded))
                        Circle().fill(Theme.success).frame(width: 6, height: 6).opacity(pulse ? 1 : 0.4)
                    }
                    Text("SD, CFexpress, XQD… M la riconosce automaticamente.\nScegli le cartelle e dai un nome alla tessera prima di scaricare.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Text("IN ATTESA DI UNA SCHEDA").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.3).foregroundStyle(.tertiary).padding(.top, 3)
                }
                Spacer(minLength: 0)
            }
        }.onAppear {
            if !reduceMotion { withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) { pulse = true } }
        }
    }
}

struct CardHistoryRow: View {
    @ObservedObject var model: AppModel
    let card: CardRecord
    @State private var expanded = false
    var body: some View {
        Surface(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "sdcard.fill").font(.system(size: 23, weight: .light)).foregroundStyle(card.status == .completata ? Theme.success : .secondary)
                        .frame(width: 40, height: 43).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(card.folderName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            StatusBadge(status: card.status)
                        }
                        Text(card.destPath).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(card.destPath)
                        HStack(spacing: 12) {
                            Label(card.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            Text("\(card.fileCount) file · \(Theme.bytes(card.copiedBytes))")
                            if let end = card.finishedAt { Text("\(Int(max(0, end.timeIntervalSince(card.startedAt)))) s") }
                        }.font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 9) {
                        if card.skippedCount > 0 { RedTag(count: card.skippedCount) }
                        HStack(spacing: 12) {
                            Button { model.reveal(card.destPath) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Mostra nel Finder")
                            if let volume = model.volume(for: card), card.status != .inCorso {
                                Button { model.eject(volume) } label: { Image(systemName: "eject") }.buttonStyle(.borderless).help("Espelli in sicurezza").disabled(model.isCopying && model.card(model.activeCopyID)?.volumeUUID == card.volumeUUID)
                            }
                        }
                    }
                }
                if !card.errors.isEmpty {
                    DisclosureGroup(isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(card.errors.enumerated()), id: \.offset) { _, text in Text(text).font(.caption).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    } label: { Label("\(card.errors.count) segnalazioni", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                }
            }
        }
    }
}
