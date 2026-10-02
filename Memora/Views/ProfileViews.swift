import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject var store: MemoryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    MemoraHeader(title: "Perfil", subtitle: "Tu cuenta y tu biblioteca")
                    NavigationLink { CloudflareBackupView(store: store) } label: {
                        Image(systemName: store.lastCloudflareBackupDate != nil ? "cloud.fill" : "cloud")
                            .font(.body)
                            .foregroundStyle(store.lastCloudflareBackupDate != nil ? .mint : MemoraStyle.muted)
                            .frame(width: 38, height: 38)
                            .background(MemoraStyle.surface, in: Circle())
                    }
                    .accessibilityLabel("Copias a Cloudflare E2EE")
                    NavigationLink { SettingsView(store: store) } label: {
                        Image(systemName: "gearshape")
                            .font(.body).frame(width: 38, height: 38)
                            .background(MemoraStyle.surface, in: Circle())
                    }
                    .accessibilityLabel("Abrir configuración")
                }
                Panel {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 64, weight: .ultraLight))
                            .foregroundStyle(MemoraStyle.cream)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.account?.name ?? "")
                                .font(MemoraStyle.title(26))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(store.account?.email ?? "")
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(MemoraStyle.muted)
                            if let created = store.account?.createdAt {
                                Text("Miembro desde \(created.formatted(.dateTime.year()))")
                                    .font(.caption).foregroundStyle(MemoraStyle.muted)
                            }
                        }
                    }
                }
                HStack(spacing: 7) {
                    StatTile(symbol: "rectangle.stack", title: "Álbumes", value: "\(store.library.albums.count)")
                    StatTile(symbol: "person.2", title: "Personas", value: "\(store.library.people.count)")
                    StatTile(symbol: "heart", title: "Favoritos", value: "\(store.activeAssets.filter(\.favorite).count)")
                }
                SectionHeading(title: "Cuenta")
                NavigationLink { SettingsView(store: store) } label: {
                    Panel { MemoryRow(symbol: "gearshape", title: "Configuración", detail: "Seguridad, privacidad y biblioteca") }
                }
                .buttonStyle(.plain)
                SectionHeading(title: "Biblioteca y Nube")
                NavigationLink { VaultView(store: store) } label: {
                    Panel { MemoryRow(symbol: "lock", title: "Bóveda privada", detail: store.vaultUnlocked ? "Desbloqueada" : "Bloqueada") }
                }
                .buttonStyle(.plain)
                NavigationLink { CloudflareBackupView(store: store) } label: {
                    Panel { MemoryRow(symbol: "cloud.fill", title: "Copias a Cloudflare",
                                      detail: "Cifrado E2EE · AES-256-GCM",
                                      trailing: store.lastCloudflareBackupDate != nil ? "Activo" : "Configurar") }
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
            .padding(.horizontal, MemoraStyle.pagePadding)
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
                        NavigationLink { SecurityDetailView(store: store) } label: {
                            MemoryRow(symbol: "checkmark.shield", title: "Cifrado local",
                                      detail: "AES-256-GCM · Clave individual por archivo", trailing: "Activo")
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { FaceIDSettingsView(store: store) } label: {
                            MemoryRow(symbol: store.biometricType == .touchID ? "touchid" : "faceid",
                                      title: "Modo Face ID",
                                      detail: store.appBiometricsEnabled ? "Protección de app y bóveda activa" : "Bloqueo biométrico al abrir",
                                      trailing: store.appBiometricsEnabled ? "Activo" : nil)
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { VaultView(store: store) } label: {
                            MemoryRow(symbol: "lock", title: "Bóveda privada",
                                      detail: store.vaultUnlocked ? "Desbloqueada temporalmente" : "Bloqueada")
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { CloudflareBackupView(store: store) } label: {
                            MemoryRow(symbol: "cloud.fill", title: "Copias a Cloudflare",
                                      detail: "Cifrado de extremo a extremo (E2EE)",
                                      trailing: store.lastCloudflareBackupDate != nil ? "Activo" : nil)
                        }.buttonStyle(.plain)
                    }
                }
                SectionHeading(title: "Cuenta")
                Panel {
                    VStack(spacing: 0) {
                        NavigationLink { AccountSettingsView(store: store) } label: {
                            MemoryRow(symbol: "person", title: "Información personal", detail: store.account?.name ?? "")
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { PasswordSettingsView(store: store) } label: {
                            MemoryRow(symbol: "envelope", title: "Email y contraseña", detail: store.account?.email ?? "")
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { RecoveryInfoView() } label: {
                            MemoryRow(symbol: "key", title: "Código de recuperación", detail: "Cómo protege el acceso a tus claves")
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { SessionView(store: store) } label: {
                            MemoryRow(symbol: "iphone", title: "Dispositivos y sesiones",
                                      detail: store.persistentSessionEnabled ? "Sesión persistente protegida" : "Solicitar contraseña al abrir")
                        }.buttonStyle(.plain)
                    }
                }
                SectionHeading(title: "Privacidad y reconocimiento")
                Panel {
                    VStack(spacing: 0) {
                        NavigationLink { PrivacyDetailView() } label: {
                            MemoryRow(symbol: "person.crop.rectangle", title: "Reconocimiento facial",
                                      detail: "Estado y límites del procesamiento local")
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { MetadataDetailView() } label: {
                            MemoryRow(symbol: "location", title: "Ubicación y metadatos",
                                      detail: "Los metadatos de Memora están cifrados")
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { PrivacyDetailView() } label: {
                            MemoryRow(symbol: "eye.slash", title: "Procesamiento local",
                                      detail: "Tus archivos no salen del dispositivo")
                        }.buttonStyle(.plain)
                    }
                }
                SectionHeading(title: "Biblioteca")
                Panel {
                    VStack(spacing: 0) {
                        NavigationLink { LibraryView(store: store) } label: {
                            MemoryRow(symbol: "folder", title: "Secciones", detail: "\(store.library.sections.count) creadas")
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { LibraryView(store: store) } label: {
                            MemoryRow(symbol: "rectangle.stack", title: "Álbumes", detail: "\(store.library.albums.count) creados")
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { PeopleView(store: store) } label: {
                            MemoryRow(symbol: "person.2", title: "Personas", detail: "\(store.library.people.count) perfiles manuales")
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { TrashView(store: store) } label: {
                            MemoryRow(symbol: "trash", title: "Papelera", detail: "\(store.trash.count) archivos")
                        }.buttonStyle(.plain)
                    }
                }
                SectionHeading(title: "Almacenamiento y apariencia")
                Panel {
                    VStack(spacing: 0) {
                        NavigationLink { StorageView(store: store) } label: {
                            MemoryRow(symbol: "externaldrive", title: "Uso local", detail: store.usedBytes.memorySize)
                        }.buttonStyle(.plain)
                        Divider()
                        NavigationLink { AppearanceView() } label: {
                            MemoryRow(symbol: "moon", title: "Apariencia", detail: "Tema oscuro optimizado para OLED")
                        }.buttonStyle(.plain)
                    }
                }
                Text("Memora para iOS · 0.5.0 (5) · Los archivos permanecen en este dispositivo.")
                    .font(.caption).foregroundStyle(MemoraStyle.muted).padding(.top, 10)
            }
            .padding(MemoraStyle.pagePadding)
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
                        Text(store.usedBytes.memorySize)
                            .font(MemoraStyle.title(32))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("Usados por Memora en originales importados")
                            .font(.subheadline).foregroundStyle(MemoraStyle.muted)
                        Text("No hay cuota remota: Cloudflare Sync no está conectado.")
                            .font(.caption).foregroundStyle(MemoraStyle.muted)
                    }
                    .padding(.vertical, 8)
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
            }
            .padding(MemoraStyle.pagePadding)
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
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: "Papelera", subtitle: "\(store.trash.count) archivos")
                if store.trash.isEmpty {
                    EmptyMemory(symbol: "trash", title: "Papelera vacía",
                                message: "Los archivos eliminados permanecen aquí antes de borrarse definitivamente.")
                } else {
                    Button(role: .destructive) {
                        do { try store.emptyTrash() }
                        catch { store.notice = error.localizedDescription }
                    } label: {
                        Text("Vaciar papelera")
                    }
                    .buttonStyle(MemoraButtonStyle())
                    ForEach(store.trash) { asset in
                        Panel {
                            HStack(spacing: 12) {
                                Image(systemName: asset.kind.symbol)
                                    .font(.title3).foregroundStyle(MemoraStyle.muted)
                                VStack(alignment: .leading) {
                                    Text(asset.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(asset.size.memorySize).font(.caption).foregroundStyle(MemoraStyle.muted)
                                }
                                Spacer()
                                Button {
                                    do { try store.restoreFromTrash(asset.id) }
                                    catch { store.notice = error.localizedDescription }
                                } label: {
                                    Image(systemName: "arrow.uturn.backward.circle")
                                }
                                .accessibilityLabel("Restaurar")
                                Button(role: .destructive) {
                                    pendingDelete = asset
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Eliminar definitivamente")
                            }
                        }
                    }
                }
            }
            .padding(MemoraStyle.pagePadding)
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
                        } catch let err { self.error = err.localizedDescription }
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
                            } catch let err { self.error = err.localizedDescription }
                        }
                        .buttonStyle(MemoraButtonStyle(prominent: true))
                        Button("Volver a desbloquear") { recoveryMode = false; error = nil }
                    } else {
                        SecureField("Contraseña de bóveda", text: $password)
                            .textFieldStyle(.roundedBorder)
                        Button("Desbloquear") {
                            do { try store.unlockVault(password: password); password = ""; error = nil }
                            catch let err { self.error = err.localizedDescription }
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
                            catch let err { self.error = err.localizedDescription }
                        }
                        .buttonStyle(MemoraButtonStyle())
                    }
                } else {
                    Panel {
                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.shield.fill").font(.title).foregroundStyle(.mint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Protegida con una clave diferente")
                                    .font(MemoraStyle.title(20))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Text("Se bloquea al salir de la app o tras 15 minutos.")
                                    .font(.caption).foregroundStyle(MemoraStyle.muted)
                            }
                        }
                    }
                    if store.biometricAvailable {
                        Button("Activar Face ID para esta bóveda") {
                            do { try store.enableVaultBiometrics(); store.notice = "Face ID activado para la bóveda." }
                            catch let err { self.error = err.localizedDescription }
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
            .padding(MemoraStyle.pagePadding)
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
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 38, weight: .ultraLight))
                    .foregroundStyle(MemoraStyle.cream)
                Text(title)
                    .font(MemoraStyle.title(22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(description).font(.subheadline).foregroundStyle(MemoraStyle.muted)
            }
            .padding(.vertical, 10)
        }
    }
}

