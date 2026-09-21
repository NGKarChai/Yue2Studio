import SwiftUI

public struct MainView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $appState.currentTab) {
                    ForEach(AppState.NavigationTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.iconName)
                            .tag(tab)
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            } detail: {
                switch appState.currentTab {
                case .studio:
                    GenerationView(appState: appState)
                case .models:
                    ModelManagerView(appState: appState)
                case .history:
                    HistoryView(appState: appState)
                case .settings:
                    SettingsView(appState: appState)
                }
            }

            // Fixed Footer with Build Number and Live Hardware Monitor
            BuildFooterView(appState: appState)
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}
