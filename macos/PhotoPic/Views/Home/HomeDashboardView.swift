import SwiftUI

/// Screen 2: Home & Session Manager with persistent USB bar, New Session action, and disk history grid.
package struct HomeDashboardView: View {
    @Bindable var appState: AppState

    package init(appState: AppState) {
        self.appState = appState
    }

    package var body: some View {
        VStack(spacing: 0) {
            TopDeviceStatusBar(
                primaryDevice: appState.discoveryService.primaryLiveDevice,
                leadingTitle: "PhotoPic",
                leadingSubtitle: appState.rootFolderURL?.path,
                onTapDevicePill: { appState.openSettings(tab: .devices) },
                onTapSettings: { appState.openSettings(tab: .general) },
                onTapHelp: { appState.isPresentingHelp = true }
            )

            if let unknown = appState.discoveryService.unknownDeviceBanner {
                UnknownDeviceTopBanner(
                    device: unknown,
                    onConnectAndSave: { appState.discoveryService.connectAndSaveDevice(fingerprint: unknown.fingerprint) },
                    onDismiss: { appState.discoveryService.dismissUnknownBanner() }
                )
            }

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    headerActionsSection
                    sessionsHistorySection
                }
                .padding(AppSpacing.xl)
            }
        }
        .background(AppColors.windowCanvas)
        .sheet(isPresented: Binding(
            get: { appState.homeViewModel.isPresentingNewSessionSheet },
            set: { appState.homeViewModel.isPresentingNewSessionSheet = $0 }
        )) {
            NewSessionSheet(
                sessionName: Binding(
                    get: { appState.homeViewModel.newSessionNameDraft },
                    set: { appState.homeViewModel.newSessionNameDraft = $0 }
                ),
                rootFolderURL: appState.rootFolderURL,
                errorMessage: appState.homeViewModel.errorMessage,
                onCancel: { appState.homeViewModel.isPresentingNewSessionSheet = false },
                onCreate: { name in appState.createAndOpenSession(named: name) }
            )
        }
    }

    private var headerActionsSection: some View {
        HStack(alignment: .center, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("Sesiones de Estudio")
                    .font(AppTypography.displayTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Creá una sesión en vivo para recibir disparos por USB o reabrí cualquier carpeta previa.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button {
                appState.homeViewModel.reloadSessions(in: appState.rootFolderURL)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(StudioButtonStyle(.secondaryDark))
            .help("Actualizar contadores desde disco")

            Button {
                appState.homeViewModel.prepareNewSessionSheet()
            } label: {
                Label("Nueva Sesión de Filtrado", systemImage: "plus")
            }
            .buttonStyle(StudioButtonStyle(.primaryLight))
        }
    }

    @ViewBuilder
    private var sessionsHistorySection: some View {
        if appState.homeViewModel.sessions.isEmpty {
            emptySessionsState
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text("Historial en Carpeta Raíz")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("\(appState.homeViewModel.sessions.count) sesiones")
                        .font(AppTypography.monoCaption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: AppSpacing.cardGridMinWidth), spacing: AppSpacing.md)],
                    spacing: AppSpacing.md
                ) {
                    ForEach(appState.homeViewModel.sessions) { session in
                        SessionCardView(session: session) {
                            appState.openSession(session)
                        }
                    }
                }
            }
        }
    }

    private var emptySessionsState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "photo.stack")
                .font(AppTypography.displayTitle)
                .foregroundStyle(AppColors.textTertiary)

            Text("Todavía no hay sesiones en tu Carpeta Raíz")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text("Hacé clic en \"Nueva Sesión de Filtrado\" para crear las carpetas RAW, JPG, Para_Edicion y Archivadas y empezar a disparar.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Button {
                appState.homeViewModel.prepareNewSessionSheet()
            } label: {
                Label("Nueva Sesión de Filtrado", systemImage: "plus")
            }
            .buttonStyle(StudioButtonStyle(.primaryLight))
            .padding(.top, AppSpacing.xs)
        }
        .padding(.vertical, AppSpacing.xxxl)
        .frame(maxWidth: .infinity)
        .background(AppColors.panelSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: AppSpacing.hairline)
        )
    }
}
