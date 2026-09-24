import SwiftUI

enum WindowLayoutPolicy {
    static let minimumSize = CGSize(width: 900, height: 560)
    static let defaultSize = CGSize(width: 960, height: 680)
}

struct ContentView: View {
    @ObservedObject private var viewModel: VacancySearchViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let archiveCheckTimer = Timer.publish(
        every: VacancySearchViewModel.archiveCheckInterval,
        on: .main,
        in: .common
    ).autoconnect()

    init(viewModel: VacancySearchViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VacancySearchViews.MainWindow(
            viewModel: viewModel,
            refresh: { viewModel.startRefresh() }
        )
        .frame(
            minWidth: WindowLayoutPolicy.minimumSize.width,
            minHeight: WindowLayoutPolicy.minimumSize.height
        )
        .task {
            await viewModel.loadPersistenceIfNeeded()
            await viewModel.checkArchiveStatusesIfNeeded()
        }
        .onReceive(archiveCheckTimer) { _ in
            Task { await viewModel.checkArchiveStatusesIfNeeded() }
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task { await viewModel.checkArchiveStatusesIfNeeded() }
        }
    }
}