private struct VaultRecoverySheet: View {
    let code: String
    let close: () -> Void
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Código de la bóveda").font(MemoraStyle.title(28))
            Text("Guárdalo fuera de Memora. Es distinto del código de recuperación de la cuenta.")
                .font(.subheadline)
                .foregroundStyle(MemoraStyle.muted)
            Text(code).font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding().frame(maxWidth: .infinity)
                .background(MemoraStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            Toggle("Ya lo guardé en un lugar seguro", isOn: $saved)
                .font(.subheadline)
            Button("Continuar", action: close)
                .buttonStyle(MemoraButtonStyle(prominent: true))
                .disabled(!saved)
            Spacer()
        }
        .frame(maxWidth: 440)
        .padding(22)
        .memoraPage()
        .interactiveDismissDisabled()
    }
}

private struct AccountSettingsView: View {
    @ObservedObject var store: MemoryStore
    @State private var name = ""
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: "Información personal", subtitle: "Tu identidad dentro de Memora")
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Nombre", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Text(store.account?.email ?? "")
                            .font(.caption).foregroundStyle(MemoraStyle.muted)
                    }
                }
                Button("Guardar nombre") {
                    do { try store.updateProfileName(name); message = "Perfil actualizado." }
                    catch { message = error.localizedDescription }
                }
                .buttonStyle(MemoraButtonStyle(prominent: true))
                if let message { Text(message).font(.caption).foregroundStyle(MemoraStyle.muted) }
            }.padding(MemoraStyle.pagePadding)
        }
        .onAppear { name = store.account?.name ?? "" }
        .navigationBarTitleDisplayMode(.inline).memoraPage()
    }
}

