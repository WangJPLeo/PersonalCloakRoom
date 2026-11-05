import SwiftUI

@main
@MainActor
struct CloakRoomApp: App {
    @StateObject private var model = MobileSession()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            MobileContentView(model: model).tint(.mint)
                .onChange(of: phase) { _, value in if value == .active { model.reload() } }
        }
    }
}

@MainActor
struct MobileContentView: View {
    @ObservedObject var model: MobileSession
    @State private var settings = false
    @State private var gallery = false
    var body: some View {
        TabView {
            NavigationStack {
                MobileTryonPage(model: model, chooseCatalog: { gallery = true })
                    .navigationTitle("衣橱快截")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("设置") { settings = true }.disabled(model.busy) } }
            }.tabItem { Label("换装", systemImage: "tshirt") }
            MobileHistoryView(model: model).tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
        }
        .sheet(isPresented: $settings) { MobileSettingsView(model: model) }
        .sheet(isPresented: $gallery) { MobileCatalogView(model: model) }
    }
}
