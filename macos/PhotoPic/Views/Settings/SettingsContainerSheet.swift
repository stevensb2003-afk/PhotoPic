import SwiftUI

/// Screen 4: Clean two-section Settings & Device Manager modal sheet.
package struct SettingsContainerSheet: View {
    @Bindable var appState: AppState

    package init(appState: AppState) {
        self.appState = appState
    }

    package var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.md) {
                Text("Configuración")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Picker("Sección", selection: $appState.settingsTab) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)

                Spacer()

                Button("Listo") {
                    appState.isPresentingSettings = false
                }
                .buttonStyle(StudioButtonStyle(.primaryLight, compact: true))
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
            .background(AppColors.panelSurface)
            .overlay(
                Rectangle()
                    .frame(height: AppSpacing.hairline)
                    .foregroundStyle(AppColors.borderSubtle),
                alignment: .bottom
            )

            Group {
                switch appState.settingsTab {
                case .devices:
                    DeviceManagerView(viewModel: appState.deviceManagerViewModel)
                case .general:
                    GeneralSettingsView(
                        rootFolderURL: appState.rootFolderURL,
                        onChangeRootFolder: { appState.pickAndSetRootFolder() }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.windowCanvas)
        }
        .frame(width: AppSpacing.settingsWidth, height: AppSpacing.settingsHeight)
    }
}
