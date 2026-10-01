import Combine
import SwiftUI

@main
struct MemoraApp: App {
    @StateObject private var store = MemoryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.authenticated {
                    if store.recoveryCode != nil {
                        RecoveryCodeView(store: store)
                    } else {
                        MainTabs(store: store)
                    }
                } else {
                    AuthView(store: store)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { store.lockVault() }
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
