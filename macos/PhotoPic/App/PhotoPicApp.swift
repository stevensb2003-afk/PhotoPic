import AppKit
import SwiftUI

/// Ensures native macOS window activation whether launched via Finder bundle or SwiftPM.
@MainActor
package final class PhotoPicAppDelegate: NSObject, NSApplicationDelegate {
    nonisolated package func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated package func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Top-level native macOS application scene and studio keyboard commands.
package struct PhotoPicApp: App {
    @NSApplicationDelegateAdaptor(PhotoPicAppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    package init() {}

    package var body: some Scene {
        WindowGroup {
            RootShellView(appState: appState)
                .frame(minWidth: 1080, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nueva Sesión de Filtrado...") {
                    if appState.activeSessionViewModel == nil && !appState.needsOnboarding {
                        appState.homeViewModel.prepareNewSessionSheet()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.needsOnboarding || appState.activeSessionViewModel != nil)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Dispositivos USB y Configuración...") {
                    appState.openSettings(tab: .devices)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Root window router rendering Onboarding, Home Dashboard, or Live Culling Workspace.
package struct RootShellView: View {
    @Bindable var appState: AppState

    package init(appState: AppState) {
        self.appState = appState
    }

    package var body: some View {
        ZStack(alignment: .top) {
            Group {
                if appState.needsOnboarding {
                    RootFolderOnboardingView(onChooseFolder: { appState.pickAndSetRootFolder() })
                } else if let workspaceVM = appState.activeSessionViewModel {
                    SessionWorkspaceView(appState: appState, viewModel: workspaceVM)
                } else {
                    HomeDashboardView(appState: appState)
                }
            }

            if let toast = activeToastMessage {
                FloatingToastBanner(message: toast)
                    .padding(.top, AppSpacing.topBarHeight + AppSpacing.md)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .onTapGesture {
                        appState.discoveryService.dismissToast()
                        appState.globalNoticeBanner = nil
                    }
            }
        }
        .animation(AppMotion.quickEaseOut, value: activeToastMessage)
        .sheet(isPresented: $appState.isPresentingSettings) {
            SettingsContainerSheet(appState: appState)
        }
        .onChange(of: appState.discoveryService.statusToastMessage) { _, newValue in
            guard newValue != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.5))
                if appState.discoveryService.statusToastMessage == newValue {
                    appState.discoveryService.dismissToast()
                }
            }
        }
    }

    private var activeToastMessage: String? {
        appState.discoveryService.statusToastMessage ?? appState.globalNoticeBanner
    }
}
