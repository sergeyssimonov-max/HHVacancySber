import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum VacancyListMode: String, CaseIterable, Identifiable {
    case all = "Все вакансии"
    case favorites = "Избранное"
    var id: String { rawValue }
}

enum VacancySortOrder: String, CaseIterable, Identifiable {
    case newest = "Сначала новые"
    case employer = "По работодателю"
    case subject = "По субъекту"
    var id: String { rawValue }
}

struct VacancyFilterOption: Identifiable, Equatable {
    let id: String
    let title: String
}

private struct VacancySearchCache {
    let values: [VacancySearchResult]
    let updatedAt: Date
}

@MainActor
final class VacancySearchViewModel: ObservableObject {
    static let searchCacheTTL: TimeInterval = 10 * 60
    static let archiveCheckInterval: TimeInterval = 30 * 60

    @Published private(set) var results: [VacancySearchResult] = []
    @Published private(set) var favorites: [FavoriteVacancyRecord] = []
    @Published private(set) var expandedVacancyID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isPersistenceLoaded = false
    @Published private(set) var isExportingFavoritesPDF = false
    @Published private(set) var favoritesPDFExportProgress: FavoritePDFExportProgress?
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var updatedAtMessage: String?
    @Published private(set) var favoritesWarning: String?
    @Published private(set) var hasSearched = false
    @Published var displayMode: VacancyListMode = .all { didSet { reconcileExpanded() } }
    @Published var selectedEmployerID = "all" { didSet { reconcileExpanded() } }
    @Published var selectedRegionID = "all" { didSet { reconcileExpanded() } }
    @Published var sortOrder: VacancySortOrder = .newest

    private let apiClient: any HHVacancyAPIClient
    private let employerStore: any EmployerConfigurationStoring
    private let areaStore: AreaDirectoryStore
    private let favoritesStore: any FavoriteVacancyStoring
    private let favoritePDFExporter: any FavoriteVacanciesPDFExporting
    private let currentDate: @Sendable () -> Date
    private var detailsCache: [String: HHVacancyDetails] = [:]
    private var cache: VacancySearchCache?
    private var detailTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var pendingPersistenceSnapshot: (revision: Int, values: [FavoriteVacancyRecord])?
    private var persistenceRevision = 0
    private var isPersistenceDriverRunning = false

    init(
        apiClient: any HHVacancyAPIClient = HHAPIClient(),
        employerStore: any EmployerConfigurationStoring,
        areaStore: AreaDirectoryStore = AreaDirectoryStore(),
        favoritesStore: any FavoriteVacancyStoring = InMemoryFavoriteVacancyStore(),
        favoritePDFExporter: (any FavoriteVacanciesPDFExporting)? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.apiClient = apiClient
        self.employerStore = employerStore
        self.areaStore = areaStore
        self.favoritesStore = favoritesStore
        self.favoritePDFExporter = favoritePDFExporter ?? FavoriteVacanciesPDFExporter()
        self.currentDate = currentDate
    }

    deinit { detailTask?.cancel(); saveTask?.cancel() }

    var canSearch: Bool { isPersistenceLoaded && !isLoading }
    var isShowingFavorites: Bool { displayMode == .favorites }
    var canExportFavoritesPDF: Bool { !favorites.isEmpty && !isExportingFavoritesPDF }

