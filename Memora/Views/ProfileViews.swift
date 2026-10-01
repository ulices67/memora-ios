import SwiftUI

struct ProfileView: View {
    @ObservedObject var store: MemoryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    MemoraHeader(title: "Perfil", subtitle: "Tu cuenta y tu biblioteca")
                    Image(systemName: "icloud.slash")
                        .font(.title3).foregroundStyle(MemoraStyle.muted)
                        .frame(width: 41, height: 41)
                        .background(MemoraStyle.surface, in: Circle())
                        .accessibilityLabel("Sin sincronización en la nube")
                    NavigationLink { SettingsView(store: store) } label: {
                        Image(systemName: "gearshape")
                            .font(.title3).frame(width: 41, height: 41)
                            .background(MemoraStyle.surface, in: Circle())
                    }
                    .accessibilityLabel("Abrir configuración")
                }
                Panel {
                    HStack(spacing: 17) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 65, weight: .ultraLight))
                            .foregroundStyle(MemoraStyle.cream)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.account?.name ?? "").font(MemoraStyle.title(28))
                            Text(store.account?.email ?? "").font(.subheadline)
                                .foregroundStyle(MemoraStyle.muted)
                            if let created = store.account?.createdAt {
                                Text("Miembro desde \(created.formatted(.dateTime.year()))")
                                    .font(.caption).foregroundStyle(MemoraStyle.muted)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    StatTile(symbol: "rectangle.stack", title: "Álbumes", value: "\(store.library.albums.count)")
                    StatTile(symbol: "person.2", title: "Personas", value: "\(store.library.people.count)")
                    StatTile(symbol: "heart", title: "Favoritos", value: "\(store.activeAssets.filter(\.favorite).count)")
                }
                SectionHeading(title: "Cuenta")
                NavigationLink { SettingsView(store: store) } label: {
                    Panel { MemoryRow(symbol: "gearshape", title: "Configuración", detail: "Seguridad, privacidad y biblioteca") }
                }
                .buttonStyle(.plain)
                SectionHeading(title: "Biblioteca")
                NavigationLink { VaultView(store: store) } label: {
                    Panel { MemoryRow(symbol: "lock", title: "Bóveda privada", detail: store.vaultUnlocked ? "Desbloqueada" : "Bloqueada") }
                }
                .buttonStyle(.plain)
                NavigationLink { StorageView(store: store) } label: {
                    Panel { MemoryRow(symbol: "externaldrive", title: "Almacenamiento", detail: "Uso real en este iPhone") }
                }
                .buttonStyle(.plain)
                NavigationLink { TrashView(store: store) } label: {
                    Panel { MemoryRow(symbol: "trash", title: "Papelera", detail: "\(store.trash.count) archivos") }
                }
                .buttonStyle(.plain)
                Button(role: .destructive) { store.logout() } label: {
                    Panel { MemoryRow(symbol: "rectangle.portrait.and.arrow.right", title: "Cerrar sesión", detail: "Solicitar contraseña al volver") }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .toolbar(.hidden, for: .navigationBar)
        .memoraPage()
    }
}

