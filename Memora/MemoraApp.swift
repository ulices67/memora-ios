import Combine
import SwiftUI

@main
struct MemoraApp: App {
    @StateObject private var store = MemoryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                MemoraStyle.background
                    .ignoresSafeArea()

                Group {
                    if store.authenticated {
                        if store.appBiometricsEnabled && store.appLocked {
                            AppBiometricLockView(store: store)
                        } else if store.recoveryCode != nil {
                            RecoveryCodeView(store: store)
                        } else {
                            MainTabs(store: store)
                        }
                    } else {
                        AuthView(store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MemoraStyle.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    store.lockVault()
                    store.lockApp()
                } else if store.authenticated && store.appBiometricsEnabled && store.appLocked {
                    Task { _ = await store.unlockAppWithBiometrics() }
                }
            }
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                store.checkVaultDeadline()
            }
            .alert("Memora", isPresented: Binding(
                get: { store.notice != nil },
                set: { if !$0 { store.notice = nil } }
            )) {
                Button("Entendido") { store.notice = nil }
            } message: {
                Text(store.notice ?? "")
            }
        }
    }
}

struct AppBiometricLockView: View {
    @ObservedObject var store: MemoryStore
    @State private var showingPasswordPrompt = false
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: store.biometricType == .touchID ? "touchid" : "faceid")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(MemoraStyle.cream)
                .padding(.bottom, 8)

            Text("Memora")
                .font(MemoraStyle.title(36))
                .foregroundStyle(.white)

            Text("Biblioteca protegida con \(store.biometricType.title)")
                .font(.subheadline)
                .foregroundStyle(MemoraStyle.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { _ = await store.unlockAppWithBiometrics() }
                } label: {
                    Label("Desbloquear con \(store.biometricType.title)",
                          systemImage: store.biometricType == .touchID ? "touchid" : "faceid")
                }
                .buttonStyle(MemoraButtonStyle(prominent: true))

                Button("Usar contraseña de cuenta") {
                    password = ""
                    showingPasswordPrompt = true
                }
                .font(.subheadline)
                .foregroundStyle(MemoraStyle.muted)
                .padding(.top, 4)

                Button("Cerrar sesión / Cambiar cuenta") {
                    store.logout()
                }
                .font(.caption)
                .foregroundStyle(MemoraStyle.muted)
                .padding(.top, 2)
            }
            .padding(.horizontal, MemoraStyle.pagePadding)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: 440)
        .memoraPage()
        .onAppear {
            Task { _ = await store.unlockAppWithBiometrics() }
        }
        .alert("Desbloquear con contraseña", isPresented: $showingPasswordPrompt) {
            SecureField("Contraseña de cuenta", text: $password)
            Button("Desbloquear") {
                do {
                    try store.unlockAppWithPassword(password)
                    password = ""
                } catch {
                    store.notice = "Contraseña incorrecta."
                }
            }
            Button("Cancelar", role: .cancel) { password = "" }
        } message: {
            Text("Ingresa tu contraseña de Memora para acceder.")
        }
    }
}