private struct PasswordSettingsView: View {
    @ObservedObject var store: MemoryStore
    @State private var current = ""
    @State private var next = ""
    @State private var confirmation = ""
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: "Contraseña", subtitle: "Protege la clave raíz de tu cuenta")
                SecureField("Contraseña actual", text: $current).textFieldStyle(.roundedBorder)
                SecureField("Contraseña nueva · mínimo 12 caracteres", text: $next).textFieldStyle(.roundedBorder)
                SecureField("Confirmar contraseña nueva", text: $confirmation).textFieldStyle(.roundedBorder)
                Button("Cambiar contraseña") {
                    do {
                        guard next == confirmation else { throw MemoraError.invalidInput("Las contraseñas nuevas no coinciden.") }
                        try store.changePassword(current: current, new: next)
                        current = ""; next = ""; confirmation = ""; message = "Contraseña actualizada. Tus archivos no necesitaron volver a cifrarse."
                    } catch { message = error.localizedDescription }
                }.buttonStyle(MemoraButtonStyle(prominent: true))
                if let message { Text(message).font(.caption).foregroundStyle(MemoraStyle.muted) }
            }.padding(MemoraStyle.pagePadding)
        }.navigationBarTitleDisplayMode(.inline).memoraPage()
    }
}

private struct SecurityDetailView: View {
    @ObservedObject var store: MemoryStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MemoraHeader(title: "Cifrado local", subtitle: "La protección activa de esta biblioteca")
                Panel { MemoryRow(symbol: "key.horizontal", title: "Clave raíz de cuenta", detail: "Generada en el dispositivo", trailing: "Activa") }
                Panel { MemoryRow(symbol: "doc.badge.gearshape", title: "Clave individual por archivo", detail: "AES-256-GCM con verificación de integridad", trailing: "Activa") }
                Panel { MemoryRow(symbol: "number", title: "Detección de duplicados", detail: "Comparación local mediante SHA-256", trailing: "Activa") }
                Text("La contraseña protege la clave raíz. Cambiarla no vuelve a cifrar todos los originales.").font(.caption).foregroundStyle(MemoraStyle.muted)
            }.padding(MemoraStyle.pagePadding)
        }.navigationBarTitleDisplayMode(.inline).memoraPage()
    }
}

