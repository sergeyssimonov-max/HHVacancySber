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
    let issues: [VacancyCollectionIssue]
}

@MainActor
final class VacancySearchViewModel: ObservableObject {
    static let searchCacheTTL: TimeInterval = 10 * 60
    static let archiveCheckInterval: TimeInterval = 30 * 60
    static let archiveBatchInterval: TimeInterval = 60
    static let archiveBatchSize = 20
    private static let publicationDateParser = HHPublicationDateParser()

    @Published private(set) var results: [VacancySearchResult] = []
    @Published private(set) var favorites: [FavoriteVacancyRecord] = []
    @Published private(set) var expandedVacancyID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isPersistenceLoaded = false
    @Published private(set) var isExportingFavoritesPDF = false
    @Published private(set) var isExportingStatisticsPDF = false
    @Published private(set) var statisticsPDFExportMessage: String?
    @Published private(set) var favoritesPDFExportProgress: FavoritePDFExportProgress?
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var updatedAtMessage: String?
    @Published private(set) var favoritesWarning: String?
    /// Employers read incompletely by the last successful search.
    @Published private(set) var collectionWarning: String?
    @Published private(set) var hasSearched = false
    @Published private(set) var isCancellingSearch = false
    @Published private(set) var isCancellingFavoritesPDFExport = false
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
    private let statisticsPDFDestination: @MainActor (String) -> URL?
    private let currentDate: @Sendable () -> Date
    private var detailsCache: [String: HHVacancyDetails] = [:]
    private var cache: VacancySearchCache?
    private var detailTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var favoritesExportTask: Task<Void, Never>?
    // Detail state for favorites shown from the offline snapshot, outside `results`.
    @Published private var offlineDetailStates: [String: (isLoading: Bool, errorMessage: String?)] = [:]
    private var saveTask: Task<Void, Never>?
    private var pendingPersistenceSnapshot: (revision: Int, values: [FavoriteVacancyRecord])?
    private var persistenceRevision = 0
    private var nextPersistenceRetryAt = Date.distantPast
    private var isPersistenceDriverRunning = false
    private var isFavoritesPersistenceWritable = false
    private var isArchiveCheckRunning = false
    private var resultsRevision = 0
    private var archiveAttempts: [String: Date] = [:]
    private var nextArchiveBatchAt = Date.distantPast
    private final class DetailFlight: @unchecked Sendable {
        let token = UUID()
        private let lock = NSLock()
        private var task: Task<Void, Never>?
        private var waiters: [UUID: CheckedContinuation<HHVacancyDetails, Error>] = [:]
        func addIfActive(_ id: UUID, _ continuation: CheckedContinuation<HHVacancyDetails, Error>) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !waiters.isEmpty else { return false }
            waiters[id] = continuation
            return true
        }
        func add(_ id: UUID, _ continuation: CheckedContinuation<HHVacancyDetails, Error>) {
            lock.lock(); waiters[id] = continuation; lock.unlock()
        }
        func setTask(_ value: Task<Void, Never>) {
            lock.lock(); task = value; let empty = waiters.isEmpty; lock.unlock()
            if empty { value.cancel() }
        }
        func cancel(_ id: UUID) {
            lock.lock()
            let waiter = waiters.removeValue(forKey: id)
            let cancelledTask = waiters.isEmpty ? task : nil
            lock.unlock()
            cancelledTask?.cancel()
            waiter?.resume(throwing: CancellationError())
        }
        func finish(_ result: Result<HHVacancyDetails, Error>) {
            lock.lock(); let pending = waiters; waiters = [:]; task = nil; lock.unlock()
            for waiter in pending.values { waiter.resume(with: result) }
        }
        func cancelAll() {
            lock.lock(); let cancelledTask = task; lock.unlock()
            cancelledTask?.cancel()
            finish(.failure(CancellationError()))
        }
    }
    private final class DetailSubscription: @unchecked Sendable {
        let id = UUID()
        private let lock = NSLock()
        private var flight: DetailFlight?
        private var cancelled = false
        func attach(_ value: DetailFlight) {
            lock.lock(); flight = value; let shouldCancel = cancelled; lock.unlock()
            if shouldCancel { value.cancel(id) }
        }
        func cancel() {
            lock.lock(); cancelled = true; let current = flight; lock.unlock()
            current?.cancel(id)
        }
    }
    private var detailFlights: [String: DetailFlight] = [:]

    init(
        apiClient: any HHVacancyAPIClient = HHAPIClient(),
        employerStore: any EmployerConfigurationStoring,
        areaStore: AreaDirectoryStore = AreaDirectoryStore(),
        favoritesStore: any FavoriteVacancyStoring = InMemoryFavoriteVacancyStore(),
        favoritePDFExporter: (any FavoriteVacanciesPDFExporting)? = nil,
        statisticsPDFDestination: (@MainActor (String) -> URL?)? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.apiClient = apiClient
        self.employerStore = employerStore
        self.areaStore = areaStore
        self.favoritesStore = favoritesStore
        self.favoritePDFExporter = favoritePDFExporter ?? FavoriteVacanciesPDFExporter()
        self.statisticsPDFDestination = statisticsPDFDestination ?? Self.chooseStatisticsPDFDestination
        self.currentDate = currentDate
    }

    deinit {
        detailTask?.cancel(); saveTask?.cancel(); searchTask?.cancel(); favoritesExportTask?.cancel()
        for flight in detailFlights.values {
            flight.cancelAll()
        }
    }

    var canSearch: Bool { isPersistenceLoaded && !isLoading && searchTask == nil }
    var canCancelSearch: Bool { searchTask != nil && !isCancellingSearch }
    var canCancelFavoritesPDFExport: Bool { favoritesExportTask != nil && !isCancellingFavoritesPDFExport }
    var isShowingFavorites: Bool { displayMode == .favorites }
    var canExportFavoritesPDF: Bool { !favorites.isEmpty && !isExportingFavoritesPDF && !isExportingStatisticsPDF }
    var canExportStatisticsPDF: Bool {
        !isLoading && !isExportingFavoritesPDF && !isExportingStatisticsPDF
            && (isShowingFavorites ? isPersistenceLoaded : cache != nil)
    }
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
            return favorites.map { favorite in
                if let value = live[favorite.id] { return value }
                let value = favorite.searchResult
                guard let state = offlineDetailStates[favorite.id] else { return value }
                return value.updatingDetailState(isLoading: state.isLoading, errorMessage: state.errorMessage)
            }
        }
    }

    func loadPersistenceIfNeeded() async {
        guard !isPersistenceLoaded else {
            if pendingPersistenceSnapshot != nil, !isPersistenceDriverRunning,
               currentDate() >= nextPersistenceRetryAt { startPersistenceDriver() }
            return
        }
        do {
            favorites = try favoritesStore.load().sorted { $0.favoritedAt > $1.favoritedAt }
            isFavoritesPersistenceWritable = true
        }
        catch { favoritesWarning = error.localizedDescription }
        isPersistenceLoaded = true
    }

    func search() async { await performSearch(useCache: true) }
    func refreshVacancies() async { await performSearch(useCache: false) }

    /// Starts a refresh owned by the model, so the UI can cancel it.
    func startRefresh() {
        guard canSearch else { return }
        searchTask = Task { [weak self] in
            await self?.refreshVacancies()
            self?.searchTask = nil
            self?.isCancellingSearch = false
        }
    }

    func cancelSearch() {
        guard canCancelSearch else { return }
        isCancellingSearch = true
        searchTask?.cancel()
    }

    func startFavoritesPDFExport() {
        guard favoritesExportTask == nil, canExportFavoritesPDF else { return }
        favoritesExportTask = Task { [weak self] in
            await self?.exportFavoriteVacanciesPDF()
            self?.favoritesExportTask = nil
            self?.isCancellingFavoritesPDFExport = false
        }
    }

    func cancelFavoritesPDFExport() {
        guard canCancelFavoritesPDFExport else { return }
        isCancellingFavoritesPDFExport = true
        favoritesExportTask?.cancel()
    }

    private func performSearch(useCache: Bool) async {
        await loadPersistenceIfNeeded()
        guard !isLoading else { return }
        let now = currentDate()
        if useCache, let cache, cache.issues.isEmpty, now.timeIntervalSince(cache.updatedAt) >= 0,
           now.timeIntervalSince(cache.updatedAt) < Self.searchCacheTTL {
            resultsRevision += 1
            results = cache.values
            hasSearched = true
            updatedAtMessage = timeMessage(cache.updatedAt)
            collectionWarning = nil
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
            let collection = try await collector.collect(employers: employers, areas: areaSnapshot.index) { [weak self] progress in
                self?.statusMessage = "\(progress.employerName): загружено \(progress.loadedCount), \(progress.partition)."
            }
            try Task.checkCancellation()
            let values = orderedNewestFirst(collection.vacancies.map { summary -> VacancySearchResult in
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
            if !collection.isComplete, let cache, cache.issues.isEmpty {
                collectionWarning = Self.makeCollectionWarning(for: collection.issues)?
                    .replacingOccurrences(of: "Показаны полученные вакансии", with: "Сохранена предыдущая полная выборка")
                statusMessage = "Обновление неполное; сохранена предыдущая полная выборка."
                return
            }
            resultsRevision += 1
            results = values
            cache = VacancySearchCache(values: values, updatedAt: now, issues: collection.issues)
            updatedAtMessage = timeMessage(now)
            collectionWarning = Self.makeCollectionWarning(for: collection.issues)
            if collection.isComplete {
                statusMessage = values.isEmpty ? "У выбранных работодателей нет открытых вакансий." : "Готово: \(values.count) уникальных вакансий."
            } else {
                statusMessage = "Готово с пропусками: \(values.count) уникальных вакансий, неполностью загружено работодателей: \(collection.issues.count)."
            }
            normalizeFilters()
        } catch is CancellationError {
            // A cancelled first search returns to the initial screen, not to "no vacancies found".
            if cache == nil { hasSearched = false }
            statusMessage = "Поиск отменён."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Поиск не завершён; сохранены ранее загруженные вакансии."
        }
    }

    static func makeCollectionWarning(for issues: [VacancyCollectionIssue]) -> String? {
        guard !issues.isEmpty else { return nil }
        let shown = issues.prefix(3).map(\.message).joined(separator: ". ")
        let rest = issues.count > 3 ? ". Еще работодателей с пропусками: \(issues.count - 3)" : ""
        return "Выгрузка неполная. \(shown)\(rest). Показаны полученные вакансии, повторите обновление позже."
    }

    func toggleExplanation(for id: String) {
        if expandedVacancyID == id { expandedVacancyID = nil; detailTask?.cancel(); offlineDetailStates[id] = nil; return }
        expandedVacancyID = id
        detailTask?.cancel()
        detailTask = Task { [weak self] in await self?.loadVacancyDetails(id: id) }
    }

    func loadVacancyDetails(id: String) async {
        guard let index = results.firstIndex(where: { $0.id == id }) else {
            await loadOfflineFavoriteDetails(id: id)
            return
        }
        let revision = resultsRevision
        if let cached = detailsCache[id] { apply(details: cached, at: index); return }
        let current = results[index]
        results[index] = current.updatingDetailState(isLoading: true, errorMessage: nil)
        do {
            let details = try await sharedDetails(id: id)
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

    /// A favorite that is not in the current results is shown from its stored
    /// snapshot; loading details updates and persists that snapshot.
    private func loadOfflineFavoriteDetails(id: String) async {
        guard let favorite = favorites.first(where: { $0.id == id }), favorite.detailsSnapshot == nil else { return }
        offlineDetailStates[id] = (true, nil)
        do {
            let details: HHVacancyDetails
            if let cached = detailsCache[id] {
                details = cached
            } else {
                details = try await sharedDetails(id: id)
            }
            try Task.checkCancellation()
            detailsCache[id] = details
            offlineDetailStates[id] = nil
            guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }
            let old = favorites[index].searchResult
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
            if favorites[index].update(from: value, at: currentDate()) { persistFavorites() }
            statusMessage = "Описание вакансии загружено."
        } catch is CancellationError {
            offlineDetailStates[id] = nil
        } catch {
            offlineDetailStates[id] = (false, "Не удалось загрузить описание: \(error.localizedDescription)")
        }
    }

    /// Every consumer joins one detail request. Cancelling a subscriber is immediate;
    /// the network task is cancelled only when its last subscriber leaves.
    private func sharedDetails(id: String, refresh: Bool = false) async throws -> HHVacancyDetails {
        try Task.checkCancellation()
        if !refresh, let cached = detailsCache[id] { return cached }
        let subscriber = DetailSubscription()
        // A refresh starts a new generation; its card must not join an older response.
        let key = "\(resultsRevision):\(id)"
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HHVacancyDetails, Error>) in
                joinDetails(id: id, key: key, subscriber: subscriber, continuation: continuation)
            }
        } onCancel: {
            subscriber.cancel()
        }
    }

    private func joinDetails(id: String, key: String, subscriber: DetailSubscription,
                             continuation: CheckedContinuation<HHVacancyDetails, Error>) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        if let flight = detailFlights[key], flight.addIfActive(subscriber.id, continuation) {
            subscriber.attach(flight)
            return
        }
        let flight = DetailFlight()
        flight.add(subscriber.id, continuation)
        subscriber.attach(flight)
        let token = flight.token
        let client = apiClient
        let task = Task { [weak self] in
            let result: Result<HHVacancyDetails, Error>
            do {
                try Task.checkCancellation()
                let details = try await client.vacancyDetails(id: id)
                try Task.checkCancellation()
                result = .success(details)
            } catch { result = .failure(error) }
            self?.finishDetails(key: key, token: token, result: result)
        }
        flight.setTask(task)
        detailFlights[key] = flight
    }

    private func finishDetails(key: String, token: UUID, result: Result<HHVacancyDetails, Error>) {
        guard let flight = detailFlights[key], flight.token == token else { return }
        detailFlights[key] = nil
        flight.finish(result)
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
        startPersistenceDriver()
    }

    private func startPersistenceDriver() {
        guard !isPersistenceDriverRunning else { return }
        isPersistenceDriverRunning = true
        saveTask = Task { [weak self] in await self?.runPersistenceDriver() }
    }

    private func runPersistenceDriver() async {
        defer { isPersistenceDriverRunning = false; saveTask = nil }
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
                    pendingPersistenceSnapshot = pending
                    nextPersistenceRetryAt = currentDate().addingTimeInterval(Self.archiveBatchInterval)
                    return
                }
            }
        }
    }

    func waitForPendingFavoritesSaves() async {
        while let task = saveTask { await task.value }
    }

    func checkArchiveStatusesIfNeeded(background: Bool = false) async {
        await loadPersistenceIfNeeded()
        guard !isArchiveCheckRunning, !(background && (isLoading || isExportingFavoritesPDF)),
              currentDate() >= nextArchiveBatchAt else { return }
        let favoriteIDs = Set(favorites.map(\.id))
        archiveAttempts = archiveAttempts.filter { favoriteIDs.contains($0.key) }
        isArchiveCheckRunning = true
        defer { isArchiveCheckRunning = false }
        let due = currentDate().addingTimeInterval(-Self.archiveCheckInterval)
        var didUpdate = false
        var seenIDs = Set<String>()
        var favoriteIndicesByID = makeFavoriteIndicesByID()
        let dueIDs: [String] = favorites.compactMap { favorite in
            guard (favorite.archiveCheckedAt ?? .distantPast) < due,
                  (archiveAttempts[favorite.id] ?? .distantPast) < due,
                  seenIDs.insert(favorite.id).inserted else { return nil }
            return favorite.id
        }
        // Oldest attempted entries first prevents a large list's tail from starving
        // when the first batch becomes due again before the whole list was visited.
        let orderedIDs = background ? dueIDs.enumerated().sorted { lhs, rhs in
            let left = archiveAttempts[lhs.element] ?? .distantPast
            let right = archiveAttempts[rhs.element] ?? .distantPast
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element) : dueIDs
        let batchSize = background ? Self.archiveBatchSize : dueIDs.count
        if dueIDs.count > batchSize {
            nextArchiveBatchAt = currentDate().addingTimeInterval(Self.archiveBatchInterval)
        }
        for id in orderedIDs.prefix(batchSize) {
            guard !Task.isCancelled, !(background && (isLoading || isExportingFavoritesPDF)) else { break }
            guard favoriteIndex(for: id, cachedIndices: &favoriteIndicesByID) != nil else { continue }
            archiveAttempts[id] = currentDate()
            let revision = resultsRevision
            do {
                let details = try await sharedDetails(id: id, refresh: true)
                try Task.checkCancellation()
                if revision == resultsRevision { detailsCache[id] = details }
                guard let archived = details.archived,
                      let index = favoriteIndex(for: id, cachedIndices: &favoriteIndicesByID) else { continue }
                let checkedAt = currentDate()
                favorites[index].updateArchiveStatus(archived, checkedAt: checkedAt)
                updateResultArchiveStatus(id: id, archived: archived, checkedAt: checkedAt, revision: revision)
                didUpdate = true
            } catch let error as HHAPIError where error.isNotFound {
                // A vacancy removed from hh.ru is no longer available to apply for.
                guard let index = favoriteIndex(for: id, cachedIndices: &favoriteIndicesByID) else { continue }
                let checkedAt = currentDate()
                favorites[index].updateArchiveStatus(true, checkedAt: checkedAt)
                updateResultArchiveStatus(id: id, archived: true, checkedAt: checkedAt, revision: revision)
                didUpdate = true
            } catch is CancellationError {
                archiveAttempts[id] = nil
                break
            } catch let error as HHAPIError where shouldStopArchiveCheckCycle(after: error) {
                nextArchiveBatchAt = currentDate().addingTimeInterval(Self.archiveCheckInterval)
                break
            } catch let error as URLError where error.code == .notConnectedToInternet {
                nextArchiveBatchAt = currentDate().addingTimeInterval(Self.archiveBatchInterval)
                break
            } catch {
                continue
            }
        }
        if didUpdate { persistFavorites() }
    }

    private func updateResultArchiveStatus(id: String, archived: Bool, checkedAt: Date, revision: Int) {
        guard revision == resultsRevision else { return }
        if let index = results.firstIndex(where: { $0.id == id }) {
            results[index] = results[index].updatingArchiveStatus(archived, checkedAt: checkedAt)
        }
        if let previous = cache, let index = previous.values.firstIndex(where: { $0.id == id }) {
            var values = previous.values
            values[index] = values[index].updatingArchiveStatus(archived, checkedAt: checkedAt)
            cache = VacancySearchCache(values: values, updatedAt: previous.updatedAt, issues: previous.issues)
        }
    }

    private func makeFavoriteIndicesByID() -> [String: Int] {
        var result: [String: Int] = [:]
        for (index, favorite) in favorites.enumerated() where result[favorite.id] == nil {
            result[favorite.id] = index
        }
        return result
    }

    private func favoriteIndex(for id: String, cachedIndices: inout [String: Int]) -> Int? {
        if let index = cachedIndices[id], favorites.indices.contains(index), favorites[index].id == id {
            return index
        }
        cachedIndices = makeFavoriteIndicesByID()
        return cachedIndices[id]
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
            let worker = PDFExportWorker()
            try await worker.exportPersonal(
                vacancy: PDFVacancySnapshot(value: prepared),
                destination: destination
            )
            statusMessage = "Вакансия сохранена в PDF."
            return true
        } catch { statusMessage = "Не удалось сохранить PDF."; return false }
    }

    func exportFavoriteVacanciesPDF() async {
        guard canExportFavoritesPDF else { return }
        isExportingFavoritesPDF = true
        defer { isExportingFavoritesPDF = false; favoritesPDFExportProgress = nil }
        // Freeze local rows and membership before enrichment can suspend this actor.
        let currentResults = unfilteredResults
        let snapshot = favorites.map { favorite in
            currentResults.first { $0.id == favorite.id } ?? favorite.searchResult
        }
        do {
            var values: [VacancySearchResult] = []
            for (index, source) in snapshot.enumerated() {
                try Task.checkCancellation()
                values.append(try await preparedForPDF(source))
                favoritesPDFExportProgress = .init(completedVacancies: index + 1, totalVacancies: snapshot.count)
            }
            try Task.checkCancellation()
            let outcome = try await favoritePDFExporter.export(vacancies: values) { [weak self] in self?.favoritesPDFExportProgress = $0 }
            switch outcome {
            case .cancelled: break
            case .exported(let files, let pages): statusMessage = "Сохранено PDF: \(files), страниц: \(pages)."
            }
        } catch is CancellationError {
            statusMessage = "Сохранение избранного в PDF отменено."
        } catch {
            statusMessage = "Не удалось сохранить избранное в PDF: \(error.localizedDescription)"
        }
    }

    func statisticsReportSnapshot() -> VacancyStatisticsReport {
        let employer = employerFilterOptions.first { $0.id == selectedEmployerID }?.title ?? selectedEmployerID
        let region = regionFilterOptions.first { $0.id == selectedRegionID }?.title ?? selectedRegionID
        var note = "Отчёт по локальной выборке на момент нажатия кнопки. Дополнительная проверка HH.ru не выполнялась."
        if let cache {
            note += " Последняя загрузка общего списка: \(cache.updatedAt.formatted(date: .numeric, time: .shortened))."
        }
        if let cache, !cache.issues.isEmpty {
            note += " Выгрузка общего списка неполная, работодателей с пропусками: \(cache.issues.count)."
        }
        if errorMessage != nil { note += " Последнее обновление не завершено; использованы сохранённые данные." }
        return VacancyStatisticsReport(
            entries: displayedResults.map(VacancyStatisticsReport.Entry.init),
            modeName: displayMode.rawValue,
            employerID: selectedEmployerID,
            employerName: employer,
            regionID: selectedRegionID,
            regionName: region,
            createdAt: currentDate(),
            timeZoneIdentifier: TimeZone.current.identifier,
            sourceNote: note
        )
    }

    func exportStatisticsPDF() async {
        guard canExportStatisticsPDF else { return }
        isExportingStatisticsPDF = true
        statisticsPDFExportMessage = nil
        defer { isExportingStatisticsPDF = false }
        // Capture the rows and filter labels together, before the save panel suspends UI work.
        let report = statisticsReportSnapshot()
        guard let destination = statisticsPDFDestination(report.fileName) else { return }
        do {
            let worker = PDFExportWorker()
            try await worker.exportStatistics(report: report, destination: destination)
            statisticsPDFExportMessage = "Статистический отчёт сохранён: \(report.entries.count) вакансий."
        } catch is CancellationError {
            statisticsPDFExportMessage = "Сохранение отчёта отменено."
        } catch {
            statisticsPDFExportMessage = "Не удалось сохранить отчёт: \(error.localizedDescription)"
        }
    }

    private static func chooseStatisticsPDFDestination(_ fileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func preparedForPDF(_ source: VacancySearchResult) async throws -> VacancySearchResult {
        try Task.checkCancellation()
        if source.isDetailLoaded { return source }
        do {
            let details: HHVacancyDetails
            if let cached = detailsCache[source.id] {
                details = cached
            } else {
                details = try await sharedDetails(id: source.id)
            }
            try Task.checkCancellation()
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
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as HHAPIError where shouldStopArchiveCheckCycle(after: error) {
            // Access restrictions stop bulk PDF enrichment just like archive checks.
            throw error
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
    private func reconcileExpanded() {
        if let id = expandedVacancyID, !displayedResults.contains(where: { $0.id == id }) {
            expandedVacancyID = nil
            detailTask?.cancel()
            offlineDetailStates[id] = nil
        }
    }
    private func normalizeFilters() {
        if !employerFilterOptions.contains(where: { $0.id == selectedEmployerID }) { selectedEmployerID = "all" }
        if !regionFilterOptions.contains(where: { $0.id == selectedRegionID }) { selectedRegionID = "all" }
    }
    private func orderedNewestFirst(_ values: [VacancySearchResult]) -> [VacancySearchResult] {
        let datedValues = values.map { value in
            (value: value, date: Self.publicationDateParser.date(from: value.publishedAt))
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
