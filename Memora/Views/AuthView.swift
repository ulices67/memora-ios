import SwiftUI
import UIKit

struct AuthView: View {
    @ObservedObject var store: MemoryStore
    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var recovery = ""
    @State private var error: String?
    @State private var working = false
    @State private var showWipeWarning = false

    private enum Mode: String, CaseIterable, Hashable {
        case login = "Iniciar sesión"
        case register = "Crear cuenta"
        case recover = "Recuperar"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(MemoraStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    Text("MEMORA")
                        .font(.caption.weight(.semibold))
                        .tracking(3)
                        .foregroundStyle(MemoraStyle.cream)
                }
                .padding(.top, 28)

                Text(mode == .register ? "Aquí empieza tu historia." : "Tus recuerdos, contigo.")
                    .font(MemoraStyle.title(34))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Un lugar privado para guardar y volver a lo que más importa.")
                    .font(.subheadline)
                    .foregroundStyle(MemoraStyle.muted)

                Panel {
                    VStack(alignment: .leading, spacing: 15) {
                        if mode != .recover {
                            HStack(spacing: 6) {
                                ForEach([Mode.login, .register], id: \.self) { candidate in
                                    Button(candidate.rawValue) {
                                        mode = candidate
                                        error = nil
                                    }
                                    .font(.subheadline.weight(mode == candidate ? .semibold : .regular))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 44)
                                    .background(mode == candidate ? MemoraStyle.raised : .clear,
                                                in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .background(MemoraStyle.background, in: RoundedRectangle(cornerRadius: 12))
                        }

                        if mode == .register { input("Tu nombre", text: $name) }
                        input("Correo electrónico", text: $email, keyboard: .emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        if mode == .recover {
                            input("Código de recuperación", text: $recovery)
                            
                            Button {
                                if let code = store.fetchRecoveryCodeFromCloud(email: email) {
                                    recovery = code
                                    error = nil
                                } else {
                                    error = "No se encontró un código en iCloud para este correo."
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "icloud.and.arrow.down")
                                    Text("Cargar código de recuperación desde iCloud")
                                }
                                .font(.caption.weight(.medium))
                            }
                            .padding(.top, -5)
                            .padding(.bottom, 5)
                        }
                        
                        SecureField(mode == .recover ? "Contraseña nueva" : "Contraseña", text: $password)
                            .textContentType(mode == .login ? .password : .newPassword)
                            .frame(minHeight: MemoraStyle.controlHeight)
                            .padding(.horizontal, 14)
                            .background(MemoraStyle.background, in: RoundedRectangle(cornerRadius: 12))
                        if mode == .register {
                            SecureField("Confirmar contraseña", text: $confirmation)
                                .frame(minHeight: MemoraStyle.controlHeight)
                                .padding(.horizontal, 14)
                                .background(MemoraStyle.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Button { submit() } label: {
                            HStack {
                                if working { ProgressView().tint(.black) }
                                Text(mode == .login ? "Entrar a mi biblioteca" : mode == .register ? "Crear mi cuenta" : "Recuperar acceso")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        .buttonStyle(MemoraButtonStyle(prominent: true))
                        .disabled(working || email.isEmpty || password.isEmpty)

                        Button(mode == .recover ? "Volver a iniciar sesión" : "¿Olvidaste tu contraseña?") {
                            mode = mode == .recover ? .login : .recover
                            error = nil
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                    }
                }

                Text("Cuenta local en este iPhone. Al entrar, la sesión puede mantenerse mediante Keychain; puedes revocarla desde Perfil → Configuración → Dispositivos y sesiones.")
                    .font(.caption)
                    .foregroundStyle(MemoraStyle.muted)
                
                if store.hasAccount {
                    Button(role: .destructive) {
                        showWipeWarning = true
                    } label: {
                        Text("Restablecer cuenta local (Borrar todos los datos)")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                }
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, MemoraStyle.pagePadding)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .memoraPage()
        .alert("¿Borrar cuenta local?", isPresented: $showWipeWarning) {
            Button("Cancelar", role: .cancel) { }
            Button("Borrar todo", role: .destructive) {
                store.wipeLocalData()
                mode = .register
            }
        } message: {
            Text("Esto eliminará la base de datos de Memora de este iPhone. Es irreversible.")
        }
    }

    private func input(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textContentType(placeholder == "Correo electrónico" ? .emailAddress : .name)
            .frame(minHeight: MemoraStyle.controlHeight)
            .padding(.horizontal, 14)
            .background(MemoraStyle.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func submit() {
        working = true
        defer { working = false }
        do {
            switch mode {
            case .login:
                try store.login(email: email, password: password)
            case .register:
                guard password == confirmation else {
                    throw MemoraError.invalidInput("Las contraseñas no coinciden.")
                }
                _ = try store.register(name: name, email: email, password: password)
            case .recover:
                _ = try store.recover(email: email, code: recovery, newPassword: password)
            }
            password = ""
            confirmation = ""
            recovery = ""
        } catch let err {
            self.error = err.localizedDescription
        }
    }
}

struct RecoveryCodeView: View {
    @ObservedObject var store: MemoryStore
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "key.fill")
                    .font(.largeTitle)
                    .foregroundStyle(MemoraStyle.cream)
                Text("Tu llave de regreso")
                    .font(MemoraStyle.title(32))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Guarda este código fuera de Memora. Si olvidas la contraseña, será la única forma local de recuperar tu biblioteca.")
                    .font(.subheadline)
                    .foregroundStyle(MemoraStyle.muted)
                Panel {
                    Text(store.recoveryCode ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                Toggle("Ya guardé mi código en un lugar seguro", isOn: $saved)
                    .font(.subheadline)
                Button("Entrar a mi biblioteca") { store.recoveryCode = nil }
                    .buttonStyle(MemoraButtonStyle(prominent: true))
                    .disabled(!saved)
            }
            .frame(maxWidth: 440)
            .padding(22)
            .frame(maxWidth: .infinity)
        }
        .memoraPage()
    }
}
