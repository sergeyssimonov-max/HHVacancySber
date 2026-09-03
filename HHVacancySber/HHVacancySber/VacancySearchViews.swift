import SwiftUI
import WebKit

enum VacancySearchViews {
    struct MainWindow: View {
        @ObservedObject var viewModel: VacancySearchViewModel
        let refresh: () -> Void

        private enum ToolbarMetrics {
            static let controlHeight: CGFloat = 32
            static let modeWidth: CGFloat = 220
            static let statusWidth: CGFloat = 140
            static let refreshWidth: CGFloat = 160
        }

        var body: some View {
            VStack(spacing: 0) {
                toolbar
                Divider()
                if let warning = viewModel.favoritesWarning { warningView(warning) }
                content
            }
            .background(DeskPalette.content)
        }

        private var toolbar: some View {
            HStack(spacing: 12) {
                Picker("", selection: $viewModel.displayMode) {
                    Text("Вакансии").tag(VacancyListMode.all)
                    Text(viewModel.favorites.isEmpty ? "Избранное" : "Избранное · \(viewModel.favorites.count)").tag(VacancyListMode.favorites)
                }
                .pickerStyle(.segmented)
                .frame(width: ToolbarMetrics.modeWidth, height: ToolbarMetrics.controlHeight)
                .accessibilityIdentifier("vacancyListModePicker")

                Picker("Работодатель", selection: $viewModel.selectedEmployerID) {
                    ForEach(viewModel.employerFilterOptions) { Text($0.title).tag($0.id) }
                }
                .labelsHidden()
                .frame(minWidth: 150, maxWidth: .infinity)
                .frame(height: ToolbarMetrics.controlHeight)
                .accessibilityIdentifier("employerFilterPicker")

                Picker("Субъект", selection: $viewModel.selectedRegionID) {
                    ForEach(viewModel.regionFilterOptions) { Text($0.title).tag($0.id) }
                }
                .labelsHidden()
                .frame(minWidth: 150, maxWidth: .infinity)
                .frame(height: ToolbarMetrics.controlHeight)
                .accessibilityIdentifier("regionFilterPicker")

                Text(viewModel.updatedAtMessage ?? " ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: ToolbarMetrics.statusWidth, height: ToolbarMetrics.controlHeight, alignment: .trailing)
                    .accessibilityHidden(viewModel.updatedAtMessage == nil)
                    .accessibilityIdentifier("vacancyUpdateStatus")

                Button(viewModel.isLoading ? "Обновление…" : "Обновить выборку", action: refresh)
                    .buttonStyle(.borderedProminent)
                    .frame(width: ToolbarMetrics.refreshWidth, height: ToolbarMetrics.controlHeight)
                    .disabled(!viewModel.canSearch)
                    .accessibilityIdentifier("searchVacanciesButton")
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(DeskPalette.toolbar)
        }

        @ViewBuilder private var content: some View {
            if viewModel.isLoading && viewModel.displayedResults.isEmpty {
                VStack(spacing: 12) { ProgressView(); Text("Загружаем вакансии всех настроенных работодателей…") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.displayedResults.isEmpty {
                empty(title: "Не удалось загрузить вакансии", message: error, action: "Повторить")
            } else if viewModel.hasSearched && viewModel.displayedResults.isEmpty {
                empty(title: "Вакансий не найдено", message: "Для выбранных работодателей и фильтров вакансий сейчас нет.", action: "Обновить")
            } else if !viewModel.hasSearched && viewModel.displayedResults.isEmpty {
                empty(title: "СберВакансии", message: "Загрузите открытые вакансии настроенных работодателей группы Сбер по всей России.", action: "Загрузить")
            } else {
                results
            }
        }

        private var results: some View {
            VStack(spacing: 0) {
                HStack {
                    Text(viewModel.displayedVacancyCountMessage)
                        .accessibilityIdentifier("displayedVacancyCount")
                    if viewModel.isLoading, let status = viewModel.statusMessage {
                        Text("· \(status)")
                    }
                    Spacer()
                    if viewModel.isShowingFavorites {
                        if let progress = viewModel.favoritesPDFExportProgress {
                            ProgressView(value: Double(progress.completedVacancies), total: Double(max(1, progress.totalVacancies))).frame(width: 90)
                        }
                        Button(viewModel.isExportingFavoritesPDF ? "Экспорт…" : "Экспортировать всё в PDF") {
                            Task { await viewModel.exportFavoriteVacanciesPDF() }
                        }.disabled(!viewModel.canExportFavoritesPDF)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 28)
                .frame(height: 40)
                Divider()
                if let error = viewModel.errorMessage { warningView(error) }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.displayedResults) { result in
                            VacancyCard(
                                result: result,
                                isFavorite: viewModel.isFavorite(id: result.id),
                                isExpanded: viewModel.expandedVacancyID == result.id,
                                toggleFavorite: { viewModel.toggleFavorite(id: result.id) },
                                toggleDetails: { viewModel.toggleExplanation(for: result.id) },
                                openURL: { viewModel.openVacancyURL(id: result.id) },
                                copyURL: { viewModel.copyVacancyURL(id: result.id) },
                                exportPDF: { await viewModel.exportVacancyPDF(id: result.id) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }

        private func warningView(_ text: String) -> some View {
            HStack { Label(text, systemImage: "exclamationmark.triangle"); Spacer() }
                .font(.caption).foregroundColor(.secondary).padding(.horizontal, 28).padding(.vertical, 10)
        }

        private func empty(title: String, message: String, action: String) -> some View {
            VStack(spacing: 12) {
                Text(title).font(.headline)
                Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
                Button(action, action: refresh).buttonStyle(.borderedProminent)
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
private struct VacancyCard: View {
    let result: VacancySearchResult
    let isFavorite: Bool
    let isExpanded: Bool
    let toggleFavorite: () -> Void
    let toggleDetails: () -> Void
    let openURL: () -> Void
    let copyURL: () -> Bool
    let exportPDF: () async -> Bool
    @State private var copied = false
    @State private var exported = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(result.name)
                            .font(.system(size: 15, weight: .semibold))
                            .accessibilityIdentifier("vacancyTitle.\(result.id)")
                        if result.isArchived { Label("В архиве", systemImage: "archivebox").font(.caption) }
                    }
                    Text(result.employerName).font(.system(size: 13)).foregroundColor(.secondary)
                    if let department = result.departmentName { Text(department).font(.caption).foregroundColor(.secondary) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(result.salaryText ?? "Зарплата не указана").font(.system(size: 13))
                    Text(result.areaName).font(.caption).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button("Открыть на hh.ru ↗", action: openURL).disabled(result.alternateURL == nil)
                Button(copied ? "✓ Скопировано" : "Скопировать ссылку") { if copyURL() { copied = true } }.disabled(result.alternateURL == nil)
                Button(isFavorite ? "★ В избранном" : "☆ В избранное", action: toggleFavorite)
                Button(isExpanded ? "Скрыть детали" : "Подробнее", action: toggleDetails)
                    .accessibilityIdentifier("expandVacancy.\(result.id)")
                Spacer()
                Button(exported ? "✓ Сохранено" : "Экспорт в PDF") {
                    Task { if await exportPDF() { exported = true } }
                }.disabled(exported)
            }.buttonStyle(.borderless)
            if isExpanded { details }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if result.isDetailLoading {
                Label("Загружаем полное описание…", systemImage: "hourglass")
            } else if let error = result.detailErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
            } else if result.hasFullDescription {
                VacancyHTMLDescriptionView(html: result.htmlDescription).frame(minHeight: 320)
            } else {
                Text("Полное описание вакансии отсутствует.").foregroundColor(.secondary)
            }
        }
        .font(.caption)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskPalette.toolbar)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct VacancyHTMLDocument {
    static func make(from bodyHTML: String) -> String {
        let body = VacancyHTMLAttributedText.sanitize(bodyHTML)
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        :root{color-scheme:light dark} body{margin:14px;font:-apple-system-body;color:-apple-system-label;background:transparent;overflow-wrap:anywhere}
        a{color:-apple-system-link} img,table{max-width:100%;height:auto}
        </style></head><body>\(body)</body></html>
        """
    }
}

struct VacancyHTMLDescriptionView: NSViewRepresentable {
    let html: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent(); configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration); view.navigationDelegate = context.coordinator; view.underPageBackgroundColor = .clear; return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html; view.loadHTMLString(VacancyHTMLDocument.make(from: html), baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }
}

private enum DeskPalette {
    static let content = Color(nsColor: .textBackgroundColor)
    static let toolbar = Color(nsColor: .windowBackgroundColor)
}