    var employerFilterOptions: [VacancyFilterOption] {
        let values = Dictionary(grouping: unfilteredResults.compactMap { result -> VacancyFilterOption? in
            guard let id = result.employerID else { return nil }
            return VacancyFilterOption(id: id, title: result.employerName)
        }, by: \.id).compactMap { $0.value.first }
        return [.init(id: "all", title: "Все работодатели")] + values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var regionFilterOptions: [VacancyFilterOption] {
        let values = Dictionary(grouping: unfilteredResults.map {
            VacancyFilterOption(id: $0.location.filterID, title: $0.location.kind == .subject ? ($0.location.subjectName ?? $0.areaName) : $0.areaName)
        }, by: \.id).compactMap { $0.value.first }
        return [.init(id: "all", title: "Все регионы")] + values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var displayedResults: [VacancySearchResult] {
        unfilteredResults
            .filter { selectedEmployerID == "all" || $0.employerID == selectedEmployerID }
            .filter { selectedRegionID == "all" || $0.location.filterID == selectedRegionID }
            .sorted(by: sortPredicate)
    }

    var expandedVacancy: VacancySearchResult? { displayedResults.first { $0.id == expandedVacancyID } }
    func isFavorite(id: String) -> Bool { favorites.contains { $0.id == id } }

    private var unfilteredResults: [VacancySearchResult] {
        switch displayMode {
        case .all: return results
        case .favorites:
            let live = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
            return favorites.map { live[$0.id] ?? $0.searchResult }
        }
    }

    func loadPersistenceIfNeeded() async {
        guard !isPersistenceLoaded else { return }
        do { favorites = try favoritesStore.load().sorted { $0.favoritedAt > $1.favoritedAt } }
        catch { favoritesWarning = error.localizedDescription }
        isPersistenceLoaded = true
    }

    func search() async { await performSearch(useCache: true) }
    func refreshVacancies() async { await performSearch(useCache: false) }

    private func performSearch(useCache: Bool) async {
        await loadPersistenceIfNeeded()
        guard !isLoading else { return }
        let now = currentDate()
        if useCache, let cache, now.timeIntervalSince(cache.updatedAt) >= 0,
           now.timeIntervalSince(cache.updatedAt) < Self.searchCacheTTL {
            results = cache.values
            hasSearched = true
            updatedAtMessage = timeMessage(cache.updatedAt)
            statusMessage = "Показана сохранённая полная выборка."
            return
        }
        do { try apiClient.validateVacanciesAccess() }
        catch { hasSearched = true; errorMessage = error.localizedDescription; statusMessage = "Поиск не завершён."; return }

        isLoading = true
        hasSearched = true
        errorMessage = nil
        let previous = results
        defer { isLoading = false }
        do {
            let employers = try employerStore.loadOrCreate().employers
            statusMessage = "Загружается справочник регионов."
            let areaSnapshot = try await areaStore.load(using: apiClient)
            if let warning = areaSnapshot.warning { statusMessage = warning }
            let collector = VacancyCollectionService(client: apiClient, now: currentDate)
            let summaries = try await collector.collect(employers: employers, areas: areaSnapshot.index) { [weak self] progress in
                self?.statusMessage = "\(progress.employerName): загружено \(progress.loadedCount), \(progress.partition)."
            }
            try Task.checkCancellation()
            let values = summaries.map { summary -> VacancySearchResult in
                let fallback = HHVacancyDetails(
                    id: summary.id,
                    name: summary.name,
                    employer: summary.employer,
                    area: summary.area,
                    salary: summary.salary,
                    alternateURL: summary.alternateURL,
                    description: nil,
                    schedule: summary.schedule,
                    workFormat: summary.workFormat,
                    department: summary.department
                )
                return VacancySearchResult(
                    id: summary.id,
                    summary: summary,
                    details: fallback,
                    location: areaSnapshot.index.location(for: summary)
                )
            }
            results = values
            cache = VacancySearchCache(values: values, updatedAt: now)
            updatedAtMessage = timeMessage(now)
            statusMessage = values.isEmpty ? "У выбранных работодателей нет открытых вакансий." : "Готово: \(values.count) уникальных вакансий."
            normalizeFilters()
        } catch is CancellationError {
            results = previous
            statusMessage = "Поиск отменён."
        } catch {
            results = previous
            errorMessage = error.localizedDescription
            statusMessage = "Поиск не завершён; сохранена предыдущая полная выборка."
        }
    }

    func toggleExplanation(for id: String) {
        if expandedVacancyID == id { expandedVacancyID = nil; detailTask?.cancel(); return }
        expandedVacancyID = id
        detailTask?.cancel()
        detailTask = Task { [weak self] in await self?.loadVacancyDetails(id: id) }
    }

    func scheduleVacancyDetailsLoad(id: String) { toggleExplanation(for: id) }

    func loadVacancyDetails(id: String) async {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        if let cached = detailsCache[id] { apply(details: cached, at: index); return }
        let current = results[index]
        results[index] = current.updatingDetailState(isLoading: true, errorMessage: nil)
        do {
            let details = try await apiClient.vacancyDetails(id: id)
            try Task.checkCancellation()
            detailsCache[id] = details
            guard let newIndex = results.firstIndex(where: { $0.id == id }) else { return }
            apply(details: details, at: newIndex)
        } catch is CancellationError {
            if let newIndex = results.firstIndex(where: { $0.id == id }) {
                results[newIndex] = results[newIndex].updatingDetailState(isLoading: false, errorMessage: nil)
            }
        } catch {
            if let newIndex = results.firstIndex(where: { $0.id == id }) {
                results[newIndex] = results[newIndex].updatingDetailState(isLoading: false, errorMessage: "Не удалось загрузить описание: \(error.localizedDescription)")
            }
        }
    }

    private func apply(details: HHVacancyDetails, at index: Int) {
        let old = results[index]
        let value = VacancySearchResult(
            id: old.id,
            summary: old.summary,
            details: details,
            location: old.location,
            isDetailLoaded: true,
            persistedSalaryText: old.persistedSalaryText,
            isArchived: details.archived ?? old.isArchived,
            archiveCheckedAt: details.archived == nil ? old.archiveCheckedAt : currentDate()
        )
        results[index] = value
        if let favoriteIndex = favorites.firstIndex(where: { $0.id == value.id }), favorites[favoriteIndex].update(from: value, at: currentDate()) {
            persistFavorites()
        }
        statusMessage = "Описание вакансии загружено."
    }

    func toggleFavorite(id: String) {
        if let index = favorites.firstIndex(where: { $0.id == id }) { favorites.remove(at: index); persistFavorites(); reconcileExpanded(); return }
        guard let value = unfilteredResults.first(where: { $0.id == id }) else { return }
        let now = currentDate()
        favorites.append(.init(result: value, favoritedAt: now, updatedAt: now, archiveCheckedAt: value.archiveCheckedAt))
        favorites.sort { $0.favoritedAt > $1.favoritedAt }
        persistFavorites()
    }

    private func persistFavorites() {
        persistenceRevision += 1
        pendingPersistenceSnapshot = (persistenceRevision, favorites)
        guard !isPersistenceDriverRunning else { return }
        isPersistenceDriverRunning = true
        saveTask = Task { [weak self] in await self?.runPersistenceDriver() }
    }

    private func runPersistenceDriver() async {
        let store = favoritesStore
        while let pending = pendingPersistenceSnapshot {
            pendingPersistenceSnapshot = nil
            do {
                try await Task.detached { try store.save(pending.values) }.value
                if pending.revision == persistenceRevision, pendingPersistenceSnapshot == nil {
                    favoritesWarning = nil
                }
            } catch {
                if pending.revision == persistenceRevision, pendingPersistenceSnapshot == nil {
                    favoritesWarning = "Не удалось сохранить избранное: \(error.localizedDescription)"
                }
            }
        }
        isPersistenceDriverRunning = false
        saveTask = nil
    }

    func retryFavoritesPersistence() { persistFavorites() }
    func waitForPendingFavoritesSaves() async {
        while let task = saveTask { await task.value }
    }

    func checkArchiveStatusesIfNeeded() async {
        await loadPersistenceIfNeeded()
        let due = currentDate().addingTimeInterval(-Self.archiveCheckInterval)
        for id in Set(favorites.filter { ($0.archiveCheckedAt ?? .distantPast) < due }.map(\.id)) {
            do {
                let details = try await apiClient.vacancyDetails(id: id)
                guard let archived = details.archived, let index = favorites.firstIndex(where: { $0.id == id }) else { continue }
                favorites[index].updateArchiveStatus(archived, checkedAt: currentDate())
            } catch { break }
        }
        persistFavorites()
    }

    func openVacancyURL(id: String) {
        guard let raw = result(id)?.alternateURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func copyVacancyURL(id: String) -> Bool {
        guard let raw = result(id)?.alternateURL else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(raw, forType: .string)
    }

    @discardableResult
    func exportVacancyPDF(id: String) async -> Bool {
        guard let source = result(id) else { return false }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.canCreateDirectories = true
        panel.nameFieldStringValue = VacancyPDFDefaults.personalFileName(vacancyID: source.id, vacancyName: source.name)
        guard panel.runModal() == .OK, let destination = panel.url else { return false }
        do {
            let prepared = try await preparedForPDF(source)
            let worker = PDFExportWorker(fileManager: PDFFileManager(.default))
            try await worker.exportPersonal(document: PDFAttributedDocument(VacancyPDFFormatter.attributedDocument(for: prepared)), destination: destination)
            statusMessage = "Вакансия сохранена в PDF."
            return true
        } catch { statusMessage = "Не удалось сохранить PDF."; return false }
    }

    func exportFavoriteVacanciesPDF() async {
        guard canExportFavoritesPDF else { return }
        isExportingFavoritesPDF = true
        defer { isExportingFavoritesPDF = false; favoritesPDFExportProgress = nil }
        do {
            var values: [VacancySearchResult] = []
            for (index, favorite) in favorites.enumerated() {
                values.append(try await preparedForPDF(result(favorite.id) ?? favorite.searchResult))
                favoritesPDFExportProgress = .init(completedVacancies: index + 1, totalVacancies: favorites.count)
            }
            let outcome = try await favoritePDFExporter.export(vacancies: values) { [weak self] in self?.favoritesPDFExportProgress = $0 }
            switch outcome {
            case .cancelled: break
            case .exported(let files, let pages): statusMessage = "Сохранено PDF: \(files), страниц: \(pages)."
            case .exportedWithCleanupWarning(let files, let pages, let directory):
                statusMessage = "Сохранено PDF: \(files), страниц: \(pages). Служебный каталог: \(directory.path)."
            }
        } catch { statusMessage = "Не удалось сохранить избранное в PDF." }
    }

    private func preparedForPDF(_ source: VacancySearchResult) async throws -> VacancySearchResult {
        if source.isDetailLoaded { return source }
        do {
            let details = try await apiClient.vacancyDetails(id: source.id)
            detailsCache[source.id] = details
            return VacancySearchResult(
                id: source.id,
                summary: source.summary,
                details: details,
                location: source.location,
                isDetailLoaded: true,
                persistedSalaryText: source.persistedSalaryText,
                isArchived: details.archived ?? source.isArchived,
                archiveCheckedAt: source.archiveCheckedAt
            )
        } catch {
            return VacancySearchResult(
                id: source.id,
                summary: source.summary,
                details: source.details,
                location: source.location,
                isDetailLoaded: source.isDetailLoaded,
                persistedSalaryText: source.persistedSalaryText,
                isArchived: source.isArchived,
                archiveCheckedAt: source.archiveCheckedAt,
                exportDataNotice: "Полные detail-данные hh.ru недоступны; документ содержит локальные данные карточки."
            )
        }
    }

    nonisolated static func exportText(for vacancy: VacancySearchResult) -> String { VacancyPDFFormatter.text(for: vacancy) }

    private func result(_ id: String) -> VacancySearchResult? { unfilteredResults.first { $0.id == id } }
    private func reconcileExpanded() { if let id = expandedVacancyID, !displayedResults.contains(where: { $0.id == id }) { expandedVacancyID = nil } }
    private func normalizeFilters() {
        if !employerFilterOptions.contains(where: { $0.id == selectedEmployerID }) { selectedEmployerID = "all" }
        if !regionFilterOptions.contains(where: { $0.id == selectedRegionID }) { selectedRegionID = "all" }
    }
    private func sortPredicate(_ left: VacancySearchResult, _ right: VacancySearchResult) -> Bool {
        let comparison: ComparisonResult
        switch sortOrder {
        case .newest:
            let formatter = ISO8601DateFormatter()
            let leftDate = left.summary.publishedAt.flatMap { formatter.date(from: $0) }
            let rightDate = right.summary.publishedAt.flatMap { formatter.date(from: $0) }
            if leftDate != rightDate { return (leftDate ?? .distantPast) > (rightDate ?? .distantPast) }
            comparison = left.name.localizedCaseInsensitiveCompare(right.name)
        case .employer: comparison = left.employerName.localizedCaseInsensitiveCompare(right.employerName)
        case .subject: comparison = left.areaName.localizedCaseInsensitiveCompare(right.areaName)
        }
        if comparison == .orderedSame { return left.id < right.id }
        return comparison == .orderedAscending
    }
    private func timeMessage(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ru_RU"); formatter.timeStyle = .short; formatter.dateStyle = .none
        return "Обновлено: \(formatter.string(from: date))"
    }
}
