import SwiftUI

/// Programmatic navigation destinations.
enum Screen: Hashable {
    case splitRouting
    case geoLock
    case logs
}

@main
struct RouteMasterApp: App {
    @StateObject private var vm = ConfigViewModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(vm)
                .frame(minWidth: 720, minHeight: 560)
                .onAppear { vm.onAppear() }
        }
        .windowStyle(.hiddenTitleBar)

        // MenuBarExtra: quick controls + live location/geo state.
        MenuBarExtra("RouteMaster", systemImage: vm.engineRunning ? "bolt.horizontal.circle.fill"
                                                                   : "bolt.horizontal.circle") {
            MenuBarView()
                .environmentObject(vm)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Root window: dashboard + programmatic navigation to the other screens.
struct RootView: View {
    @EnvironmentObject var vm: ConfigViewModel
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                NeonBackground()
                DashboardView(path: $path)
            }
            .navigationTitle("RouteMaster")
            .navigationDestination(for: Screen.self) { screen in
                ZStack {
                    NeonBackground()
                    switch screen {
                    case .splitRouting: SplitRoutingView()
                    case .geoLock:      GeoLockView()
                    case .logs:         LogsView()
                    }
                }
            }
        }
    }
}