private struct SessionView: View {
    @ObservedObject var store: MemoryStore
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: "Sesiones", subtitle: "Accesos autorizados")
                Panel { MemoryRow(symbol: "iphone", title: UIDevice.current.name, detail: "Sesión local actual", trailing: "Activa") }
                Panel {
                    Toggle(isOn: Binding(
                        get: { store.persistentSessionEnabled },
                        set: { enabled in
                            do { try store.setPersistentSession(enabled); error = nil }
                            catch let err { self.error = err.localizedDescription }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mantener sesión iniciada")
                            Text("La clave de sesión se guarda en Keychain sólo para este dispositivo.")
                                .font(.caption).foregroundStyle(MemoraStyle.muted)
                        }
                    }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Button("Cerrar esta sesión", role: .destructive) { store.logout() }.buttonStyle(MemoraButtonStyle())
            }.padding(MemoraStyle.pagePadding)
        }.navigationBarTitleDisplayMode(.inline).memoraPage()
    }
}

private struct RecoveryInfoView: View {
    var body: some View { InfoPage(title: "Recuperación", symbol: "key", message: "Memora muestra un código nuevo al crear o recuperar la cuenta. Guárdalo fuera de la app: permite volver a envolver la clave raíz sin que un servidor conozca tus archivos.") }
}
private struct PrivacyDetailView: View {
    var body: some View { InfoPage(title: "Procesamiento local", symbol: "iphone.and.arrow.forward", message: "Las personas se organizan manualmente en esta versión. Memora no afirma reconocer rostros ni crea embeddings hasta integrar y validar un modelo ejecutado completamente en el dispositivo.") }
}
private struct MetadataDetailView: View {
    var body: some View { InfoPage(title: "Metadatos", symbol: "location.slash", message: "Nombres, etiquetas, álbumes, personas y ubicaciones guardadas por Memora forman parte del manifiesto cifrado de la biblioteca.") }
}
struct FaceIDSettingsView: View {
    @ObservedObject var store: MemoryStore
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: "Modo Face ID", subtitle: "Autenticación biométrica en el dispositivo")

                Panel {
                    HStack(spacing: 16) {
                        Image(systemName: store.biometricType == .touchID ? "touchid" : "faceid")
                            .font(.system(size: 44, weight: .ultraLight))
                            .foregroundStyle(MemoraStyle.cream)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.biometricType.title)
                                .font(MemoraStyle.title(22))
                            Text(store.biometricAvailable
                                 ? "Disponible y listo para usar en este iPhone."
                                 : "No configurado o no disponible en este dispositivo.")
                                .font(.caption)
                                .foregroundStyle(MemoraStyle.muted)
                        }
                    }
                }

                SectionHeading(title: "Bloqueo de la aplicación")
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { store.appBiometricsEnabled },
                            set: { enabled in
                                Task {
                                    do {
                                        try await store.setAppBiometricsEnabled(enabled)
                                        error = nil
                                    } catch let err {
                                        self.error = err.localizedDescription
                                    }
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Requerir \(store.biometricType.title) al abrir")
                                    .font(.body)
                                Text("Solicita autenticación cada vez que abres la aplicación o vuelves de segundo plano.")
                                    .font(.caption)
                                    .foregroundStyle(MemoraStyle.muted)
                            }
                        }
                        .disabled(!store.biometricAvailable)
                    }
                }

                SectionHeading(title: "Bóveda privada")
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Face ID para la Bóveda")
                            Spacer()
                            Text(store.vaultConfigured ? "Disponible" : "Sin configurar")
                                .font(.caption)
                                .foregroundStyle(MemoraStyle.muted)
                        }
                        Text("Puedes activar el desbloqueo rápido con biometría directamente desde la Bóveda una vez creada.")
                            .font(.caption)
                            .foregroundStyle(MemoraStyle.muted)
                    }
                }

                SectionHeading(title: "Privacidad y seguridad")
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Enclave Seguro de Apple", systemImage: "lock.shield")
                            .font(.subheadline.weight(.semibold))
                        Text("Tu rostro y huella dactilar nunca son leídos ni almacenados por Memora. Todo el proceso es ejecutado de forma aislada por el Secure Enclave de iOS.")
                            .font(.caption)
                            .foregroundStyle(MemoraStyle.muted)
                    }
                }

                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(MemoraStyle.pagePadding)
        }
        .navigationBarTitleDisplayMode(.inline)
        .memoraPage()
    }
}