struct SettingsView: View {
    @ObservedObject var store: MemoryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MemoraHeader(title: "Configuración", subtitle: "Protección, privacidad y organización")
                SectionHeading(title: "Protección de la cuenta")
                Panel {
                    VStack(spacing: 0) {
                        MemoryRow(symbol: "checkmark.shield", title: "Cifrado local",
                                  detail: "AES-256-GCM · Clave individual por archivo", trailing: "Activo")
                        Divider()
                        MemoryRow(symbol: "faceid", title: "Face ID",
                                  detail: store.biometricAvailable ? "Disponible para la bóveda" : "No disponible en este dispositivo")
                        Divider()
                        MemoryRow(symbol: "lock", title: "Bóveda",
                                  detail: store.vaultUnlocked ? "Desbloqueada temporalmente" : "Bloqueada")
                        Divider()
                        MemoryRow(symbol: "icloud.slash", title: "Cloudflare Sync",
                                  detail: "No conectado · No hay copia remota")
                    }
                }
                SectionHeading(title: "Cuenta")
                Panel {
                    VStack(spacing: 0) {
                        MemoryRow(symbol: "person", title: "Información personal", detail: store.account?.name ?? "")
                        Divider()
                        MemoryRow(symbol: "envelope", title: "Email y contraseña", detail: store.account?.email ?? "")
                        Divider()
                        MemoryRow(symbol: "key", title: "Código de recuperación", detail: "Guardado por el usuario; no se puede volver a mostrar")
                        Divider()
                        MemoryRow(symbol: "iphone", title: "Dispositivos y sesiones", detail: "Una cuenta local en este iPhone")
                    }
                }
                SectionHeading(title: "Privacidad y reconocimiento")
                Panel {
                    VStack(spacing: 0) {
                        MemoryRow(symbol: "person.crop.rectangle", title: "Reconocimiento facial",
                                  detail: "Pendiente · No se guardan embeddings")
                        Divider()
                        MemoryRow(symbol: "location", title: "Ubicación y metadatos",
                                  detail: "Los metadatos de Memora están cifrados")
                        Divider()
                        MemoryRow(symbol: "eye.slash", title: "Búsqueda mediante foto",
                                  detail: "Pendiente de modelo local validado")
                    }
                }
                SectionHeading(title: "Biblioteca")
                Panel {
                    VStack(spacing: 0) {
                        MemoryRow(symbol: "folder", title: "Secciones", detail: "\(store.library.sections.count) creadas")
                        Divider()
                        MemoryRow(symbol: "rectangle.stack", title: "Álbumes", detail: "\(store.library.albums.count) creados")
                        Divider()
                        MemoryRow(symbol: "person.2", title: "Personas", detail: "\(store.library.people.count) perfiles manuales")
                        Divider()
                        MemoryRow(symbol: "trash", title: "Papelera", detail: "\(store.trash.count) archivos")
                    }
                }
                SectionHeading(title: "Almacenamiento y apariencia")
                Panel {
                    VStack(spacing: 0) {
                        MemoryRow(symbol: "externaldrive", title: "Uso local", detail: store.usedBytes.memorySize)
                        Divider()
                        MemoryRow(symbol: "moon", title: "Tema oscuro", detail: "Activo")
                    }
                }
                Text("Memora para iOS · 0.1 · Los archivos permanecen en este dispositivo.")
                    .font(.caption).foregroundStyle(MemoraStyle.muted).padding(.top, 10)
            }
            .padding(18)
        }
        .navigationBarTitleDisplayMode(.inline)
        .memoraPage()
    }
}

struct StorageView: View {
    @ObservedObject var store: MemoryStore
    @State private var showLarge = false

    private func size(_ kind: AssetKind) -> Int {
        store.library.assets.filter { $0.kind == kind }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                MemoraHeader(title: "Almacenamiento", subtitle: "Controla el espacio de tu biblioteca")
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.usedBytes.memorySize).font(MemoraStyle.title(36))
                        Text("Usados por Memora en originales importados")
                            .font(.subheadline).foregroundStyle(MemoraStyle.muted)
                        Text("No hay cuota remota: Cloudflare Sync no está conectado.")
                            .font(.caption).foregroundStyle(MemoraStyle.muted)
                    }
                    .padding(.vertical, 10)
                }
                SectionHeading(title: "Uso por tipo")
                HStack(spacing: 8) {
                    StatTile(symbol: "photo", title: "Fotos", value: size(.photo).memorySize)
                    StatTile(symbol: "video", title: "Videos", value: size(.video).memorySize)
                }
                HStack(spacing: 8) {
                    StatTile(symbol: "waveform", title: "Audio", value: size(.audio).memorySize)
                    StatTile(symbol: "doc", title: "Documentos", value: size(.document).memorySize)
                }
                SectionHeading(title: "Optimización")
                Panel {
                    VStack(spacing: 0) {
                        Button { store.clearPreviewCache() } label: {
                            MemoryRow(symbol: "trash.slash", title: "Liberar caché",
                                      detail: "Borra vistas temporales, conserva originales")
                        }
                        .buttonStyle(.plain)
                        Divider()
                        Button { showLarge.toggle() } label: {
                            MemoryRow(symbol: "doc.text.magnifyingglass", title: "Revisar archivos grandes",
                                      detail: "Ordenados por tamaño real")
                        }
                        .buttonStyle(.plain)
                        Divider()
                        MemoryRow(symbol: "square.on.square", title: "Duplicados",
                                  detail: "Se evitan al importar con SHA-256")
                    }
                }
                if showLarge {
                    ForEach(store.library.assets.sorted { $0.size > $1.size }.prefix(10)) { asset in
                        Panel {
                            HStack {
                                Image(systemName: asset.kind.symbol)
                                Text(asset.name).lineLimit(1)
                                Spacer()
                                Text(asset.size.memorySize).foregroundStyle(MemoraStyle.muted)
                            }
                        }
                    }
                }
                SectionHeading(title: "Protección de tus copias")
                Panel {
                    VStack(spacing: 0) {
                        MemoryRow(symbol: "lock.shield", title: "Originales cifrados",
                                  detail: "Claves diferentes por archivo")
                        Divider()
                        MemoryRow(symbol: "wifi.slash", title: "Copia en la nube",
                                  detail: "No configurada en esta versión")
                    }
                }
                Text("El tamaño de la bóveda se suma cuando está desbloqueada. iOS puede usar espacio adicional para archivos temporales del sistema.")
                    .font(.caption).foregroundStyle(MemoraStyle.muted)
            }
            .padding(18)
        }
        .navigationBarTitleDisplayMode(.inline)
        .memoraPage()
    }
}

