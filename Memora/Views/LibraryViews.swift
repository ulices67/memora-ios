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
        HStack(spacing: 8) {
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20,
                         matching: .any(of: [.images, .videos])) {
                Label("Fotos y videos", systemImage: "photo.on.rectangle")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(MemoraButtonStyle(prominent: true))

            Button { showingFiles = true } label: {
                Label("Archivos", systemImage: "doc.badge.plus")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                HStack(spacing: 7) {
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 11) {
                            ForEach(store.library.albums.sorted { $0.createdAt > $1.createdAt }.prefix(5)) { album in
                                NavigationLink {
                                    AlbumDetailView(store: store, album: album)
                                } label: {
                                    AlbumTile(store: store, album: album)
                                        .frame(width: 144)
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
            .padding(.horizontal, MemoraStyle.pagePadding)
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
                ScrollView(.horizontal, showsIndicators: false) {
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
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
                if store.library.sections.isEmpty {
                    EmptyMemory(symbol: "folder.badge.plus", title: "Organiza por secciones",
                                message: "Crea carpetas maestras (Amigos, Viajes, Familia). Mantén presionado para abrir sus álbumes.")
                } else {
                    ForEach(store.library.sections) { section in
                        SectionRowView(store: store, section: section)
                    }
                }
                SectionHeading(title: filter?.label ?? "Todos los archivos")
                if assets.isEmpty {
                    EmptyMemory(symbol: "square.grid.2x2", title: "Sin archivos todavía",
                                message: "Importa fotos, videos, audio o documentos para llenar tu biblioteca.")
                } else { AssetGrid(store: store, assets: assets) }
            }
            .padding(.horizontal, MemoraStyle.pagePadding)
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
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .foregroundStyle(selected ? MemoraStyle.background : .white)
        .background(selected ? MemoraStyle.cream : MemoraStyle.raised, in: Capsule())
    }
}

struct AlbumTile: View {
    @ObservedObject var store: MemoryStore
    let album: MemoryAlbum
    @State private var isTargeted = false

    private var contents: [MemoryAsset] {
        store.activeAssets.filter { $0.albumIDs.contains(album.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let asset = contents.first {
                MemoryCard(asset: asset, image: store.thumbnail(for: asset))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(MemoraStyle.raised)
                    .overlay(Image(systemName: "rectangle.stack").font(.title).foregroundStyle(MemoraStyle.muted))
                    .aspectRatio(1, contentMode: .fit)
            }
            Text(album.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text("\(contents.count) elementos")
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(MemoraStyle.muted)
        }
        .padding(4)
        .background(isTargeted ? MemoraStyle.cream.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        .draggable(album.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            for item in items {
                if let assetID = UUID(uuidString: item) {
                    try? store.addAssets([assetID], toAlbum: album.id)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}

struct AssetGrid: View {
    @ObservedObject var store: MemoryStore
    let assets: [MemoryAsset]
    var secure = false

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 6)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(assets) { asset in
                NavigationLink {
                    AssetDetailView(store: store, assetID: asset.id, secure: secure)
                } label: {
                    MemoryCard(asset: asset, image: store.thumbnail(for: asset, secure: secure))
                }
                .buttonStyle(.plain)
                .draggable(asset.id.uuidString)
            }
        }
    }
}

struct AlbumDetailView: View {
    @ObservedObject var store: MemoryStore
    let album: MemoryAlbum
    var secure = false
    @State private var showingAddPhotos = false
    @State private var isDropTargeted = false

    private var assets: [MemoryAsset] {
        (secure ? store.privateLibrary?.assets ?? [] : store.activeAssets)
            .filter { $0.albumIDs.contains(album.id) }
    }

    private var availableAssets: [MemoryAsset] {
        store.activeAssets.filter { !$0.albumIDs.contains(album.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: album.name, subtitle: "\(assets.count) elementos · Arrastra fotos aquí")

                HStack(spacing: 8) {
                    Button {
                        showingAddPhotos = true
                    } label: {
                        Label("Añadir de la biblioteca", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .buttonStyle(MemoraButtonStyle(prominent: true))

                    ImportActions(store: store, secure: secure)
                }

                if isDropTargeted {
                    Panel {
                        Label("Suelta los archivos para añadirlos a este álbum", systemImage: "arrow.down.doc.fill")
                            .foregroundStyle(MemoraStyle.cream)
                    }
                }

                if assets.isEmpty {
                    EmptyMemory(symbol: "photo.stack", title: "Álbum vacío",
                                message: "Arrastra archivos aquí o toca 'Añadir de la biblioteca' para organizarlos.")
                } else {
                    AssetGrid(store: store, assets: assets, secure: secure)
                }
            }
            .padding(MemoraStyle.pagePadding)
        }
        .dropDestination(for: String.self) { items, _ in
            for item in items {
                if let assetID = UUID(uuidString: item) {
                    try? store.addAssets([assetID], toAlbum: album.id)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .sheet(isPresented: $showingAddPhotos) {
            AddToAlbumSheet(store: store, album: album, available: availableAssets)
        }
        .navigationBarTitleDisplayMode(.inline)
        .memoraPage()
    }
}

struct AddToAlbumSheet: View {
    @ObservedObject var store: MemoryStore
    let album: MemoryAlbum
    let available: [MemoryAsset]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Selecciona recuerdos para añadir a '\(album.name)'")
                        .font(.subheadline).foregroundStyle(MemoraStyle.muted)

                    if available.isEmpty {
                        EmptyMemory(symbol: "checkmark.circle", title: "Todo asignado",
                                    message: "No hay más archivos sueltos en la biblioteca.")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 6)], spacing: 6) {
                            ForEach(available) { asset in
                                ZStack(alignment: .topTrailing) {
                                    MemoryCard(asset: asset, image: store.thumbnail(for: asset))
                                        .opacity(selectedIDs.contains(asset.id) ? 0.7 : 1.0)
                                    if selectedIDs.contains(asset.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(MemoraStyle.cream)
                                            .padding(6)
                                    }
                                }
                                .onTapGesture {
                                    if selectedIDs.contains(asset.id) {
                                        selectedIDs.remove(asset.id)
                                    } else {
                                        selectedIDs.insert(asset.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(MemoraStyle.pagePadding)
            }
            .navigationTitle("Añadir a álbum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir (\(selectedIDs.count))") {
                        try? store.addAssets(Array(selectedIDs), toAlbum: album.id)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .memoraPage()
        }
    }
}

struct SectionRowView: View {
    @ObservedObject var store: MemoryStore
    let section: MemorySection
    @State private var isPressed = false
    @State private var showDetail = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showNewAlbumAlert = false
    @State private var newAlbumName = ""

    private var albums: [MemoryAlbum] { store.albums(in: section) }
    private var assets: [MemoryAsset] { store.assets(in: section) }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            Panel {
                HStack(spacing: 14) {
                    Image(systemName: section.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(MemoraStyle.cream)
                        .frame(width: 44, height: 44)
                        .background(MemoraStyle.raised, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(albums.count) álbumes · \(assets.count) recuerdos")
                            .font(.caption)
                            .foregroundStyle(MemoraStyle.muted)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Mantén presionado")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MemoraStyle.muted)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(MemoraStyle.muted)
                    }
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing in
            isPressed = pressing
        }) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showDetail = true
        }
        .contextMenu {
            Button {
                showDetail = true
            } label: {
                Label("Abrir sección", systemImage: "folder.badge.gearshape")
            }

            Button {
                newAlbumName = ""
                showNewAlbumAlert = true
            } label: {
                Label("Nuevo álbum en sección", systemImage: "rectangle.stack.badge.plus")
            }

            Button {
                renameText = section.name
                showRenameAlert = true
            } label: {
                Label("Renombrar sección", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                do { try store.deleteSection(section.id) }
                catch { store.notice = error.localizedDescription }
            } label: {
                Label("Eliminar sección", systemImage: "trash")
            }
        }
        .navigationDestination(isPresented: $showDetail) {
            SectionDetailView(store: store, section: section)
        }
        .dropDestination(for: String.self) { items, _ in
            for item in items {
                if let droppedID = UUID(uuidString: item) {
                    if store.library.albums.contains(where: { $0.id == droppedID }) {
                        try? store.assignAlbum(droppedID, toSection: section.id)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else if store.activeAssets.contains(where: { $0.id == droppedID }) {
                        try? store.addAssets([droppedID], toSection: section.id)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
            }
            return true
        }
        .alert("Renombrar sección", isPresented: $showRenameAlert) {
            TextField("Nombre", text: $renameText)
            Button("Guardar") {
                do { try store.renameSection(section.id, newName: renameText) }
                catch { store.notice = error.localizedDescription }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Nuevo álbum en \(section.name)", isPresented: $showNewAlbumAlert) {
            TextField("Nombre del álbum", text: $newAlbumName)
            Button("Crear") {
                do { try store.createAlbum(newAlbumName, sectionID: section.id) }
                catch { store.notice = error.localizedDescription }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

struct SectionDetailView: View {
    @ObservedObject var store: MemoryStore
    let section: MemorySection
    @State private var addingAlbum = false
    @State private var albumName = ""
    @State private var showingAddFiles = false
    @State private var isDropTargeted = false

    private var albums: [MemoryAlbum] { store.albums(in: section) }
    private var assets: [MemoryAsset] { store.assets(in: section) }
    private var availableAssets: [MemoryAsset] {
        let sectionAlbumIDs = Set(albums.map(\.id))
        return store.activeAssets.filter { asset in
            !asset.albumIDs.contains(where: { sectionAlbumIDs.contains($0) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MemoraHeader(
                    title: section.name,
                    subtitle: "\(albums.count) álbumes · \(assets.count) recuerdos asociados · Arrastra álbumes o fotos aquí"
                )

                HStack(spacing: 8) {
                    Button { addingAlbum = true } label: {
                        Label("Nuevo álbum", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .buttonStyle(MemoraButtonStyle(prominent: true))

                    Button { showingAddFiles = true } label: {
                        Label("Añadir archivos", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(MemoraButtonStyle())
                }

                if isDropTargeted {
                    Panel {
                        Label("Suelta aquí para añadir este álbum o recuerdo a '\(section.name)'", systemImage: "arrow.down.doc.fill")
                            .foregroundStyle(MemoraStyle.cream)
                    }
                }

                SectionHeading(title: "Álbumes de la sección")
                if albums.isEmpty {
                    EmptyMemory(
                        symbol: "rectangle.stack.badge.plus",
                        title: "Sin álbumes en esta sección",
                        message: "Arrastra un álbum existente aquí o toca 'Nuevo álbum' para agrupar recuerdos afines."
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                        ForEach(albums) { album in
                            NavigationLink {
                                AlbumDetailView(store: store, album: album)
                            } label: {
                                AlbumTile(store: store, album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                SectionHeading(title: "Todos los recuerdos en esta sección")
                if assets.isEmpty {
                    EmptyMemory(
                        symbol: "photo.stack",
                        title: "No hay archivos asignados",
                        message: "Arrastra fotos aquí para asociarlas a esta sección."
                    )
                } else {
                    AssetGrid(store: store, assets: assets)
                }
            }
            .padding(MemoraStyle.pagePadding)
        }
        .dropDestination(for: String.self) { items, _ in
            for item in items {
                if let droppedID = UUID(uuidString: item) {
                    if store.library.albums.contains(where: { $0.id == droppedID }) {
                        try? store.assignAlbum(droppedID, toSection: section.id)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else if store.activeAssets.contains(where: { $0.id == droppedID }) {
                        try? store.addAssets([droppedID], toSection: section.id)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
            }
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .sheet(isPresented: $showingAddFiles) {
            AddToSectionSheet(store: store, section: section, available: availableAssets)
        }
        .alert("Nuevo álbum en \(section.name)", isPresented: $addingAlbum) {
            TextField("Nombre del álbum", text: $albumName)
            Button("Crear") {
                do {
                    try store.createAlbum(albumName, sectionID: section.id)
                    albumName = ""
                } catch {
                    store.notice = error.localizedDescription
                }
            }
            Button("Cancelar", role: .cancel) { albumName = "" }
        }
        .navigationBarTitleDisplayMode(.inline)
        .memoraPage()
    }
}

struct AddToSectionSheet: View {
    @ObservedObject var store: MemoryStore
    let section: MemorySection
    let available: [MemoryAsset]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Selecciona recuerdos para incorporar a la sección '\(section.name)'")
                        .font(.subheadline).foregroundStyle(MemoraStyle.muted)

                    if available.isEmpty {
                        EmptyMemory(symbol: "checkmark.circle", title: "Todo asignado",
                                    message: "Todos tus archivos activos ya forman parte de esta sección.")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 6)], spacing: 6) {
                            ForEach(available) { asset in
                                ZStack(alignment: .topTrailing) {
                                    MemoryCard(asset: asset, image: store.thumbnail(for: asset))
                                        .opacity(selectedIDs.contains(asset.id) ? 0.7 : 1.0)
                                    if selectedIDs.contains(asset.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(MemoraStyle.cream)
                                            .padding(6)
                                    }
                                }
                                .onTapGesture {
                                    if selectedIDs.contains(asset.id) {
                                        selectedIDs.remove(asset.id)
                                    } else {
                                        selectedIDs.insert(asset.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(MemoraStyle.pagePadding)
            }
            .navigationTitle("Añadir a sección")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir (\(selectedIDs.count))") {
                        try? store.addAssets(Array(selectedIDs), toSection: section.id)
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .memoraPage()
        }
    }
}

struct AssetDetailView: View {
    @ObservedObject var store: MemoryStore
    let assetID: UUID
    var secure = false
    @State private var temporary: URL?
    @State private var showingPreview = false
    @State private var showingShare = false
    @State private var locationText = ""
    @State private var newTagText = ""
    @State private var localTags: [String] = []

    private var asset: MemoryAsset? {
        if secure {
            return store.privateLibrary?.assets.first { $0.id == assetID }
        }
        return store.library.assets.first { $0.id == assetID }
    }

    var body: some View {
        ScrollView {
            if let asset {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = store.thumbnail(for: asset, secure: secure) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity).frame(maxHeight: 480)
                            .background(MemoraStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        EmptyMemory(symbol: asset.kind.symbol, title: asset.name,
                                    message: "Archivo original cifrado en este iPhone.")
                    }
                    Text(asset.name)
                        .font(MemoraStyle.title(24))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
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
                        SectionHeading(title: "Ubicación")
                        Panel {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(MemoraStyle.cream)
                                    TextField("Añadir o editar ubicación…", text: $locationText)
                                        .textFieldStyle(.plain)
                                        .onSubmit { saveMetadata() }
                                    if locationText != asset.location {
                                        Button("Guardar") { saveMetadata() }
                                            .font(.caption.bold())
                                            .foregroundStyle(.mint)
                                    }
                                }
                                if let lat = asset.latitude, let lon = asset.longitude {
                                    Text(String(format: "GPS: %.4f°, %.4f°", lat, lon))
                                        .font(.caption2)
                                        .foregroundStyle(MemoraStyle.muted)
                                }
                            }
                        }

                        SectionHeading(title: "Etiquetas")
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                if !localTags.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(localTags, id: \.self) { tag in
                                                HStack(spacing: 5) {
                                                    Text("#\(tag)").font(.caption).foregroundStyle(MemoraStyle.cream)
                                                    Button {
                                                        localTags.removeAll { $0 == tag }
                                                        saveMetadata()
                                                    } label: {
                                                        Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(MemoraStyle.muted)
                                                    }
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(MemoraStyle.line, in: Capsule())
                                            }
                                        }
                                    }
                                }
                                HStack {
                                    Image(systemName: "tag").foregroundStyle(MemoraStyle.cream)
                                    TextField("Nueva etiqueta…", text: $newTagText)
                                        .textFieldStyle(.plain)
                                        .onSubmit { addTag() }
                                    if !newTagText.trimmingCharacters(in: .whitespaces).isEmpty {
                                        Button("Añadir") { addTag() }
                                            .font(.caption.bold())
                                            .foregroundStyle(.mint)
                                    }
                                }
                            }
                        }
                    }

                    if asset.cameraModel != nil || asset.iso != nil || asset.aperture != nil || asset.focalLength != nil || asset.width != nil {
                        SectionHeading(title: "Detalles técnicos")
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                if let camera = asset.cameraModel {
                                    HStack {
                                        Label(camera, systemImage: "camera")
                                            .font(.subheadline)
                                        Spacer()
                                    }
                                }
                                if let w = asset.width, let h = asset.height {
                                    HStack {
                                        Label("\(w) × \(h) px", systemImage: "aspectratio")
                                            .font(.caption)
                                            .foregroundStyle(MemoraStyle.muted)
                                        Spacer()
                                    }
                                }
                                HStack(spacing: 14) {
                                    if let iso = asset.iso {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("ISO").font(.caption2).foregroundStyle(MemoraStyle.muted)
                                            Text("\(iso)").font(.system(.subheadline, design: .monospaced).bold())
                                        }
                                    }
                                    if let f = asset.aperture {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("APERTURA").font(.caption2).foregroundStyle(MemoraStyle.muted)
                                            Text(String(format: "ƒ/%.1f", f)).font(.system(.subheadline, design: .monospaced).bold())
                                        }
                                    }
                                    if let focal = asset.focalLength {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("FOCAL").font(.caption2).foregroundStyle(MemoraStyle.muted)
                                            Text(String(format: "%.0f mm", focal)).font(.system(.subheadline, design: .monospaced).bold())
                                        }
                                    }
                                }
                            }
                        }
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
                .padding(MemoraStyle.pagePadding)
            }
        }
        .onAppear {
            if let asset {
                locationText = asset.location
                localTags = asset.tags
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

    private func saveMetadata() {
        guard !secure else { return }
        do {
            try store.updateAssetMetadata(id: assetID, location: locationText, tags: localTags)
        } catch {
            store.notice = error.localizedDescription
        }
    }

    private func addTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard !trimmed.isEmpty else { return }
        if !localTags.contains(trimmed) {
            localTags.append(trimmed)
            saveMetadata()
        }
        newTagText = ""
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
    @State private var selectedTab = 0
    @State private var namingCluster: FaceCluster?
    @State private var clusterPersonName = ""

    private var reviewCount: Int {
        store.library.detectedFaces.filter { $0.reviewStatus == .suggested }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: "Personas", subtitle: "Reconocimiento facial y agrupaciones locales")

                HStack(spacing: 10) {
                    Button { adding = true } label: { Label("Nueva persona", systemImage: "plus") }
                        .buttonStyle(MemoraButtonStyle(prominent: true))

                    Button {
                        store.recomputeClusters()
                    } label: {
                        Label("Reanalizar", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(MemoraButtonStyle())
                }

                Picker("Categoría", selection: $selectedTab) {
                    Text("Todas (\(store.library.people.count))").tag(0)
                    Text("Sin identificar (\(store.library.clusters.count))").tag(1)
                    Text("Revisar (\(reviewCount))").tag(2)
                }
                .pickerStyle(.segmented)

                if selectedTab == 0 {
                    if store.library.people.isEmpty {
                        EmptyMemory(symbol: "person.2", title: "Ponle nombre a tus recuerdos",
                                    message: "Crea personas o asígnales nombre desde las agrupaciones automáticas de rostros.")
                    }
                    ForEach(store.library.people) { person in
                        NavigationLink {
                            PersonDetailView(store: store, person: person)
                        } label: {
                            Panel {
                                HStack(spacing: 14) {
                                    Image(systemName: "person.crop.circle")
                                        .font(.system(size: 38, weight: .ultraLight))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(person.name)
                                            .font(MemoraStyle.title(22))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                        Text("\(store.activeAssets.filter { $0.personIDs.contains(person.id) }.count) archivos")
                                            .font(.caption).foregroundStyle(MemoraStyle.muted)
                                    }
                                    Spacer()
                                    if !person.reviewCandidateAssetIDs.isEmpty {
                                        Text("\(person.reviewCandidateAssetIDs.count) para revisar")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.2), in: Capsule())
                                            .foregroundStyle(.orange)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(MemoraStyle.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else if selectedTab == 1 {
                    if store.library.clusters.isEmpty {
                        EmptyMemory(symbol: "person.crop.circle.badge.checkmark",
                                    title: "No hay rostros sin identificar",
                                    message: "Todos los rostros detectados han sido nombrados o no cumplen el Quality Gate.")
                    } else {
                        ForEach(store.library.clusters) { cluster in
                            Panel {
                                HStack(spacing: 14) {
                                    Image(systemName: "person.crop.rectangle.stack")
                                        .font(.system(size: 32, weight: .ultraLight))
                                        .foregroundStyle(MemoraStyle.cream)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Grupo con \(cluster.faceIDs.count) fotos")
                                            .font(MemoraStyle.title(18))
                                        Text("Rostros similares encontrados localmente")
                                            .font(.caption).foregroundStyle(MemoraStyle.muted)
                                    }
                                    Spacer()
                                    Button("Nombrar") {
                                        clusterPersonName = cluster.suggestedName ?? ""
                                        namingCluster = cluster
                                    }
                                    .buttonStyle(MemoraButtonStyle(prominent: true))
                                }
                            }
                        }
                    }
                } else {
                    let suggested = store.library.detectedFaces.filter { $0.reviewStatus == .suggested }
                    if suggested.isEmpty {
                        EmptyMemory(symbol: "checkmark.circle",
                                    title: "Todo al día",
                                    message: "No hay coincidencias en zona de duda pendientes de confirmación.")
                    } else {
                        ForEach(suggested) { face in
                            Panel {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        if let asset = store.library.assets.first(where: { $0.id == face.assetID }),
                                           let thumb = store.thumbnail(for: asset) {
                                            Image(uiImage: thumb)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 50, height: 50)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            if let pID = face.personID, let person = store.library.people.first(where: { $0.id == pID }) {
                                                Text("¿Es \(person.name)?")
                                                    .font(MemoraStyle.title(18))
                                            } else {
                                                Text("Coincidencia sugerida")
                                                    .font(MemoraStyle.title(18))
                                            }
                                            Text(String(format: "Confianza: %.0f%% · Zona de revisión", face.confidence * 100))
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                        Spacer()
                                    }
                                    HStack(spacing: 10) {
                                        if let pID = face.personID {
                                            Button("Confirmar") {
                                                do {
                                                    try store.confirmFaceReview(faceID: face.id, personID: pID)
                                                } catch {
                                                    store.notice = error.localizedDescription
                                                }
                                            }
                                            .buttonStyle(MemoraButtonStyle(prominent: true))
                                        }
                                        Menu("Asignar a otra") {
                                            ForEach(store.library.people) { other in
                                                Button(other.name) {
                                                    do {
                                                        try store.correctFace(faceID: face.id, correctPersonID: other.id)
                                                    } catch {
                                                        store.notice = error.localizedDescription
                                                    }
                                                }
                                            }
                                        }
                                        .buttonStyle(MemoraButtonStyle())
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(MemoraStyle.pagePadding)
        }
        .alert("Añadir persona", isPresented: $adding) {
            TextField("Nombre", text: $name)
            Button("Guardar") {
                do { try store.createPerson(name); name = "" }
                catch { store.notice = error.localizedDescription }
            }
            Button("Cancelar", role: .cancel) { name = "" }
        }
        .alert("Nombrar grupo de rostros", isPresented: Binding(
            get: { namingCluster != nil },
            set: { if !$0 { namingCluster = nil } }
        )) {
            TextField("Nombre de la persona", text: $clusterPersonName)
            Button("Guardar") {
                if let cluster = namingCluster {
                    do {
                        try store.nameCluster(cluster.id, name: clusterPersonName)
                    } catch {
                        store.notice = error.localizedDescription
                    }
                }
                namingCluster = nil
                clusterPersonName = ""
            }
            Button("Cancelar", role: .cancel) {
                namingCluster = nil
                clusterPersonName = ""
            }
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

                if !person.reviewCandidateAssetIDs.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                    .foregroundStyle(.orange)
                                Text("\(person.reviewCandidateAssetIDs.count) fotos por confirmar")
                                    .font(MemoraStyle.title(16))
                                    .foregroundStyle(.orange)
                            }
                            Text("Face Engine v2 identificó posibles recuerdos con coincidencia moderada.")
                                .font(.caption).foregroundStyle(MemoraStyle.muted)
                        }
                    }
                }

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
            .padding(MemoraStyle.pagePadding)
        }
        .memoraPage()
    }
}

struct SearchView: View {
    @ObservedObject var store: MemoryStore
    @State private var query = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var queryImage: UIImage?
    @State private var isSearchingByPhoto = false
    @State private var photoSearchResults: [FaceMatchResult] = []
    @State private var hasSearchedPhoto = false

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
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: "Buscar", subtitle: "Encuentra personas, lugares y momentos")

                TextField("Buscar en tu biblioteca…", text: $query)
                    .textFieldStyle(.roundedBorder)

                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "faceid")
                                .font(.title2)
                                .foregroundStyle(MemoraStyle.cream)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Buscar mediante fotografía")
                                    .font(MemoraStyle.title(18))
                                Text("Reconocimiento local · Face Engine v2")
                                    .font(.caption)
                                    .foregroundStyle(MemoraStyle.muted)
                            }
                            Spacer()
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Label(queryImage == nil ? "Elegir foto" : "Cambiar", systemImage: "photo.badge.plus")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(MemoraButtonStyle())
                        }

                        if let queryImage {
                            HStack(spacing: 12) {
                                Image(uiImage: queryImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(MemoraStyle.line, lineWidth: 1))
                                VStack(alignment: .leading, spacing: 4) {
                                    if isSearchingByPhoto {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Analizando rostros…")
                                                .font(.caption)
                                                .foregroundStyle(MemoraStyle.muted)
                                        }
                                    } else {
                                        Text("\(photoSearchResults.count) persona(s) evaluada(s)")
                                            .font(.caption.bold())
                                        Button("Limpiar foto") {
                                            self.queryImage = nil
                                            self.photoSearchResults = []
                                            self.hasSearchedPhoto = false
                                            self.selectedPhotoItem = nil
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                }

                if hasSearchedPhoto && !isSearchingByPhoto {
                    if photoSearchResults.isEmpty {
                        EmptyMemory(symbol: "person.crop.circle.badge.questionmark",
                                    title: "Sin rostros identificables",
                                    message: "No se detectaron rostros con suficiente calidad en esta fotografía.")
                    } else {
                        SectionHeading(title: "Coincidencias faciales encontradas")
                        ForEach(photoSearchResults) { match in
                            NavigationLink {
                                PersonDetailView(store: store, person: match.person)
                            } label: {
                                Panel {
                                    HStack(spacing: 14) {
                                        Image(systemName: "person.crop.circle")
                                            .font(.system(size: 38, weight: .ultraLight))
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(match.person.name)
                                                    .font(MemoraStyle.title(20))
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(String(format: "%.0f%%", match.confidence * 100))
                                                    .font(.system(.subheadline, design: .monospaced).bold())
                                                    .foregroundStyle(match.zone == .high ? .mint : (match.zone == .review ? .orange : MemoraStyle.muted))
                                            }
                                            HStack {
                                                Text(match.zone.rawValue)
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        (match.zone == .high ? Color.mint.opacity(0.15) : (match.zone == .review ? Color.orange.opacity(0.15) : MemoraStyle.surfaceElevated)),
                                                        in: Capsule()
                                                    )
                                                    .foregroundStyle(match.zone == .high ? .mint : (match.zone == .review ? .orange : MemoraStyle.muted))
                                                Spacer()
                                                Text("\(match.assetCount) fotos · \(match.albumCount) álbumes")
                                                    .font(.caption)
                                                    .foregroundStyle(MemoraStyle.muted)
                                            }
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if query.isEmpty && !hasSearchedPhoto {
                    EmptyMemory(symbol: "magnifyingglass", title: "Tu biblioteca, a un toque",
                                message: "Busca por nombre, álbum, persona, etiqueta o elige una foto para buscar rostros.")
                } else if !query.isEmpty {
                    if results.isEmpty {
                        EmptyMemory(symbol: "magnifyingglass", title: "Sin coincidencias",
                                    message: "Prueba con otro nombre o etiqueta.")
                    } else {
                        SectionHeading(title: "Resultados de texto")
                        AssetGrid(store: store, assets: results)
                    }
                }
            }
            .padding(MemoraStyle.pagePadding)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    queryImage = img
                    isSearchingByPhoto = true
                    hasSearchedPhoto = true
                    let matches = await store.searchPeopleByPhoto(image: img)
                    photoSearchResults = matches
                    isSearchingByPhoto = false
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .memoraPage()
    }
}