struct CloudflareBackupView: View {
    @ObservedObject var store: MemoryStore
    @State private var config = CloudflareBackupService.loadConfig()
    @State private var testing = false
    @State private var backingUp = false
    @State private var loadingBackups = false
    @State private var remoteBackups: [CloudflareRemoteBackup] = []
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var selectedRestoreBackup: CloudflareRemoteBackup?
    @State private var confirmingRestore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: "Copias a Cloudflare", subtitle: "Cifrado de extremo a extremo (E2EE)")

                Panel {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title)
                            .foregroundStyle(.mint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cifrado E2EE con AES-256-GCM")
                                .font(MemoraStyle.title(18))
                                .foregroundStyle(.white)
                            Text("Tus recuerdos, miniaturas y metadatos se cifran localmente con tu clave privada antes de enviarse. Cloudflare únicamente almacena datos binarios cifrados opacos que nadie más puede abrir.")
                                .font(.caption)
                                .foregroundStyle(MemoraStyle.muted)
                        }
                    }
                }

                SectionHeading(title: "Estado del respaldo")
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Última copia remota:")
                                .font(.subheadline)
                                .foregroundStyle(MemoraStyle.muted)
                            Spacer()
                            Text(store.lastCloudflareBackupDate?.formatted(date: .abbreviated, time: .shortened) ?? "Ninguna")
                                .font(.subheadline.weight(.semibold))
                        }
                        Divider()
                        HStack {
                            Text("Archivos locales:")
                                .font(.subheadline)
                                .foregroundStyle(MemoraStyle.muted)
                            Spacer()
                            Text("\(store.activeAssets.count) archivos (\(store.usedBytes.memorySize))")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }

                SectionHeading(title: "Configuración de Cloudflare R2")
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Account ID")
                                .font(.caption).foregroundStyle(MemoraStyle.muted)
                            TextField("Ej. a1b2c3d4e5f6...", text: $config.accountID)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nombre del Bucket R2")
                                .font(.caption).foregroundStyle(MemoraStyle.muted)
                            TextField("Ej. memora-backups", text: $config.bucketName)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Access Key ID (R2 Token)")
                                .font(.caption).foregroundStyle(MemoraStyle.muted)
                            TextField("Access Key ID", text: $config.accessKeyID)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Secret Access Key")
                                .font(.caption).foregroundStyle(MemoraStyle.muted)
                            SecureField("Secret Access Key", text: $config.secretAccessKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Toggle("Contraseña E2EE personalizada (Opcional)", isOn: $config.useCustomPassphrase)
                            .font(.subheadline)

                        if config.useCustomPassphrase {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Contraseña de cifrado E2EE")
                                    .font(.caption).foregroundStyle(MemoraStyle.muted)
                                SecureField("Usa al menos 12 caracteres", text: $config.customPassphrase)
                                    .textFieldStyle(.roundedBorder)
                                Text("Si la defines, necesitarás esta misma contraseña para restaurar la copia.")
                                    .font(.caption2).foregroundStyle(MemoraStyle.muted)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        testConnection()
                    } label: {
                        if testing {
                            ProgressView().tint(.white)
                        } else {
                            Label("Probar conexión", systemImage: "network")
                        }
                    }
                    .buttonStyle(MemoraButtonStyle())
                    .disabled(testing || backingUp)

                    Button {
                        performBackup()
                    } label: {
                        if backingUp {
                            ProgressView().tint(MemoraStyle.background)
                        } else {
                            Label("Hacer copia cifrada", systemImage: "arrow.clockwise.icloud.fill")
                        }
                    }
                    .buttonStyle(MemoraButtonStyle(prominent: true))
                    .disabled(testing || backingUp || !config.isConfigured)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(isError ? .red : .mint)
                        .padding(.horizontal, 4)
                }

                SectionHeading(title: "Copias cifradas en Cloudflare")
                if remoteBackups.isEmpty {
                    Button {
                        fetchRemoteBackups()
                    } label: {
                        if loadingBackups {
                            ProgressView().tint(.white)
                        } else {
                            Label("Buscar copias en Cloudflare", systemImage: "magnifyingglass")
                        }
                    }
                    .buttonStyle(MemoraButtonStyle())
                    .disabled(loadingBackups || !config.isConfigured)
                } else {
                    VStack(spacing: 8) {
                        ForEach(remoteBackups) { backup in
                            Panel {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(backup.formattedDate)
                                            .font(.body.weight(.semibold))
                                        Text("\(backup.formattedSize) · E2EE AES-256-GCM")
                                            .font(.caption).foregroundStyle(MemoraStyle.muted)
                                    }
                                    Spacer()
                                    Button("Restaurar") {
                                        selectedRestoreBackup = backup
                                        confirmingRestore = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(MemoraStyle.cream)
                                    .foregroundStyle(MemoraStyle.background)
                                }
                            }
                        }
                    }
                }
            }
            .padding(MemoraStyle.pagePadding)
            .padding(.bottom, 24)
        }
        .onChange(of: config) { _, newConfig in
            CloudflareBackupService.saveConfig(newConfig)
        }
        .onAppear {
            if config.isConfigured {
                fetchRemoteBackups()
            }
        }
        .confirmationDialog(
            "¿Restaurar copia desde Cloudflare?",
            isPresented: $confirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Descargar y descifrar copia", role: .destructive) {
                if let backup = selectedRestoreBackup {
                    restoreBackup(backup)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta acción sincronizará los recuerdos y metadatos contenidos en la copia cifrada seleccionada.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .memoraPage()
    }

    private func testConnection() {
        testing = true
        statusMessage = "Probando conexión con Cloudflare R2..."
        isError = false
        Task {
            do {
                try await CloudflareBackupService.testConnection(config: config)
                testing = false
                statusMessage = "Conexión exitosa con el bucket '\(config.bucketName)'."
                isError = false
                fetchRemoteBackups()
            } catch {
                testing = false
                statusMessage = error.localizedDescription
                isError = true
            }
        }
    }

    private func performBackup() {
        backingUp = true
        statusMessage = "Empaquetando y cifrando recuerdos con AES-256-GCM..."
        isError = false
        Task {
            do {
                let backup = try await CloudflareBackupService.performBackup(config: config, store: store)
                store.recordSuccessfulCloudflareBackup(date: backup.date)
                backingUp = false
                statusMessage = "¡Copia cifrada de extremo a extremo subida exitosamente! (\(backup.formattedSize))"
                isError = false
                fetchRemoteBackups()
            } catch {
                backingUp = false
                statusMessage = error.localizedDescription
                isError = true
            }
        }
    }

    private func fetchRemoteBackups() {
        guard config.isConfigured else { return }
        loadingBackups = true
        Task {
            do {
                let backups = try await CloudflareBackupService.listBackups(config: config)
                remoteBackups = backups
                loadingBackups = false
            } catch {
                loadingBackups = false
            }
        }
    }

    private func restoreBackup(_ backup: CloudflareRemoteBackup) {
        statusMessage = "Descargando y descifrando copia desde Cloudflare..."
        isError = false
        Task {
            do {
                try await CloudflareBackupService.restoreBackup(key: backup.key, config: config, store: store)
                statusMessage = "Copia cifrada restaurada con éxito."
                isError = false
            } catch {
                statusMessage = error.localizedDescription
                isError = true
            }
        }
    }
}
private struct AppearanceView: View {
    var body: some View { InfoPage(title: "Apariencia", symbol: "moon.stars", message: "Memora usa un tema oscuro de alto contraste, tipografía adaptable y controles de al menos 44 puntos para facilitar el uso en todos los tamaños de iPhone.") }
}

private struct InfoPage: View {
    let title: String
    let symbol: String
    let message: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MemoraHeader(title: title, subtitle: "Memora 0.5")
                Panel {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(MemoraStyle.cream)
                        Text(message).foregroundStyle(MemoraStyle.muted)
                    }.padding(.vertical, 8)
                }
            }.padding(MemoraStyle.pagePadding)
        }.navigationBarTitleDisplayMode(.inline).memoraPage()
    }
}
