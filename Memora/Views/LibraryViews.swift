import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct MainTabs: View {
    @ObservedObject var store: MemoryStore
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView(store: store, selection: $selection) }
                .tabItem { Label("Inicio", systemImage: "house") }.tag(0)
            NavigationStack { LibraryView(store: store) }
                .tabItem { Label("Biblioteca", systemImage: "square.on.square") }.tag(1)
            NavigationStack { PeopleView(store: store) }
                .tabItem { Label("Personas", systemImage: "person.2") }.tag(2)
            NavigationStack { SearchView(store: store) }
                .tabItem { Label("Buscar", systemImage: "magnifyingglass") }.tag(3)
            NavigationStack { ProfileView(store: store) }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }.tag(4)
        }
        .toolbarBackground(MemoraStyle.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .memoraPage()
    }
}

struct ImportActions: View {
    @ObservedObject var store: MemoryStore
    var secure = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingFiles = false

    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20,
                         matching: .any(of: [.images, .videos])) {
                Label("Fotos y videos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(MemoraButtonStyle(prominent: true))
            Button { showingFiles = true } label: {
                Label("Archivos", systemImage: "doc.badge.plus")
            }
            .buttonStyle(MemoraButtonStyle())
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await store.importPhotoItems(items, secure: secure)
                selectedPhotos = []
            }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): store.importURLs(urls, secure: secure)
            case .failure(let error): store.notice = error.localizedDescription
            }
        }
    }
}

struct HomeView: View {
    @ObservedObject var store: MemoryStore
    @Binding var selection: Int