struct TrashView: View {
    @ObservedObject var store: MemoryStore
    @State private var pendingDelete: MemoryAsset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                MemoraHeader(title: "Papelera", subtitle: "Recupera o elimina archivos")
                if store.trash.isEmpty {
                    EmptyMemory(symbol: "trash", title: "La papelera está vacía",
                                message: "Los archivos eliminados aparecerán aquí.")
                }
                ForEach(store.trash) { asset in
                    Panel {
                        HStack {
                            Image(systemName: asset.kind.symbol).frame(width: 35)
                            VStack(alignment: .leading) {
                                Text(asset.name).lineLimit(1)
                                Text(asset.size.memorySize).font(.caption).foregroundStyle(MemoraStyle.muted)
                            }
                            Spacer()
                            Menu {
                                Button("Restaurar") {
                                    do { try store.restore(asset.id) }
                                    catch { store.notice = error.localizedDescription }
                                }
                                Button("Eliminar definitivamente", role: .destructive) {
                                    pendingDelete = asset
                                }
                            } label: { Image(systemName: "ellipsis") }
                        }
                    }
                }
            }
            .padding(18)
        }
        .confirmationDialog("¿Eliminar este archivo para siempre?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Eliminar definitivamente", role: .destructive) {
                if let id = pendingDelete?.id {
                    do { try store.deleteForever(id) }
                    catch { store.notice = error.localizedDescription }
                }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        }
        .navigationBarTitleDisplayMode(.inline)
        .memoraPage()
    }
}

