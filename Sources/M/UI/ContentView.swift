import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Binding var appearance: String
    @State private var showingNewSession = false
    @State private var sessionToDelete: SessionRecord?
    private var archivedSessions: [SessionRecord] { model.store.sessions.filter { $0.isArchived } }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 260)
            Rectangle().fill(.primary.opacity(0.08)).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                if let notice = model.notice {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                        Text(notice).font(.caption)
                        Spacer()
                        Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Chiudi avviso")
                    }.padding(14).background(.orange.opacity(0.10))
                }
                if model.isCopying, let record = model.card(model.activeCopyID), record.sessionID != model.selectedSessionID {
                    Button { model.selectedSessionID = record.sessionID } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Scaricamento in corso · \(record.folderName)")
                            Spacer()
                            Text("Vai alla sessione").fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                        }.font(.caption).padding(14).background(Theme.accent.opacity(0.12))
                    }.buttonStyle(.plain)
                }
                if let session = model.activeSession { SessionDetail(model: model, session: session) }
                else { noSession }
            }
        }
        .background {
            ZStack(alignment: .topTrailing) {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(colors: [Theme.accent.opacity(0.11), .clear], center: .topTrailing, startRadius: 10, endRadius: 650)
            }.ignoresSafeArea()
        }
        .sheet(isPresented: $showingNewSession) { NewSessionView(model: model) }
        .alert(sessionToDelete.map { "Eliminare «\($0.name)» da M?" } ?? "", isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } })) {
            Button("Elimina", role: .destructive) { if let session = sessionToDelete { model.deleteSession(session) }; sessionToDelete = nil }
            Button("Annulla", role: .cancel) { sessionToDelete = nil }
        } message: {
            Text("Vengono rimossi i registri di M (sessione e tessere). I file su disco NON vengono eliminati e quelli già scaricati non verranno ricopiati in altre sessioni.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newMSession)) { _ in showingNewSession = true }
        .alert("M · Attenzione", isPresented: Binding(get: { !showingNewSession && model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("Ho capito", role: .cancel) { model.errorText = nil }
        } message: { Text(model.errorText ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("M").font(.system(size: 29, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 47, height: 47).background(LinearGradient(colors: [Theme.accent, Color(red: 0.32, green: 0.04, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("M").font(.headline)
                    Text("SCARICO SCHEDE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 21).padding(.top, 32).padding(.bottom, 30)
            HStack {
                Text("SESSIONI").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.store.sessions.count)").font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(model.store.sessions.filter { !$0.isArchived }) { session in
                        sessionButton(session, archived: false)
                    }
                    if model.store.sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Si parte da una sessione.").font(.subheadline.weight(.medium))
                            Text("Scegli dove raccogliere le tue schede. Al resto pensa M.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }
                    if !archivedSessions.isEmpty {
                        HStack {
                            Text("ARCHIVIO").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(archivedSessions.count)").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }.padding(.horizontal, 4).padding(.top, 14).padding(.bottom, 2)
                        ForEach(archivedSessions) { session in
                            sessionButton(session, archived: true)
                        }
                    }
                }.padding(.horizontal, 12)
            }
            Button { showingNewSession = true } label: { Label("Nuova sessione", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle()).padding(16)
                .keyboardShortcut("n", modifiers: .command)
            HStack(spacing: 6) {
                Circle().fill(Theme.success).frame(width: 5, height: 5)
                Text("Tutto locale. Nessun cloud.").font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.bottom, 20)
        }.background(.ultraThinMaterial)
    }
    private func sessionButton(_ session: SessionRecord, archived: Bool) -> some View {
        let selected = model.selectedSessionID == session.id
        let cards = model.cards(for: session)
        return ZStack(alignment: .topTrailing) {
            Button { model.selectedSessionID = session.id } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: archived ? "archivebox.fill" : "square.stack.3d.up.fill").foregroundStyle(selected ? Theme.accent : .secondary)
                        Text(session.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).foregroundStyle(archived ? .secondary : .primary)
                        Spacer(minLength: 0)
                        if selected { Circle().fill(Theme.accent).frame(width: 6, height: 6) }
                    }
                    Text(session.destinationPath).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Text("\(cards.count) tessere  ·  \(Theme.gb(cards.reduce(0) { $0 + $1.copiedBytes }))")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                    .background(selected ? Theme.accent.opacity(0.10) : Color.primary.opacity(archived ? 0.015 : 0.025), in: RoundedRectangle(cornerRadius: 13))
                    .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? Theme.accent.opacity(0.4) : .clear, lineWidth: 1) }
                    .contentShape(RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain).help(session.destinationPath)
            if archived {
                Button { sessionToDelete = session } label: {
                    Image(systemName: "trash").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(7).background(.thinMaterial, in: Circle())
                }.buttonStyle(.plain).help("Elimina la sessione da M (i file su disco restano)")
                    .padding(6)
            }
        }
    }
    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(model.activeSession == nil ? .orange : model.activeSession?.isArchived == true ? .secondary : Theme.success).frame(width: 6, height: 6)
                Text(model.activeSession == nil ? "Nessuna sessione attiva" : model.activeSession?.isArchived == true ? "Sessione in archivio" : "Sessione attiva").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.activeSession != nil {
                Button { model.selectedSessionID = nil } label: { Image(systemName: "power") }.help("Disattiva la sessione (le nuove schede non verranno scaricate)")
                    .buttonStyle(.borderless)
            }
            Menu {
                Picker("Aspetto", selection: $appearance) {
                    Text("Scuro").tag("dark")
                    Text("Chiaro").tag("light")
                    Text("Come il sistema").tag("system")
                }
            } label: { Image(systemName: "circle.lefthalf.filled") }.menuStyle(.borderlessButton).fixedSize().help("Aspetto")
        }.padding(.horizontal, 30).padding(.top, 28).padding(.bottom, 15)
    }
    private var noSession: some View {
        ScrollView {
            VStack(spacing: 23) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30).fill(Theme.accent.opacity(0.09)).frame(width: 118, height: 118).rotationEffect(.degrees(-8))
                    Image(systemName: "sdcard.fill").font(.system(size: 55, weight: .light)).foregroundStyle(Theme.accent)
                }.padding(.top, 60)
                VStack(spacing: 10) {
                    Text("Ogni scheda,\nal posto giusto.").font(.system(size: 38, weight: .semibold, design: .rounded)).multilineTextAlignment(.center).tracking(-1)
                    Text("Crea una sessione, inserisci una scheda.\nM copia, verifica e ricorda ciò che hai già scaricato.")
                        .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                }
                Button { showingNewSession = true } label: { Label(model.store.sessions.isEmpty ? "Crea la tua prima sessione" : "Crea una nuova sessione", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
                HStack(spacing: 22) {
                    Label("Copia integrale", systemImage: "folder")
                    Label("Verifica dimensione", systemImage: "checkmark.shield")
                    Label("Zero doppioni", systemImage: "circle.fill")
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 10)
                if !model.drafts.isEmpty {
                    Surface {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Nessuna sessione attiva", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.headline)
                            Text("\(model.drafts.count) schede rilevate. Nessun file verrà copiato finché non selezioni una sessione.").font(.caption).foregroundStyle(.secondary)
                            ForEach(model.drafts) { draft in
                                HStack {
                                    Label(draft.volume.name, systemImage: "sdcard")
                                    Spacer()
                                    Button("Espelli in sicurezza") { model.eject(draft.volume) }.disabled(model.isCopying && model.card(model.activeCopyID)?.volumeUUID == draft.volume.volumeUUID)
                                }.font(.caption)
                            }
                        }
                    }.padding(.horizontal, 36).padding(.top, 15)
                }
                Spacer(minLength: 36)
            }.frame(maxWidth: .infinity)
        }
    }
}

struct NewSessionView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var destination: URL?
    @State private var volumes: [VolumeRow] = []
    @FocusState private var nameFocused: Bool
    struct VolumeRow: Identifiable {
        let url: URL
        let name: String
        let isInternal: Bool
        var id: String { url.path }
    }
    /// V4 ruling: pick the destination volume directly from the mounted list.
    static func mountedVolumeRows() -> [VolumeRow] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey]
        let rows = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: .skipHiddenVolumes) ?? []).compactMap { url -> VolumeRow? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return VolumeRow(url: url, name: values.volumeName ?? url.lastPathComponent, isInternal: values.volumeIsInternal == true)
        }
        // External volumes first (the photographer's card destinations), then internal.
        return rows.sorted { ($0.isInternal ? 1 : 0, $0.name.lowercased()) < ($1.isInternal ? 1 : 0, $1.name.lowercased()) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "folder.badge.plus").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 7) {
                Text("Una nuova sessione.").font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Un progetto, un viaggio, una giornata. Tutte le schede nello stesso posto.").font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("NOME SESSIONE").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                TextField("Es. Dolomiti · Novembre", text: $name).textFieldStyle(.roundedBorder).controlSize(.large).focused($nameFocused)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("VOLUMI MONTATI").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    Spacer()
                    Button { volumes = Self.mountedVolumeRows() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help("Aggiorna la lista dei volumi")
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(volumes) { volume in
                            let selected = destination == volume.url
                            Button { destination = volume.url } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                                        .foregroundStyle(volume.isInternal ? Color.secondary : Theme.accent)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(volume.name).font(.system(size: 12, weight: .medium))
                                        Text(volume.url.path).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                                }
                                .padding(.horizontal, 11).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected ? Theme.accent.opacity(0.10) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
                                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Theme.accent.opacity(0.45) : .clear, lineWidth: 1) }
                                .contentShape(RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 132)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("CARTELLA DI DESTINAZIONE").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill").font(.title2).foregroundStyle(Theme.accent)
                    Text(destination?.path ?? "Scegli un volume o una cartella contenitrice").font(.caption).foregroundStyle(destination == nil ? .secondary : .primary).lineLimit(2).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Scegli…", action: chooseDestination)
                }.padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                Text("Dentro la cartella scelta, M crea la cartella «\(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "nome-sessione" : name.trimmingCharacters(in: .whitespacesAndNewlines))» e ci mette le tessere e il report.").font(.caption2).foregroundStyle(.secondary).lineSpacing(2)
            }
            Text("La sessione selezionata sarà quella attiva. Puoi cambiarla in qualsiasi momento dalla barra laterale.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            HStack {
                Button("Annulla", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Crea sessione") {
                    if let destination {
                        model.createSession(name: name, destination: destination)
                        if model.errorText == nil { dismiss() }
                    }
                }.buttonStyle(PrimaryButtonStyle()).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || destination == nil).keyboardShortcut(.defaultAction)
            }
        }.padding(32).frame(width: 480).onAppear { nameFocused = true; volumes = Self.mountedVolumeRows() }
        .alert("Impossibile creare la sessione", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("Ho capito", role: .cancel) { model.errorText = nil }
        } message: { Text(model.errorText ?? "") }
    }
    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Destinazione della sessione"
        panel.prompt = "Scegli destinazione"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK { destination = panel.url }
        }
    }
}
