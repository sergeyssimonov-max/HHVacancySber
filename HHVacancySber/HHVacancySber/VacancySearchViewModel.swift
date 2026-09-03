import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum VacancyListMode: String, CaseIterable, Identifiable {
    case all = "Все вакансии"
    case favorites = "Избранное"
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
    private static let publicationDateFormatter = ISO8601DateFormatter()

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
    @Published var displayMode: VacancyListMode = .all {
        didSet {
            normalizeFilters()
            reconcileExpanded()
        }
    }
    @Published var selectedEmployerID = "all" { didSet { reconcileExpanded() } }
    @Published var selectedRegionID = "all" { didSet { reconcileExpanded() } }

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
    private var isFavoritesPersistenceWritable = false
    private var isArchiveCheckRunning = false
    private var resultsRevision = 0

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
    var displayedVacancyCountMessage: String { "Показано вакансий: \(displayedResults.count)" }

    var employerFilterOptions: [VacancyFilterOption] {
        var titlesByID: [String: String] = [:]
        for result in unfilteredResults {
            guard let id = result.employerID, titlesByID[id] == nil else { continue }
            titlesByID[id] = result.employerName
        }
        let values = titlesByID.map { VacancyFilterOption(id: $0.key, title: $0.value) }
        return [.init(id: "all", title: "Все работодатели")] + values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var regionFilterOptions: [VacancyFilterOption] {
        var titlesByID: [String: String] = [:]
        for result in unfilteredResults {
            let id = result.location.filterID
            guard titlesByID[id] == nil else { continue }
            titlesByID[id] = result.location.kind == .subject
                ? (result.location.subjectName ?? result.areaName)
                : result.areaName
        }
        let values = titlesByID.map { VacancyFilterOption(id: $0.key, title: $0.value) }
        return [.init(id: "all", title: "Все регионы")] + values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var displayedResults: [VacancySearchResult] {
        let values = unfilteredResults
        let filtered: [VacancySearchResult]
        switch (selectedEmployerID == "all", selectedRegionID == "all") {
        case (true, true):
            filtered = values
        case (false, true):
            filtered = values.filter { $0.employerID == selectedEmployerID }
        case (true, false):
            filtered = values.filter { $0.location.filterID == selectedRegionID }
        case (false, false):
            filtered = values
                .filter { $0.employerID == selectedEmployerID }
                .filter { $0.location.filterID == selectedRegionID }
        }
        switch displayMode {
        case .all:
            return filtered
        case .favorites:
            return orderedNewestFirst(filtered)
        }
    }

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
        do {
            favorites = try favoritesStore.load().sorted { $0.favoritedAt > $1.favoritedAt }
            isFavoritesPersistenceWritable = true
        }
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
            resultsRevision += 1
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
            let values = orderedNewestFirst(summaries.map { summary -> VacancySearchResult in
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
            })
            resultsRevision += 1
            results = values
            cache = VacancySearchCache(values: values, updatedAt: now)
            updatedAtMessage = timeMessage(now)
            statusMessage = values.isEmpty ? "У выбранных работодателей нет открытых вакансий." : "Готово: \(values.count) уникальных вакансий."
            normalizeFilters()
        } catch is CancellationError {
            statusMessage = "Поиск отменён."
        } catch {
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

    func loadVacancyDetails(id: String) async {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        let revision = resultsRevision
        if let cached = detailsCache[id] { apply(details: cached, at: index); return }
        let current = results[index]
        results[index] = current.updatingDetailState(isLoading: true, errorMessage: nil)
        do {
            let details = try await apiClient.vacancyDetails(id: id)
            try Task.checkCancellation()
            guard revision == resultsRevision else { return }
            detailsCache[id] = details
            guard let newIndex = results.firstIndex(where: { $0.id == id }) else { return }
            apply(details: details, at: newIndex)
        } catch is CancellationError {
            guard revision == resultsRevision else { return }
            if let newIndex = results.firstIndex(where: { $0.id == id }) {
                results[newIndex] = results[newIndex].updatingDetailState(isLoading: false, errorMessage: nil)
            }
        } catch {
            guard revision == resultsRevision else { return }
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
        if let index = favorites.firstIndex(where: { $0.id == id }) {
            favorites.remove(at: index)
            normalizeFilters()
            persistFavorites()
            reconcileExpanded()
            return
        }
        guard let value = unfilteredResults.first(where: { $0.id == id }) else { return }
        let now = currentDate()
        favorites.append(.init(result: value, favoritedAt: now, updatedAt: now, archiveCheckedAt: value.archiveCheckedAt))
        favorites.sort { $0.favoritedAt > $1.favoritedAt }
        persistFavorites()
    }

    private func persistFavorites() {
        guard isFavoritesPersistenceWritable else { return }
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

    func waitForPendingFavoritesSaves() async {
        while let task = saveTask { await task.value }
    }

    func checkArchiveStatusesIfNeeded() async {
        await loadPersistenceIfNeeded()
        guard !isArchiveCheckRunning else { return }
        isArchiveCheckRunning = true
        defer { isArchiveCheckRunning = false }
        let due = currentDate().addingTimeInterval(-Self.archiveCheckInterval)
        var didUpdate = false
        var seenIDs = Set<String>()
        let dueIDs: [String] = favorites.compactMap { favorite in
            guard (favorite.archiveCheckedAt ?? .distantPast) < due,
                  seenIDs.insert(favorite.id).inserted else { return nil }
            return favorite.id
        }
        for id in dueIDs {
            do {
                let details = try await apiClient.vacancyDetails(id: id)
                guard let archived = details.archived, let index = favorites.firstIndex(where: { $0.id == id }) else { continue }
                favorites[index].updateArchiveStatus(archived, checkedAt: currentDate())
                didUpdate = true
            } catch let error as HHAPIError where error.isNotFound {
                guard let index = favorites.firstIndex(where: { $0.id == id }) else { continue }
                let archived = favorites[index].isArchived
                favorites[index].updateArchiveStatus(archived, checkedAt: currentDate())
                didUpdate = true
            } catch is CancellationError {
                return
            } catch let error as HHAPIError where shouldStopArchiveCheckCycle(after: error) {
                break
            } catch {
                continue
            }
        }
        if didUpdate { persistFavorites() }
    }

    private func shouldStopArchiveCheckCycle(after error: HHAPIError) -> Bool {
        switch error {
        case .missingApplicationToken, .placeholderApplicationToken, .unauthorized,
             .forbidden, .rateLimited, .captchaRequired:
            return true
        default:
            return false
        }
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

    private func result(_ id: String) -> VacancySearchResult? { unfilteredResults.first { $0.id == id } }
    private func reconcileExpanded() { if let id = expandedVacancyID, !displayedResults.contains(where: { $0.id == id }) { expandedVacancyID = nil } }
    private func normalizeFilters() {
        if !employerFilterOptions.contains(where: { $0.id == selectedEmployerID }) { selectedEmployerID = "all" }
        if !regionFilterOptions.contains(where: { $0.id == selectedRegionID }) { selectedRegionID = "all" }
    }
    private func orderedNewestFirst(_ values: [VacancySearchResult]) -> [VacancySearchResult] {
        let datedValues = values.map { value in
            (value: value, date: value.publishedAt.flatMap { Self.publicationDateFormatter.date(from: $0) })
        }
        return datedValues.sorted { left, right in
            if left.date != right.date { return (left.date ?? .distantPast) > (right.date ?? .distantPast) }
            let comparison = left.value.name.localizedCaseInsensitiveCompare(right.value.name)
            if comparison == .orderedSame { return left.value.id < right.value.id }
            return comparison == .orderedAscending
        }.map(\.value)
    }
    private func timeMessage(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ru_RU"); formatter.timeStyle = .short; formatter.dateStyle = .none
        return "Обновлено: \(formatter.string(from: date))"
    }
}