struct VaultView: View {
    @ObservedObject var store: MemoryStore
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var recoveryMode = false
    @State private var recoveryInput = ""
    @State private var newRecoveryCode = ""
    @State private var showRecoverySheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MemoraHeader(title: "Bóveda", subtitle: "Tus recuerdos más privados")
                if !store.vaultConfigured {
                    lockPanel("Crea una bóveda independiente", description: "Su clave maestra y su contraseña serán distintas de las de la biblioteca.")
                    SecureField("Contraseña de bóveda · mínimo 12 caracteres", text: $password)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Confirmar contraseña", text: $confirmation)
                        .textFieldStyle(.roundedBorder)
                    Button("Crear bóveda") {
                        do {
                            guard password == confirmation else {
                                throw MemoraError.invalidInput("Las contraseñas no coinciden.")
                            }
                            newRecoveryCode = try store.configureVault(password: password)
                            showRecoverySheet = true
                            password = ""; confirmation = ""; error = nil
                        } catch { error = error.localizedDescription }
                    }
                    .buttonStyle(MemoraButtonStyle(prominent: true))
                } else if !store.vaultUnlocked {
                    lockPanel("Bóveda bloqueada", description: "Su contenido no aparece en la biblioteca ni en las búsquedas normales.")
                    if recoveryMode {
                        TextField("Código de recuperación de la bóveda", text: $recoveryInput)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Nueva contraseña de bóveda", text: $password)
                            .textFieldStyle(.roundedBorder)
                        Button("Recuperar bóveda") {
                            do {
                                newRecoveryCode = try store.recoverVault(code: recoveryInput, newPassword: password)
                                showRecoverySheet = true
                                recoveryInput = ""; password = ""; recoveryMode = false; error = nil
                            } catch { error = error.localizedDescription }
                        }
                        .buttonStyle(MemoraButtonStyle(prominent: true))
                        Button("Volver a desbloquear") { recoveryMode = false; error = nil }
                    } else {
                        SecureField("Contraseña de bóveda", text: $password)
                            .textFieldStyle(.roundedBorder)
                        Button("Desbloquear") {
                            do { try store.unlockVault(password: password); password = ""; error = nil }
                            catch { error = error.localizedDescription }
                        }
                        .buttonStyle(MemoraButtonStyle(prominent: true))
                        Button("¿Olvidaste la contraseña de la bóveda?") {
                            recoveryMode = true; password = ""; error = nil
                        }
                        .font(.caption)
                    }
                    if store.biometricAvailable && !recoveryMode {
                        Button("Usar Face ID") {
                            do { try store.unlockVaultWithBiometrics(); error = nil }
                            catch { error = error.localizedDescription }
                        }
                        .buttonStyle(MemoraButtonStyle())
                    }
                } else {
                    Panel {
                        HStack(spacing: 15) {
                            Image(systemName: "checkmark.shield.fill").font(.title).foregroundStyle(.mint)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Protegida con una clave diferente").font(MemoraStyle.title(22))
                                Text("Se bloquea al salir de la app o tras 15 minutos.")
                                    .font(.caption).foregroundStyle(MemoraStyle.muted)
                            }
                        }
                    }
                    if store.biometricAvailable {
                        Button("Activar Face ID para esta bóveda") {
                            do { try store.enableVaultBiometrics(); store.notice = "Face ID activado para la bóveda." }
                            catch { error = error.localizedDescription }
                        }
                        .buttonStyle(MemoraButtonStyle())
                    }
                    Button("Bloquear ahora") { store.lockVault() }
                        .buttonStyle(MemoraButtonStyle())
                    ImportActions(store: store, secure: true)
                    SectionHeading(title: "Archivos privados")
                    if let assets = store.privateLibrary?.assets, !assets.isEmpty {
                        AssetGrid(store: store, assets: assets, secure: true)
                    } else {
                        EmptyMemory(symbol: "lock.doc", title: "Tu bóveda está vacía",
                                    message: "Importa aquí archivos que quieras separar de la biblioteca.")
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .padding(18)
        }
        .sheet(isPresented: $showRecoverySheet) {
            VaultRecoverySheet(code: newRecoveryCode) {
                newRecoveryCode = ""
                showRecoverySheet = false
            }
            .presentationDetents([.medium, .large])
        }
        .navigationBarTitleDisplayMode(.inline)
        .memoraPage()
    }

    private func lockPanel(_ title: String, description: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 43, weight: .ultraLight))
                    .foregroundStyle(MemoraStyle.cream)
                Text(title).font(MemoraStyle.title(25))
                Text(description).font(.subheadline).foregroundStyle(MemoraStyle.muted)
            }
            .padding(.vertical, 14)
        }
    }
}

private struct VaultRecoverySheet: View {
    let code: String
    let close: () -> Void
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Código de la bóveda").font(MemoraStyle.title(30))
            Text("Guárdalo fuera de Memora. Es distinto del código de recuperación de la cuenta.")
                .foregroundStyle(MemoraStyle.muted)
            Text(code).font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding().frame(maxWidth: .infinity)
                .background(MemoraStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            Toggle("Ya lo guardé en un lugar seguro", isOn: $saved)
            Button("Continuar", action: close)
                .buttonStyle(MemoraButtonStyle(prominent: true))
                .disabled(!saved)
            Spacer()
        }
        .padding(22)
        .memoraPage()
        .interactiveDismissDisabled()
    }
}
