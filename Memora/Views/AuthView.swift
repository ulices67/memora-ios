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

    private enum Mode: String, CaseIterable, Hashable { case login = "Iniciar sesión", register = "Crear cuenta", recover = "Recuperar" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title2).frame(width: 48, height: 48)
                        .background(MemoraStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                    Text("MEMORA").font(.caption.weight(.semibold)).tracking(3)
                        .foregroundStyle(MemoraStyle.cream)
                }
                .padding(.top, 54)

                Text(mode == .register ? "Aquí empieza tu historia." : "Tus recuerdos, contigo.")
                    .font(MemoraStyle.title(40))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Un lugar privado para guardar y volver a lo que más importa.")
                    .foregroundStyle(MemoraStyle.muted)

                Panel {
                    VStack(alignment: .leading, spacing: 16) {
                        if mode != .recover {
                            HStack(spacing: 6) {
                                ForEach([Mode.login, .register], id: \.self) { candidate in
                                    Button(candidate.rawValue) {
                                        mode = candidate
                                        error = nil
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
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
                        if mode == .recover { input("Código de recuperación", text: $recovery) }
                        SecureField(mode == .recover ? "Contraseña nueva" : "Contraseña", text: $password)
                            .textContentType(mode == .login ? .password : .newPassword)
                            .padding(14)
                            .background(MemoraStyle.background, in: RoundedRectangle(cornerRadius: 12))
                        if mode == .register {
                            SecureField("Confirmar contraseña", text: $confirmation)
                                .padding(14)
                                .background(MemoraStyle.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                        Button { submit() } label: {
                            HStack {
                                if working { ProgressView().tint(.black) }
                                Text(mode == .login ? "Entrar a mi biblioteca" : mode == .register ? "Crear mi cuenta" : "Recuperar acceso")
                            }
                        }
                        .buttonStyle(MemoraButtonStyle(prominent: true))
                        .disabled(working || email.isEmpty || password.isEmpty)

                        Button(mode == .recover ? "Volver a iniciar sesión" : "¿Olvidaste tu contraseña?") {
                            mode = mode == .recover ? .login : .recover
                            error = nil
                        }
                        .font(.caption).frame(maxWidth: .infinity)
                    }
                }
                Text("Cuenta local en este iPhone. Memora no envía correos ni sincroniza archivos entre dispositivos.")
                    .font(.caption).foregroundStyle(MemoraStyle.muted)
            }
            .frame(maxWidth: 460)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .memoraPage()
    }

    private func input(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textContentType(placeholder == "Correo electrónico" ? .emailAddress : .name)
            .padding(14)
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
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "key.fill").font(.largeTitle).foregroundStyle(MemoraStyle.cream)
            Text("Tu llave de regreso").font(MemoraStyle.title())
            Text("Guarda este código fuera de Memora. Si olvidas la contraseña, será la única forma local de recuperar tu biblioteca.")
                .foregroundStyle(MemoraStyle.muted)
            Panel {
                Text(store.recoveryCode ?? "")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            Toggle("Ya guardé mi código en un lugar seguro", isOn: $saved)
            Button("Entrar a mi biblioteca") { store.recoveryCode = nil }
                .buttonStyle(MemoraButtonStyle(prominent: true))
                .disabled(!saved)
        }
        .frame(maxWidth: 470)
        .padding(25)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .memoraPage()
    }
}
