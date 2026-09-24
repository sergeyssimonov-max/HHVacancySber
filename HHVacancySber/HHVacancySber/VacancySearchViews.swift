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
                statusBar
                Divider()
                if let warning = viewModel.favoritesWarning { warningView(warning) }
                if !viewModel.isShowingFavorites, let warning = viewModel.collectionWarning {
                    warningView(warning)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("collectionWarning")
                }
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

                Button {
                    if viewModel.isLoading { viewModel.cancelSearch() } else { refresh() }
                } label: {
                    Text(refreshButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(width: ToolbarMetrics.refreshWidth, height: ToolbarMetrics.controlHeight)
                .disabled(viewModel.isLoading ? !viewModel.canCancelSearch : !viewModel.canSearch)
                .help(viewModel.isLoading ? "Остановить загрузку; сохранится предыдущая полная выборка" : "")
                .accessibilityIdentifier("searchVacanciesButton")
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(DeskPalette.toolbar)
        }

        private var refreshButtonTitle: String {
            guard viewModel.isLoading else { return "Обновить выборку" }
            return viewModel.isCancellingSearch ? "Отмена…" : "Отменить загрузку"
        }

        private var favoritesExportTitle: String {
            guard viewModel.isExportingFavoritesPDF else { return "Экспортировать всё в PDF" }
            return viewModel.isCancellingFavoritesPDFExport ? "Отмена…" : "Отменить экспорт"
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
                empty(title: "СберВакансии", message: "Загрузите открытые вакансии настроенных работодателей группы Сбер по всей России.", action: "Обновить выборку")
            } else {
                results
            }
        }

        private var statusBar: some View {
            HStack(spacing: 12) {
                Text(viewModel.displayedVacancyCountMessage)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("displayedVacancyCount")
                Spacer()
                if viewModel.isShowingFavorites {
                    if let progress = viewModel.favoritesPDFExportProgress {
                        ProgressView(value: Double(progress.completedVacancies), total: Double(max(1, progress.totalVacancies))).frame(width: 90)
                    }
                    PDFExportCommand(title: favoritesExportTitle) {
                        if viewModel.isExportingFavoritesPDF {
                            viewModel.cancelFavoritesPDFExport()
                        } else {
                            viewModel.startFavoritesPDFExport()
                        }
                    }.disabled(viewModel.isExportingFavoritesPDF
                        ? !viewModel.canCancelFavoritesPDFExport
                        : !viewModel.canExportFavoritesPDF)
                        .accessibilityIdentifier("exportFavoritesPDFButton")
                }
                PDFExportCommand(title: viewModel.isExportingStatisticsPDF ? "Сохранение…" : "Статистика в PDF") {
                    Task { await viewModel.exportStatisticsPDF() }
                }
                .disabled(!viewModel.canExportStatisticsPDF)
                .help("Сохранить статистику и список вакансий под текущими фильтрами")
                .accessibilityIdentifier("exportStatisticsPDFButton")
            }
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .padding(.leading, 28)
            .padding(.trailing, 28)
            .frame(height: 48)
        }

        private var results: some View {
            VStack(spacing: 0) {
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
                Button(action: refresh) {
                    Text(action)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(width: ToolbarMetrics.refreshWidth, height: ToolbarMetrics.controlHeight)
                .accessibilityIdentifier("emptyRefreshVacanciesButton")
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
private struct PDFExportCommand: View {
    let title: String
    let action: () -> Void
    var textColor: Color = .primary

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .foregroundColor(textColor)
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var exported = false

    private var primaryText: Color {
        VacancyFieldPalette.primary(for: result.field, scheme: colorScheme)?.color ?? .primary
    }

    private var secondaryText: Color {
        VacancyFieldPalette.secondary(for: result.field, scheme: colorScheme)?.color ?? .secondary
    }

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
                    if result.field != .general {
                        Text(result.field == .informationSecurity ? "ИБ" : "IT · Данные · ИИ")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(primaryText)
                            .accessibilityLabel(result.field == .informationSecurity
                                ? "Направление: информационная безопасность"
                                : "Направление: IT, данные, искусственный интеллект и смежные технологии")
                            .accessibilityIdentifier("\(result.field == .informationSecurity ? "informationSecurityLabel" : "technologyBadge").\(result.id)")
                            .help(result.field == .informationSecurity
                                ? "Информационная безопасность и смежные направления. Определено автоматически по содержанию вакансии."
                                : "IT, данные, ИИ и смежные направления. Определено автоматически по содержанию вакансии.")
                    }
                    Text(result.employerName).font(.system(size: 13)).foregroundColor(secondaryText)
                    if let department = result.departmentName { Text(department).font(.caption).foregroundColor(secondaryText) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(result.salaryText ?? "Зарплата не указана").font(.system(size: 13))
                    Text(result.areaName).font(.caption).foregroundColor(secondaryText)
                }
            }
            HStack(spacing: 10) {
                Button("Открыть на hh.ru ↗", action: openURL).disabled(result.alternateURL == nil)
                Button(copied ? "✓ Скопировано" : "Скопировать ссылку") { if copyURL() { copied = true } }.disabled(result.alternateURL == nil)
                Button(isFavorite ? "★ В избранном" : "☆ В избранное", action: toggleFavorite)
                    .accessibilityIdentifier("favoriteVacancy.\(result.id)")
                Button(isExpanded ? "Скрыть детали" : "Подробнее", action: toggleDetails)
                    .accessibilityIdentifier("expandVacancy.\(result.id)")
                Spacer()
                PDFExportCommand(title: exported ? "✓ Сохранено" : "Экспорт в PDF", action: {
                    Task { if await exportPDF() { exported = true } }
                }, textColor: primaryText).disabled(exported)
                    .accessibilityIdentifier("exportVacancyPDF.\(result.id)")
            }.buttonStyle(.borderless)
                .foregroundColor(result.field != .general ? primaryText : nil)
                .tint(result.field != .general ? primaryText : nil)
            if isExpanded { details }
        }
        .foregroundColor(primaryText)
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
                VacancyHTMLDescriptionView(html: result.htmlDescription, field: result.field).frame(minHeight: 320)
            } else {
                Text("Полное описание вакансии отсутствует.").foregroundColor(secondaryText)
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
    static func make(from bodyHTML: String, field: VacancyField = .general) -> String {
        let body = VacancyHTMLAttributedText.sanitize(bodyHTML)
        let fieldStyle: String
        if let light = VacancyFieldPalette.primary(for: field, scheme: .light),
           let dark = VacancyFieldPalette.primary(for: field, scheme: .dark) {
            fieldStyle = """
            :root{--vacancy-text:\(light.css)}
            @media(prefers-color-scheme:dark){:root{--vacancy-text:\(dark.css)}}
            body,a{color:var(--vacancy-text)}
            """
        } else {
            fieldStyle = ""
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        :root{color-scheme:light dark} body{margin:14px;font:-apple-system-body;color:-apple-system-label;background:transparent;overflow-wrap:anywhere}
        a{color:-apple-system-link} img,table{max-width:100%;height:auto}
        \(fieldStyle)
        </style></head><body>\(body)</body></html>
        """
    }
}

struct VacancyHTMLDescriptionView: NSViewRepresentable {
    let html: String
    var field: VacancyField = .general
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent(); configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration); view.navigationDelegate = context.coordinator; view.underPageBackgroundColor = .clear; return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        // Match SwiftUI even when appearance is overridden locally; CSS updates without reloading.
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        guard context.coordinator.loaded != html || context.coordinator.field != field else { return }
        context.coordinator.loaded = html
        context.coordinator.field = field
        view.loadHTMLString(VacancyHTMLDocument.make(from: html, field: field), baseURL: nil)
    }
    // The async form matches WKNavigationDelegate on every SDK. The completion-handler
    // form only nearly matched the Xcode 16 signature and was then never called.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?
        var field: VacancyField?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.request.url?.scheme == "about" ? .allow : .cancel
        }
    }
}

// Opaque, muted tones keep small text readable on both native card backgrounds.
// Share exact sRGB values between SwiftUI and the HTML description.
enum VacancyFieldPalette {
    struct Tone {
        let rgb: UInt32
        var color: Color {
            Color(.sRGB, red: Double((rgb >> 16) & 0xff) / 255,
                  green: Double((rgb >> 8) & 0xff) / 255, blue: Double(rgb & 0xff) / 255)
        }
        var css: String { String(format: "#%06X", rgb) }
    }

    static func primary(for field: VacancyField, scheme: ColorScheme) -> Tone? {
        switch field {
        case .general: return nil
        case .technology: return Tone(rgb: scheme == .dark ? 0x8BC5CA : 0x176C74)
        case .informationSecurity: return Tone(rgb: scheme == .dark ? 0xDEB394 : 0x925235)
        }
    }

    static func secondary(for field: VacancyField, scheme: ColorScheme) -> Tone? {
        switch field {
        case .general: return nil
        case .technology: return Tone(rgb: scheme == .dark ? 0x91B6BB : 0x326F76)
        case .informationSecurity: return Tone(rgb: scheme == .dark ? 0xC7AD9B : 0x86624D)
        }
    }
}

private enum DeskPalette {
    static let content = Color(nsColor: .textBackgroundColor)
    static let toolbar = Color(nsColor: .windowBackgroundColor)
}