    private var recent: [MemoryAsset] {
        Array(store.activeAssets.sorted { $0.addedAt > $1.addedAt }.prefix(12))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MemoraHeader(title: "Memora", subtitle: "Tu biblioteca privada")
                HStack(spacing: 8) {
                    StatTile(symbol: "photo", title: "Fotos", value: "\(store.activeAssets.filter { $0.kind == .photo }.count)")
                    StatTile(symbol: "video", title: "Videos", value: "\(store.activeAssets.filter { $0.kind == .video }.count)")
                    StatTile(symbol: "person.2", title: "Personas", value: "\(store.library.people.count)")
                }
                ImportActions(store: store)

                SectionHeading(title: "Álbumes recientes")
                if store.library.albums.isEmpty {
                    EmptyMemory(symbol: "rectangle.stack", title: "Todavía no hay álbumes",
                                message: "Crea uno desde Biblioteca para organizar tus recuerdos.")
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 11) {
                            ForEach(store.library.albums.sorted { $0.createdAt > $1.createdAt }.prefix(5)) { album in
                                NavigationLink {
                                    AlbumDetailView(store: store, album: album)
                                } label: {
                                    AlbumTile(store: store, album: album)
                                        .frame(width: 148)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                SectionHeading(title: "Recientes")
                if recent.isEmpty {
                    EmptyMemory(symbol: "photo.on.rectangle.angled", title: "Aquí empieza tu historia",
                                message: "Importa tus primeros archivos. No hay contenido de muestra.")
                } else {
                    AssetGrid(store: store, assets: recent)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .toolbar(.hidden, for: .navigationBar)
        .memoraPage()
    }
}

struct LibraryView: View {
    @ObservedObject var store: MemoryStore
    @State private var filter: AssetKind?
    @State private var albumName = ""
    @State private var sectionName = ""
    @State private var addingAlbum = false
    @State private var addingSection = false

    private var assets: [MemoryAsset] {
        store.activeAssets.filter { filter == nil || $0.kind == filter }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                MemoraHeader(title: "Biblioteca", subtitle: "Organiza y explora tus recuerdos")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        filterChip("Todo", selected: filter == nil) { filter = nil }
                        ForEach(AssetKind.allCases, id: \.self) { kind in
                            filterChip(kind.label, selected: filter == kind) { filter = kind }
                        }
                    }
                }
                ImportActions(store: store)
                HStack {
                    SectionHeading(title: "Álbumes")
                    Button { addingAlbum = true } label: { Image(systemName: "plus.circle") }
                        .accessibilityLabel("Nuevo álbum")
                }
                if store.library.albums.isEmpty {
                    EmptyMemory(symbol: "rectangle.stack", title: "Tus álbumes aparecerán aquí",
                                message: "Un archivo puede estar en varios álbumes sin copiarlo.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(store.library.albums) { album in
                            NavigationLink {
                                AlbumDetailView(store: store, album: album)
                            } label: { AlbumTile(store: store, album: album) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    SectionHeading(title: "Secciones")
                    Button { addingSection = true } label: { Image(systemName: "plus.circle") }
                        .accessibilityLabel("Nueva sección")
                }
                ForEach(store.library.sections) { section in
                    Panel {
                        Label(section.name, systemImage: section.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                SectionHeading(title: filter?.label ?? "Todos los archivos")
                if assets.isEmpty {
                    EmptyMemory(symbol: "square.grid.2x2", title: "Sin archivos todavía",
                                message: "Importa fotos, videos, audio o documentos para llenar tu biblioteca.")
                } else { AssetGrid(store: store, assets: assets) }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .alert("Nuevo álbum", isPresented: $addingAlbum) {
            TextField("Nombre", text: $albumName)
            Button("Crear") {
                do { try store.createAlbum(albumName); albumName = "" }
                catch { store.notice = error.localizedDescription }
            }
            Button("Cancelar", role: .cancel) { albumName = "" }
        }
        .alert("Nueva sección", isPresented: $addingSection) {
            TextField("Nombre", text: $sectionName)
            Button("Crear") {
                do { try store.createSection(sectionName); sectionName = "" }
                catch { store.notice = error.localizedDescription }
            }
            Button("Cancelar", role: .cancel) { sectionName = "" }
        }
        .toolbar(.hidden, for: .navigationBar)
        .memoraPage()
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.subheadline).padding(.horizontal, 18).padding(.vertical, 10) }
            .foregroundStyle(selected ? MemoraStyle.background : .white)
            .background(selected ? MemoraStyle.cream : MemoraStyle.raised, in: Capsule())
    }
}

struct AlbumTile: View {
    @ObservedObject var store: MemoryStore
    let album: MemoryAlbum

    private var contents: [MemoryAsset] {
        store.activeAssets.filter { $0.albumIDs.contains(album.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let asset = contents.first {
                MemoryCard(asset: asset, image: store.thumbnail(for: asset))
            } else {
                RoundedRectangle(cornerRadius: 13).fill(MemoraStyle.raised)
                    .overlay(Image(systemName: "rectangle.stack").font(.largeTitle).foregroundStyle(MemoraStyle.muted))
                    .aspectRatio(1, contentMode: .fit)
            }
            Text(album.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
            Text("\(contents.count) elementos").font(.caption).foregroundStyle(MemoraStyle.muted)
        }
    }
}

struct AssetGrid: View {
    @ObservedObject var store: MemoryStore
    let assets: [MemoryAsset]
    var secure = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
            ForEach(assets) { asset in
                NavigationLink {
                    AssetDetailView(store: store, assetID: asset.id, secure: secure)
                } label: {
                    MemoryCard(asset: asset, image: store.thumbnail(for: asset, secure: secure))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AlbumDetailView: View {
    @ObservedObject var store: MemoryStore
    let album: MemoryAlbum
    var secure = false

    private var assets: [MemoryAsset] {
        (secure ? store.privateLibrary?.assets ?? [] : store.activeAssets)
            .filter { $0.albumIDs.contains(album.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: album.name, subtitle: "\(assets.count) elementos")
                if assets.isEmpty {
                    EmptyMemory(symbol: "photo.stack", title: "Álbum vacío",
                                message: "Abre un archivo y asígnalo a este álbum.")
                } else { AssetGrid(store: store, assets: assets, secure: secure) }
            }
            .padding(18)
        }
        .navigationBarTitleDisplayMode(.inline)
        .memoraPage()
    }
}

struct AssetDetailView: View {
    @ObservedObject var store: MemoryStore
    let assetID: UUID
    var secure = false
    @State private var temporary: URL?
    @State private var showingPreview = false
    @State private var showingShare = false

    private var asset: MemoryAsset? {
        if secure {
            return store.privateLibrary?.assets.first { $0.id == assetID }
        }
        return store.library.assets.first { $0.id == assetID }
    }

    var body: some View {
        ScrollView {
            if let asset {
                VStack(alignment: .leading, spacing: 17) {
                    if let image = store.thumbnail(for: asset, secure: secure) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity).frame(maxHeight: 480)
                            .background(MemoraStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        EmptyMemory(symbol: asset.kind.symbol, title: asset.name,
                                    message: "Archivo original cifrado en este iPhone.")
                    }
                    Text(asset.name).font(MemoraStyle.title(25))
                    Text("\(asset.size.memorySize) · \(asset.addedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(MemoraStyle.muted)
                    VStack(spacing: 10) {
                        Button {
                            do {
                                temporary = try store.temporaryOriginal(for: asset, secure: secure)
                                showingPreview = true
                            } catch { store.notice = error.localizedDescription }
                        } label: {
                            Label("Abrir original", systemImage: "doc.viewfinder")
                        }
                        .buttonStyle(MemoraButtonStyle(prominent: true))
                        Button {
                            do {
                                temporary = try store.temporaryOriginal(for: asset, secure: secure)
                                showingShare = true
                            } catch { store.notice = error.localizedDescription }
                        } label: {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(MemoraButtonStyle())
                    }
                    if !secure {
                        VStack(spacing: 10) {
                            Button {
                                do { try store.toggleFavorite(asset.id) }
                                catch { store.notice = error.localizedDescription }
                            } label: {
                                Label(asset.favorite ? "Quitar favorito" : "Favorito", systemImage: asset.favorite ? "heart.slash" : "heart")
                            }
                            .buttonStyle(MemoraButtonStyle())
                            Menu("Añadir a álbum") {
                                ForEach(store.library.albums) { album in
                                    Button(album.name) {
                                        do { try store.add(asset.id, to: album.id) }
                                        catch { store.notice = error.localizedDescription }
                                    }
                                }
                            }
                            .buttonStyle(MemoraButtonStyle())
                        }
                        Menu("Asignar persona") {
                            ForEach(store.library.people) { person in
                                Button(person.name) {
                                    do { try store.assign(asset.id, to: person.id) }
                                    catch { store.notice = error.localizedDescription }
                                }
                            }
                        }
                        .buttonStyle(MemoraButtonStyle())
                        Button("Mover a Papelera", role: .destructive) {
                            do { try store.moveToTrash(asset.id) }
                            catch { store.notice = error.localizedDescription }
                        }
                        .foregroundStyle(.red)
                    }
                }
                .padding(18)
            }
        }
        .sheet(isPresented: $showingPreview, onDismiss: cleanup) {
            if let temporary { FilePreview(url: temporary) }
        }
        .sheet(isPresented: $showingShare, onDismiss: cleanup) {
            if let temporary { FileShareSheet(url: temporary) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .memoraPage()
    }

    private func cleanup() {
        if let temporary { store.removeTemporary(temporary) }
        temporary = nil
    }
}

private struct FilePreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct FileShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct PeopleView: View {
    @ObservedObject var store: MemoryStore
    @State private var name = ""
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: "Personas", subtitle: "Las personas que forman tu historia")
                Button { adding = true } label: { Label("Añadir persona", systemImage: "plus") }
                    .buttonStyle(MemoraButtonStyle(prominent: true))
                if store.library.people.isEmpty {
                    EmptyMemory(symbol: "person.2", title: "Ponle nombre a tus recuerdos",
                                message: "Crea personas y asígnalas manualmente. El reconocimiento facial aún no está integrado.")
                }
                ForEach(store.library.people) { person in
                    NavigationLink {
                        PersonDetailView(store: store, person: person)
                    } label: {
                        Panel {
                            HStack(spacing: 14) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 39, weight: .ultraLight))
                                VStack(alignment: .leading) {
                                    Text(person.name).font(MemoraStyle.title(23))
                                    Text("\(store.activeAssets.filter { $0.personIDs.contains(person.id) }.count) archivos")
                                        .font(.caption).foregroundStyle(MemoraStyle.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .alert("Añadir persona", isPresented: $adding) {
            TextField("Nombre", text: $name)
            Button("Guardar") {
                do { try store.createPerson(name); name = "" }
                catch { store.notice = error.localizedDescription }
            }
            Button("Cancelar", role: .cancel) { name = "" }
        }
        .toolbar(.hidden, for: .navigationBar)
        .memoraPage()
    }
}

struct PersonDetailView: View {
    @ObservedObject var store: MemoryStore
    let person: MemoryPerson

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: person.name, subtitle: "Recuerdos etiquetados")
                Menu("Combinar con otra persona") {
                    ForEach(store.library.people.filter { $0.id != person.id }) { target in
                        Button("Combinar en \(target.name)") {
                            do { try store.mergePeople(source: person.id, into: target.id) }
                            catch { store.notice = error.localizedDescription }
                        }
                    }
                }
                .buttonStyle(MemoraButtonStyle())
                let assets = store.activeAssets.filter { $0.personIDs.contains(person.id) }
                if assets.isEmpty {
                    EmptyMemory(symbol: "person.crop.rectangle", title: "Sin archivos asignados",
                                message: "Abre un archivo y selecciona esta persona.")
                } else { AssetGrid(store: store, assets: assets) }
            }
            .padding(18)
        }
        .memoraPage()
    }
}

struct SearchView: View {
    @ObservedObject var store: MemoryStore
    @State private var query = ""

    private var results: [MemoryAsset] {
        let words = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return store.activeAssets.filter { asset in
            let albums = store.library.albums.filter { asset.albumIDs.contains($0.id) }.map(\.name)
            let people = store.library.people.filter { asset.personIDs.contains($0.id) }.map(\.name)
            let text = ([asset.name, asset.location, asset.kind.label] + asset.tags + albums + people)
                .joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return words.allSatisfy(text.contains)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                MemoraHeader(title: "Buscar", subtitle: "Encuentra personas, lugares y momentos")
                TextField("Buscar en tu biblioteca…", text: $query)
                    .textFieldStyle(.roundedBorder)
                Panel {
                    MemoryRow(symbol: "faceid", title: "Buscar mediante fotografía",
                              detail: "Disponible tras integrar reconocimiento local")
                }
                if query.isEmpty {
                    EmptyMemory(symbol: "magnifyingglass", title: "Tu biblioteca, a un toque",
                                message: "Busca por nombre, álbum, persona, etiqueta o tipo de archivo.")
                } else if results.isEmpty {
                    EmptyMemory(symbol: "magnifyingglass", title: "Sin coincidencias",
                                message: "Prueba con otro nombre o etiqueta.")
                } else {
                    SectionHeading(title: "Resultados")
                    AssetGrid(store: store, assets: results)
                }
            }
            .padding(18)
        }
        .toolbar(.hidden, for: .navigationBar)
        .memoraPage()
    }
}
