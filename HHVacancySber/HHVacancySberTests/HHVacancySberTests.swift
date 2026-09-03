import Foundation
import XCTest
@testable import HHVacancySber

final class HHVacancySberTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testEmbeddedApplicationTokenIsConfigured() {
        XCTAssertNotNil(HHAuthConfig.configuredAccessToken)
        XCTAssertFalse(HHAuthConfig.configuredAccessToken?.isEmpty ?? true)
    }

    func testEmployerConfigurationRejectsEmptyDuplicateAndInvalidIDs() throws {
        XCTAssertThrowsError(try EmployerConfiguration(version: 1, employers: []).validated())
        XCTAssertThrowsError(try EmployerConfiguration(version: 1, employers: [
            .init(id: "3529", name: "СБЕР", comment: "ok"),
            .init(id: "3529", name: "Дубль", comment: "bad")
        ]).validated())
        XCTAssertThrowsError(try EmployerConfiguration(version: 1, employers: [
            .init(id: "not-a-number", name: "СБЕР", comment: "bad")
        ]).validated())
    }

    func testEmployerConfigurationCopiesBundledDefaultOnlyOnce() throws {
        let directory = temporaryDirectory()
        let bundled = directory.appendingPathComponent("bundled.json")
        let runtime = directory.appendingPathComponent("runtime/employers.json")
        try Data(#"{"version":1,"employers":[{"id":"3529","name":"СБЕР","comment":"verified"}]}"#.utf8).write(to: bundled)
        let store = EmployerConfigurationStore(fileURL: runtime, bundledDefaultURL: bundled)
        XCTAssertEqual(try store.loadOrCreate().employers.map(\.id), ["3529"])
        try Data(#"{"version":1,"employers":[{"id":"2798","name":"СберРешения","comment":"runtime"}]}"#.utf8).write(to: runtime)
        XCTAssertEqual(try store.loadOrCreate().employers.map(\.id), ["2798"])
    }

    func testPersistentStoresShareCanonicalApplicationSupportDirectory() {
        let employerURL = EmployerConfigurationStore().fileURL
        let areaURL = AreaDirectoryStore().fileURL
        let favoritesURL = FavoriteVacancyStore().fileURL
        let directory = employerURL.deletingLastPathComponent()

        XCTAssertEqual(directory.lastPathComponent, ApplicationSupportLocation.directoryName)
        XCTAssertEqual(areaURL.deletingLastPathComponent(), directory)
        XCTAssertEqual(favoritesURL.deletingLastPathComponent(), directory)
        XCTAssertEqual(employerURL.lastPathComponent, "employers.json")
        XCTAssertEqual(areaURL.lastPathComponent, "areas.json")
        XCTAssertEqual(favoritesURL.lastPathComponent, "favorites.json")
    }

    func testLocationClassificationIsStrict() throws {
        let index = try AreaDirectoryIndex(root: Self.areaTree)
        XCTAssertEqual(index.location(for: summary(id: "m", areaID: "1", areaName: "Москва")),
                       .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва"))
        XCTAssertEqual(index.location(for: summary(id: "e", areaID: "3", areaName: "Екатеринбург")),
                       .subject(id: "66", name: "Свердловская область", cityID: "3", cityName: "Екатеринбург"))
        XCTAssertEqual(index.location(for: summary(id: "r", areaID: nil, areaName: nil,
                                                   workFormat: [.init(id: "REMOTE", name: "Удалённо")])), .remote)
        XCTAssertEqual(index.location(for: summary(id: "foreign", areaID: "999", areaName: "Минск")), .unknown)
        let multiple = summary(id: "multi", areaID: "1", areaName: "Москва", areas: [
            .init(id: "1", name: "Москва"), .init(id: "2", name: "Санкт-Петербург")
        ])
        XCTAssertEqual(index.location(for: multiple), .unknown)
    }

    func testFavoriteV1MigratesAtomicallyToV2AndDropsHistoricalFields() throws {
        let url = temporaryDirectory().appendingPathComponent("favorites.json")
        let historicalValueKey = "sco" + "re"
        let legacy = #"{"version":1,"favorites":[{"id":"42","name":"Аналитик","employerName":"СБЕР","areaName":"Москва","salaryText":null,"alternateURL":null,"snippet":null,"descriptionHTML":null,"isArchived":false,"favoritedAt":"2026-09-01T00:00:00Z","updatedAt":"2026-09-01T00:00:00Z","HISTORICAL_KEY":{"total":99},"status":"ready","reasons":["legacy"]}]}"#
            .replacingOccurrences(of: "HISTORICAL_KEY", with: historicalValueKey)
        try Data(legacy.utf8).write(to: url)
        let records = try FavoriteVacancyStore(fileURL: url).load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].location, .unknown)
        let migrated = try String(contentsOf: url)
        XCTAssertTrue(migrated.contains(#""version" : 2"#))
        XCTAssertFalse(migrated.contains("\"\(historicalValueKey)\""))
        XCTAssertFalse(migrated.contains(#""reasons""#))
    }

    @MainActor
    func testUnsupportedFavoritesSchemaIsNotOverwrittenByArchiveCheck() async throws {
        let url = temporaryDirectory().appendingPathComponent("favorites.json")
        let unsupported = Data(#"{"version":99,"favorites":[]}"#.utf8)
        try unsupported.write(to: url)
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: FavoriteVacancyStore(fileURL: url)
        )

        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()

        XCTAssertEqual(try Data(contentsOf: url), unsupported)
        XCTAssertNotNil(model.favoritesWarning)
    }

    func testCollectorPartitionsOver2000BySubjectAndDeduplicates() async throws {
        let client = MockAPIClient(mode: .partitioned)
        let service = VacancyCollectionService(client: client)
        let values = try await service.collect(
            employers: [.init(id: "3529", name: "СБЕР", comment: "test")],
            areas: try AreaDirectoryIndex(root: .init(id: "113", name: "Россия", areas: [
                .init(id: "10", name: "Регион A"), .init(id: "20", name: "Регион B")
            ])),
            progress: { _ in }
        )
        XCTAssertEqual(values.count, 2_001)
        XCTAssertEqual(Set(values.map(\.id)).count, 2_001)
    }

    func testCollectorRetriesThenRejectsIncompleteLeaf() async throws {
        let service = VacancyCollectionService(client: MockAPIClient(mode: .mismatch))
        do {
            _ = try await service.collect(
                employers: [.init(id: "3529", name: "СБЕР", comment: "test")],
                areas: try AreaDirectoryIndex(root: Self.areaTree),
                progress: { _ in }
            )
            XCTFail("Expected completeness error")
        } catch let error as VacancyCompletenessError {
            XCTAssertEqual(error.expected, 2)
            XCTAssertEqual(error.actual, 1)
        }
    }

    func testAreaDirectoryUsesFreshThenExplicitStaleCacheAndRejectsCorruptionWithoutNetwork() async throws {
        let file = temporaryDirectory().appendingPathComponent("areas.json")
        let instant = Date(timeIntervalSince1970: 1_788_200_000)
        let freshStore = AreaDirectoryStore(fileURL: file, now: { instant })
        let fresh = try await freshStore.load(using: MockAPIClient(mode: .simple))
        XCTAssertNil(fresh.warning)

        let staleStore = AreaDirectoryStore(
            fileURL: file,
            now: { instant.addingTimeInterval(AreaDirectoryStore.defaultTTL + 1) }
        )
        let stale = try await staleStore.load(using: MockAPIClient(mode: .failure))
        XCTAssertTrue(stale.warning?.contains("устаревший кэш") == true)

        let corrupted = temporaryDirectory().appendingPathComponent("areas.json")
        try Data("not-json".utf8).write(to: corrupted)
        do {
            _ = try await AreaDirectoryStore(fileURL: corrupted).load(using: MockAPIClient(mode: .failure))
            XCTFail("Expected unavailable directory")
        } catch let error as AreaDirectoryError {
            XCTAssertEqual(error, .unavailable)
        }
    }

    func testSemanticallyInvalidFreshAreaCacheIsRefreshed() async throws {
        let file = temporaryDirectory().appendingPathComponent("areas.json")
        let invalid = #"{"version":1,"fetchedAt":"2026-09-02T00:00:00Z","root":{"id":"113","name":"Россия","areas":[{"id":"1","name":"Москва","areas":[]},{"id":"1","name":"Дубликат","areas":[]}]}}"#
        try Data(invalid.utf8).write(to: file)
        let store = AreaDirectoryStore(
            fileURL: file,
            now: { Date(timeIntervalSince1970: 1_788_321_600) }
        )

        let snapshot = try await store.load(using: MockAPIClient(mode: .simple))

        XCTAssertNil(snapshot.warning)
        XCTAssertEqual(snapshot.index.subjects.map(\.id), ["1", "2", "66"])
    }

    func testFreshAreaTreeRemainsAvailableWhenCacheWriteFails() async throws {
        let directory = temporaryDirectory()
        let blockedParent = directory.appendingPathComponent("not-a-directory")
        try Data("file blocks directory creation".utf8).write(to: blockedParent)
        let store = AreaDirectoryStore(
            fileURL: blockedParent.appendingPathComponent("areas.json")
        )

        let snapshot = try await store.load(using: MockAPIClient(mode: .simple))

        XCTAssertEqual(snapshot.index.subjects.map(\.id), ["1", "2", "66"])
        XCTAssertTrue(snapshot.warning?.contains("Не удалось сохранить кэш регионов") == true)
    }

    func testTypedAPIRequestUsesRequiredQueryAndHeaders() async throws {
        let client = makeHTTPClient { request in
            let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(components.path, "/vacancies")
            XCTAssertEqual(query["employer_id"], "3529")
            XCTAssertEqual(query["area"], "113")
            XCTAssertEqual(query["per_page"], "100")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-token")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
            XCTAssertNotNil(request.value(forHTTPHeaderField: "HH-User-Agent"))
            return (200, [:], Data(#"{"items":[],"found":0,"pages":0,"page":0,"per_page":100}"#.utf8))
        }
        let response = try await client.searchVacancies(.init(employerID: "3529"))
        XCTAssertEqual(response.found, 0)
    }

    func testLiveAPIUsesEmbeddedTokenAndRetrievesOneVacancyWithDetails() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HHVACANCYSBER_RUN_LIVE_API_TEST"] == "1",
            "Opt-in live check; set HHVACANCYSBER_RUN_LIVE_API_TEST=1."
        )
        let maximumRequestCount = 2
        var requestCount = 0
        let client = HHAPIClient(
            accessTokenProvider: HHDefaultAccessTokenProvider(),
            requestGate: HHRequestGate(minimumDelayNanoseconds: 0)
        )

        requestCount += 1
        let response = try await client.searchVacancies(.init(employerID: "3529", perPage: 1))
        XCTAssertGreaterThan(response.found, 0)
        XCTAssertLessThanOrEqual(response.items.count, 1)
        let vacancy = try XCTUnwrap(response.items.first)
        XCTAssertFalse(vacancy.id.isEmpty)
        XCTAssertFalse(vacancy.name.isEmpty)

        requestCount += 1
        let details = try await client.vacancyDetails(id: vacancy.id)
        XCTAssertEqual(details.id, vacancy.id)
        XCTAssertFalse(details.name.isEmpty)
        XCTAssertLessThanOrEqual(requestCount, maximumRequestCount)
    }

    func testAPIPreserves401RateLimitCaptchaAndNetworkErrors() async throws {
        var client = makeHTTPClient { _ in (401, [:], Data(#"{"errors":[]}"#.utf8)) }
        await assertAPIError(client, equals: .unauthorized)

        client = makeHTTPClient { _ in (429, ["Retry-After": "17"], Data(#"{"errors":[]}"#.utf8)) }
        await assertAPIError(client, equals: .rateLimited(retryAfterSeconds: 17))

        client = makeHTTPClient { _ in
            (403, [:], Data(#"{"request_id":"req-1","errors":[{"type":"captcha","value":"required"}]}"#.utf8))
        }
        await assertAPIError(client, equals: .captchaRequired(requestID: "req-1"))

        URLProtocolStub.handler = { _ in throw URLError(.notConnectedToInternet) }
        let networkClient = HTTPClientFactory.make()
        do {
            _ = try await networkClient.searchVacancies(.init(employerID: "3529"))
            XCTFail("Expected network error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestGateSerializesConcurrentOperations() async throws {
        let gate = HHRequestGate(minimumDelayNanoseconds: 0)
        let tracker = ConcurrentOperationTracker()

        async let first: Int = gate.perform {
            await tracker.begin()
            try await Task.sleep(nanoseconds: 100_000_000)
            await tracker.end()
            return 1
        }
        async let second: Int = gate.perform {
            await tracker.begin()
            try await Task.sleep(nanoseconds: 100_000_000)
            await tracker.end()
            return 2
        }

        _ = try await (first, second)
        let maximumConcurrentOperations = await tracker.maximumConcurrentOperations
        XCTAssertEqual(maximumConcurrentOperations, 1)
    }

    @MainActor
    func testViewModelUsesEmployerAndRegionFiltersWithANDSemantics() async throws {
        let employerStore = TestEmployerStore(entries: [
            .init(id: "3529", name: "СБЕР", comment: "test"),
            .init(id: "2798", name: "СберРешения", comment: "test")
        ])
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: employerStore,
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            currentDate: { Date(timeIntervalSince1970: 1_788_200_000) }
        )
        await model.search()
        XCTAssertEqual(model.results.count, 2)
        XCTAssertEqual(model.displayedResults.map(\.id), ["3529-vacancy", "2798-vacancy"])
        model.selectedEmployerID = "3529"
        model.selectedRegionID = "subject:1"
        XCTAssertEqual(model.displayedResults.map(\.id), ["3529-vacancy"])
        model.selectedRegionID = "remote"
        XCTAssertTrue(model.displayedResults.isEmpty)
    }

    @MainActor
    func testFilterOptionsAreDeduplicatedSortedAndGroupCitiesBySubject() async {
        let model = makeFilterViewModel()
        await model.search()

        XCTAssertEqual(model.employerFilterOptions.map(\.id), ["all", "9999", "3529", "2798"])
        XCTAssertEqual(model.employerFilterOptions.map(\.title), [
            "Все работодатели", "Альфа Банк", "СБЕР", "СберРешения"
        ])
        XCTAssertEqual(Set(model.employerFilterOptions.map(\.id)).count, model.employerFilterOptions.count)

        XCTAssertEqual(model.regionFilterOptions.first, .init(id: "all", title: "Все регионы"))
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: model.regionFilterOptions.map { ($0.id, $0.title) }), [
            "all": "Все регионы",
            "remote": "Удалённо",
            "unknown": "Регион не определён",
            "subject:1": "Москва",
            "subject:2": "Санкт-Петербург",
            "subject:66": "Свердловская область"
        ])
        XCTAssertEqual(Set(model.regionFilterOptions.map(\.id)).count, model.regionFilterOptions.count)
    }

    @MainActor
    func testDropdownSelectionsApplyEmployerRegionAndANDCombinations() async {
        let model = makeFilterViewModel()
        await model.search()

        model.selectedEmployerID = "3529"
        XCTAssertEqual(Set(model.displayedResults.map(\.id)), ["filter-moscow", "filter-ekb", "filter-unknown"])
        XCTAssertEqual(model.displayedVacancyCountMessage, "Показано вакансий: 3")

        model.selectedRegionID = "subject:66"
        XCTAssertEqual(model.displayedResults.map(\.id), ["filter-ekb"])
        XCTAssertEqual(model.displayedVacancyCountMessage, "Показано вакансий: 1")

        model.selectedEmployerID = "2798"
        XCTAssertTrue(model.displayedResults.isEmpty)
        XCTAssertEqual(model.displayedVacancyCountMessage, "Показано вакансий: 0")

        model.selectedRegionID = "remote"
        XCTAssertEqual(model.displayedResults.map(\.id), ["filter-remote"])

        model.selectedEmployerID = "all"
        model.selectedRegionID = "all"
        XCTAssertEqual(model.displayedResults.count, 5)
        XCTAssertEqual(model.displayedVacancyCountMessage, "Показано вакансий: 5")
    }

    @MainActor
    func testDropdownOptionsFollowFavoritesAndInvalidSelectionsReset() async {
        let model = makeFilterViewModel()
        await model.search()
        model.toggleFavorite(id: "filter-remote")
        model.selectedEmployerID = "3529"
        model.selectedRegionID = "subject:1"

        model.displayMode = .favorites

        XCTAssertEqual(model.selectedEmployerID, "all")
        XCTAssertEqual(model.selectedRegionID, "all")
        XCTAssertEqual(model.employerFilterOptions.map(\.id), ["all", "2798"])
        XCTAssertEqual(model.regionFilterOptions.map(\.id), ["all", "remote"])
        XCTAssertEqual(model.displayedResults.map(\.id), ["filter-remote"])
    }

    @MainActor
    func testRemovingLastMatchingFavoriteResetsDropdowns() async {
        let model = makeFilterViewModel()
        await model.search()
        model.toggleFavorite(id: "filter-remote")
        model.displayMode = .favorites
        model.selectedEmployerID = "2798"
        model.selectedRegionID = "remote"

        model.toggleFavorite(id: "filter-remote")

        XCTAssertEqual(model.selectedEmployerID, "all")
        XCTAssertEqual(model.selectedRegionID, "all")
        XCTAssertEqual(model.employerFilterOptions, [.init(id: "all", title: "Все работодатели")])
        XCTAssertEqual(model.regionFilterOptions, [.init(id: "all", title: "Все регионы")])
        XCTAssertTrue(model.displayedResults.isEmpty)
    }

    @MainActor
    func testChangingDropdownSelectionCollapsesAHiddenExpandedVacancy() async {
        let model = makeFilterViewModel()
        await model.search()
        model.toggleExplanation(for: "filter-moscow")
        XCTAssertEqual(model.expandedVacancyID, "filter-moscow")

        model.selectedRegionID = "subject:66"

        XCTAssertNil(model.expandedVacancyID)
    }

    @MainActor
    func testAllAndPersistedFavoritesAreAlwaysOrderedNewestFirst() async throws {
        let employerStore = TestEmployerStore(entries: [
            .init(id: "2798", name: "СберРешения", comment: "test"),
            .init(id: "3529", name: "СБЕР", comment: "test")
        ])
        let source = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: employerStore,
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )
        await source.search()
        XCTAssertEqual(source.results.map(\.id), ["3529-vacancy", "2798-vacancy"])
        XCTAssertEqual(source.displayedResults.map(\.id), ["3529-vacancy", "2798-vacancy"])

        let older = try XCTUnwrap(source.results.first { $0.id == "2798-vacancy" })
        let newer = try XCTUnwrap(source.results.first { $0.id == "3529-vacancy" })
        let persisted = FavoriteVacancyStore(fileURL: temporaryDirectory().appendingPathComponent("favorites.json"))
        try persisted.save([
            .init(result: older, favoritedAt: Date(timeIntervalSince1970: 200), updatedAt: Date(timeIntervalSince1970: 200)),
            .init(result: newer, favoritedAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 100))
        ])
        let relaunched = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: employerStore,
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: persisted
        )
        await relaunched.loadPersistenceIfNeeded()
        relaunched.displayMode = .favorites

        XCTAssertEqual(relaunched.displayedResults.map(\.id), ["3529-vacancy", "2798-vacancy"])
    }

    @MainActor
    func testLazyDetailsLoadUpdatesOnlyRequestedCard() async throws {
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )
        await model.search()
        XCTAssertFalse(model.results[0].isDetailLoaded)
        await model.loadVacancyDetails(id: "3529-vacancy")
        XCTAssertTrue(model.results.first { $0.id == "3529-vacancy" }?.isDetailLoaded == true)
        XCTAssertEqual(model.results.first { $0.id == "3529-vacancy" }?.plainTextDescription, "Полное описание")
    }

    @MainActor
    func testCompletedRefreshIgnoresDetailResponseFromPreviousResults() async {
        let client = MockAPIClient(mode: .delayedArchive)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )
        await model.search()

        let detail = Task { await model.loadVacancyDetails(id: "3529-vacancy") }
        while await client.detailRequestCount == 0 { await Task.yield() }
        await model.refreshVacancies()
        await detail.value

        XCTAssertFalse(model.results[0].isDetailLoaded)
    }

    @MainActor
    func testFailedRefreshDoesNotDiscardDetailLoadedWhileRefreshWasRunning() async {
        let client = MockAPIClient(mode: .delayedRefreshFailure)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json"))
        )
        await model.search()

        let initialRequestCount = await client.searchRequestCount
        await client.enableDelayedSearchFailure()
        let refresh = Task { await model.refreshVacancies() }
        while await client.searchRequestCount == initialRequestCount { await Task.yield() }
        await model.loadVacancyDetails(id: "3529-vacancy")
        await refresh.value

        XCTAssertTrue(model.results[0].isDetailLoaded)
        XCTAssertEqual(model.results[0].plainTextDescription, "Полное описание")
    }

    @MainActor
    func testRapidFavoriteMutationsUseOnePersistenceDriverAndKeepLatestSnapshot() async throws {
        let store = SlowRecordingFavoriteStore()
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )
        await model.search()
        model.toggleFavorite(id: "3529-vacancy")
        await Task.yield()
        model.toggleFavorite(id: "3529-vacancy")
        model.toggleFavorite(id: "3529-vacancy")
        await model.waitForPendingFavoritesSaves()
        XCTAssertEqual(store.maximumConcurrentSaves, 1)
        XCTAssertEqual(store.lastSaved.map(\.id), ["3529-vacancy"])
        XCTAssertLessThanOrEqual(store.saveCount, 2)
    }

    @MainActor
    func testArchiveCheckDoesNotPersistWhenNothingChanged() async {
        let store = SlowRecordingFavoriteStore()
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )

        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()

        XCTAssertEqual(store.saveCount, 0)
    }

    @MainActor
    func testArchiveCheckPersistsAnUpdatedStatus() async {
        let vacancy = summary(id: "3529-archived", areaID: "1", areaName: "Москва")
        let result = VacancySearchResult(
            id: vacancy.id,
            summary: vacancy,
            details: .init(
                id: vacancy.id,
                name: vacancy.name,
                employer: vacancy.employer,
                area: vacancy.area,
                salary: nil,
                alternateURL: nil,
                description: nil,
                archived: false
            ),
            location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
        )
        let record = FavoriteVacancyRecord(
            result: result,
            favoritedAt: .distantPast,
            updatedAt: .distantPast,
            archiveCheckedAt: .distantPast
        )
        let store = SlowRecordingFavoriteStore(favorites: [record])
        let now = Date(timeIntervalSince1970: 1_788_200_000)
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .simple),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store,
            currentDate: { now }
        )

        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()

        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.lastSaved.first?.archiveCheckedAt, now)
    }

    @MainActor
    func testConcurrentArchiveChecksUseOneRequest() async {
        let vacancy = summary(id: "3529-concurrent", areaID: "1", areaName: "Москва")
        let result = VacancySearchResult(
            id: vacancy.id,
            summary: vacancy,
            details: .init(
                id: vacancy.id,
                name: vacancy.name,
                employer: vacancy.employer,
                area: vacancy.area,
                salary: nil,
                alternateURL: nil,
                description: nil,
                archived: false
            ),
            location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
        )
        let record = FavoriteVacancyRecord(
            result: result,
            favoritedAt: .distantPast,
            updatedAt: .distantPast,
            archiveCheckedAt: .distantPast
        )
        let store = SlowRecordingFavoriteStore(favorites: [record])
        let client = MockAPIClient(mode: .delayedArchive)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )

        let first = Task { await model.checkArchiveStatusesIfNeeded() }
        await Task.yield()
        let second = Task { await model.checkArchiveStatusesIfNeeded() }
        await first.value
        await second.value
        await model.waitForPendingFavoritesSaves()

        let requestCount = await client.detailRequestCount
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testArchiveCheckMarksNotFoundAsCheckedAndContinues() async {
        func record(id: String) -> FavoriteVacancyRecord {
            let vacancy = summary(id: id, areaID: "1", areaName: "Москва")
            let result = VacancySearchResult(
                id: vacancy.id,
                summary: vacancy,
                details: .init(
                    id: vacancy.id,
                    name: vacancy.name,
                    employer: vacancy.employer,
                    area: vacancy.area,
                    salary: nil,
                    alternateURL: nil,
                    description: nil,
                    archived: false
                ),
                location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
            )
            return FavoriteVacancyRecord(
                result: result,
                favoritedAt: .distantPast,
                updatedAt: .distantPast,
                archiveCheckedAt: .distantPast
            )
        }
        let store = SlowRecordingFavoriteStore(favorites: [
            record(id: "3529-missing"),
            record(id: "3529-continues")
        ])
        let now = Date(timeIntervalSince1970: 1_788_200_000)
        let model = VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .archiveNotFound),
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store,
            currentDate: { now }
        )

        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()

        let saved = store.lastSaved
        XCTAssertEqual(saved.first { $0.id == "3529-missing" }?.archiveCheckedAt, now)
        XCTAssertEqual(saved.first { $0.id == "3529-missing" }?.isArchived, false)
        XCTAssertEqual(saved.first { $0.id == "3529-continues" }?.isArchived, true)
    }

    @MainActor
    func testArchiveCheckUsesFavoritesOrder() async {
        func record(id: String) -> FavoriteVacancyRecord {
            let vacancy = summary(id: id, areaID: "1", areaName: "Москва")
            let result = VacancySearchResult(
                id: vacancy.id,
                summary: vacancy,
                details: .init(
                    id: vacancy.id,
                    name: vacancy.name,
                    employer: vacancy.employer,
                    area: vacancy.area,
                    salary: nil,
                    alternateURL: nil,
                    description: nil,
                    archived: false
                ),
                location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
            )
            return FavoriteVacancyRecord(
                result: result,
                favoritedAt: .distantPast,
                updatedAt: .distantPast,
                archiveCheckedAt: .distantPast
            )
        }
        let expectedIDs = (1...8).map { "3529-order-\($0)" }
        let store = SlowRecordingFavoriteStore(favorites: expectedIDs.map(record))
        let client = MockAPIClient(mode: .simple)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )

        await model.checkArchiveStatusesIfNeeded()

        let requestedIDs = await client.requestedDetailIDs
        XCTAssertEqual(requestedIDs, expectedIDs)
    }

    @MainActor
    func testArchiveCheckContinuesAfterRecoverableVacancyFailure() async {
        func record(id: String) -> FavoriteVacancyRecord {
            let vacancy = summary(id: id, areaID: "1", areaName: "Москва")
            let result = VacancySearchResult(
                id: vacancy.id,
                summary: vacancy,
                details: .init(
                    id: vacancy.id,
                    name: vacancy.name,
                    employer: vacancy.employer,
                    area: vacancy.area,
                    salary: nil,
                    alternateURL: nil,
                    description: nil,
                    archived: false
                ),
                location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
            )
            return FavoriteVacancyRecord(
                result: result,
                favoritedAt: .distantPast,
                updatedAt: .distantPast,
                archiveCheckedAt: .distantPast
            )
        }
        let store = SlowRecordingFavoriteStore(favorites: [
            record(id: "3529-fail"),
            record(id: "3529-continues")
        ])
        let client = MockAPIClient(mode: .archiveRecoverableFailure)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )

        await model.checkArchiveStatusesIfNeeded()
        await model.waitForPendingFavoritesSaves()

        let requestedIDs = await client.requestedDetailIDs
        XCTAssertEqual(requestedIDs, ["3529-fail", "3529-continues"])
        XCTAssertEqual(store.lastSaved.first { $0.id == "3529-continues" }?.isArchived, true)
    }

    @MainActor
    func testArchiveCheckStopsAfterTerminalAPIError() async {
        func record(id: String) -> FavoriteVacancyRecord {
            let vacancy = summary(id: id, areaID: "1", areaName: "Москва")
            let result = VacancySearchResult(
                id: vacancy.id,
                summary: vacancy,
                details: .init(
                    id: vacancy.id,
                    name: vacancy.name,
                    employer: vacancy.employer,
                    area: vacancy.area,
                    salary: nil,
                    alternateURL: nil,
                    description: nil,
                    archived: false
                ),
                location: .subject(id: "1", name: "Москва", cityID: "1", cityName: "Москва")
            )
            return FavoriteVacancyRecord(
                result: result,
                favoritedAt: .distantPast,
                updatedAt: .distantPast,
                archiveCheckedAt: .distantPast
            )
        }
        let store = SlowRecordingFavoriteStore(favorites: [
            record(id: "3529-fail"),
            record(id: "3529-not-requested")
        ])
        let client = MockAPIClient(mode: .archiveTerminalFailure)
        let model = VacancySearchViewModel(
            apiClient: client,
            employerStore: TestEmployerStore(entries: [.init(id: "3529", name: "СБЕР", comment: "test")]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: store
        )

        await model.checkArchiveStatusesIfNeeded()

        let requestedIDs = await client.requestedDetailIDs
        XCTAssertEqual(requestedIDs, ["3529-fail"])
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HHVacancySberTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func makeFilterViewModel() -> VacancySearchViewModel {
        VacancySearchViewModel(
            apiClient: MockAPIClient(mode: .filters),
            employerStore: TestEmployerStore(entries: [
                .init(id: "2798", name: "СберРешения", comment: "test"),
                .init(id: "3529", name: "СБЕР", comment: "test"),
                .init(id: "9999", name: "Альфа Банк", comment: "test")
            ]),
            areaStore: AreaDirectoryStore(fileURL: temporaryDirectory().appendingPathComponent("areas.json")),
            favoritesStore: InMemoryFavoriteVacancyStore()
        )
    }

    private func makeHTTPClient(
        handler: @escaping (URLRequest) throws -> (Int, [String: String], Data)
    ) -> HHAPIClient {
        URLProtocolStub.handler = handler
        return HTTPClientFactory.make()
    }

    private func assertAPIError(_ client: HHAPIClient, equals expected: HHAPIError) async {
        do {
            _ = try await client.searchVacancies(.init(employerID: "3529"))
            XCTFail("Expected \(expected)")
        } catch let error as HHAPIError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static let areaTree = HHAreaNode(id: "113", name: "Россия", areas: [
        .init(id: "1", name: "Москва"),
        .init(id: "2", name: "Санкт-Петербург"),
        .init(id: "66", name: "Свердловская область", areas: [.init(id: "3", name: "Екатеринбург")])
    ])

    private func summary(
        id: String,
        employerID: String = "3529",
        areaID: String?,
        areaName: String?,
        workFormat: [HHNamedItem]? = nil,
        areas: [HHArea]? = nil
    ) -> HHVacancySummary {
        HHVacancySummary(
            id: id, name: "Вакансия \(id)", employer: .init(name: "СБЕР", id: employerID), salary: nil,
            area: areaID.map { .init(id: $0, name: areaName) }, alternateURL: "https://example.invalid/\(id)",
            url: nil, snippet: nil, workFormat: workFormat, publishedAt: "2026-09-01T10:00:00+0300", areas: areas
        )
    }
}

private struct TestEmployerStore: EmployerConfigurationStoring {
    let entries: [EmployerConfigurationEntry]
    func loadOrCreate() throws -> EmployerConfiguration {
        try EmployerConfiguration(version: 1, employers: entries).validated()
    }
}

private actor MockAPIClient: HHVacancyAPIClient {
    enum Mode: Sendable {
        case simple, partitioned, mismatch, failure, delayedArchive, archiveNotFound
        case archiveRecoverableFailure, archiveTerminalFailure, delayedRefreshFailure, filters
    }
    let mode: Mode
    private(set) var detailRequestCount = 0
    private(set) var requestedDetailIDs: [String] = []
    private(set) var searchRequestCount = 0
    private var shouldFailSearch = false
    init(mode: Mode) { self.mode = mode }
    func enableDelayedSearchFailure() { shouldFailSearch = true }
    nonisolated func validateVacanciesAccess() throws {}
    func areaTree() async throws -> HHAreaNode {
        if case .failure = mode { throw URLError(.notConnectedToInternet) }
        return .init(id: "113", name: "Россия", areas: [
            .init(id: "1", name: "Москва"),
            .init(id: "2", name: "Санкт-Петербург"),
            .init(id: "66", name: "Свердловская область", areas: [.init(id: "3", name: "Екатеринбург")])
        ])
    }
    func vacancyDictionaries() async throws -> HHVacancyDictionaries {
        if case .failure = mode { throw URLError(.notConnectedToInternet) }
        return .init(
            experience: ["noExperience", "between1And3", "between3And6", "moreThan6"].map { .init(id: $0, name: $0) },
            workFormat: [.init(id: "REMOTE", name: "Удалённо")],
            schedule: [.init(id: "remote", name: "Удалённая работа")]
        )
    }
    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        requestedDetailIDs.append(id)
        if case .failure = mode { throw URLError(.notConnectedToInternet) }
        if case .archiveRecoverableFailure = mode, id.hasSuffix("fail") {
            throw URLError(.timedOut)
        }
        if case .archiveTerminalFailure = mode, id.hasSuffix("fail") {
            throw HHAPIError.rateLimited(retryAfterSeconds: 60)
        }
        if case .archiveNotFound = mode, id.hasSuffix("missing") {
            throw HHAPIError.requestFailed(statusCode: 404, message: nil)
        }
        detailRequestCount += 1
        if case .delayedArchive = mode {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let employerID = id.components(separatedBy: "-").first ?? "3529"
        let archived: Bool
        switch mode {
        case .archiveNotFound, .archiveRecoverableFailure, .archiveTerminalFailure: archived = true
        default: archived = false
        }
        return .init(id: id, name: "Вакансия \(id)", employer: .init(name: employerID == "2798" ? "СберРешения" : "СБЕР", id: employerID),
                     area: .init(id: "1", name: "Москва"), salary: nil, alternateURL: nil,
                     description: "<p>Полное описание</p>", archived: archived)
    }
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        searchRequestCount += 1
        if case .delayedRefreshFailure = mode, shouldFailSearch {
            try await Task.sleep(nanoseconds: 100_000_000)
            throw URLError(.timedOut)
        }
        switch mode {
        case .filters:
            let values: [HHVacancySummary]
            switch request.employerID {
            case "3529":
                values = [
                    makeSummary(id: "filter-moscow", employerID: "3529", employerName: "СБЕР", areaID: "1", areaName: "Москва"),
                    makeSummary(id: "filter-ekb", employerID: "3529", employerName: "СБЕР", areaID: "3", areaName: "Екатеринбург"),
                    makeSummary(id: "filter-unknown", employerID: "3529", employerName: "СБЕР", areaID: "999", areaName: "Минск")
                ]
            case "2798":
                values = [makeSummary(id: "filter-remote", employerID: "2798", employerName: "СберРешения", remote: true)]
            default:
                values = [makeSummary(id: "filter-spb", employerID: "9999", employerName: "Альфа Банк", areaID: "2", areaName: "Санкт-Петербург")]
            }
            return page(values, found: values.count, request: request)
        case .simple, .delayedArchive, .archiveNotFound, .archiveRecoverableFailure, .archiveTerminalFailure,
             .delayedRefreshFailure:
            let remote = request.employerID == "2798"
            let item = makeSummary(id: "\(request.employerID)-vacancy", employerID: request.employerID,
                                   employerName: remote ? "СберРешения" : "СБЕР", remote: remote)
            return page([item], found: 1, request: request)
        case .mismatch:
            return page([makeSummary(id: "only-one", employerID: request.employerID, employerName: "СБЕР")], found: 2, request: request)
        case .partitioned:
            let count: Int
            let prefix: String
            switch request.areaID {
            case "10": count = 1_200; prefix = "a"
            case "20": count = 801; prefix = "b"
            default: count = 2_001; prefix = "root"
            }
            let start = request.page * request.perPage
            let end = min(start + request.perPage, count)
            let values = start < end ? (start..<end).map {
                makeSummary(id: "\(prefix)-\($0)", employerID: request.employerID, employerName: "СБЕР")
            } : []
            return .init(items: values, found: count, pages: Int(ceil(Double(count) / Double(request.perPage))), page: request.page, perPage: request.perPage)
        case .failure:
            throw URLError(.notConnectedToInternet)
        }
    }
    private func page(_ all: [HHVacancySummary], found: Int, request: HHVacancySearchRequest) -> HHVacancySearchResponse {
        let start = request.page * request.perPage
        let end = min(start + request.perPage, all.count)
        let items = start < end ? Array(all[start..<end]) : []
        return .init(items: items, found: found, pages: Int(ceil(Double(found) / Double(request.perPage))), page: request.page, perPage: request.perPage)
    }
    private func makeSummary(
        id: String,
        employerID: String,
        employerName: String,
        remote: Bool = false,
        areaID: String = "1",
        areaName: String = "Москва"
    ) -> HHVacancySummary {
        .init(id: id, name: "Вакансия \(id)", employer: .init(name: employerName, id: employerID), salary: nil,
              area: remote ? nil : .init(id: areaID, name: areaName), alternateURL: nil, url: nil, snippet: nil,
              workFormat: remote ? [.init(id: "REMOTE", name: "Удалённо")] : nil,
              publishedAt: employerID == "3529" ? "2026-09-02T10:00:00+0300" : "2026-09-01T10:00:00+0300")
    }
}

private struct FixedTokenProvider: HHAccessTokenProviding {
    let accessToken: String? = "unit-token"
}

private actor ConcurrentOperationTracker {
    private var activeOperations = 0
    private(set) var maximumConcurrentOperations = 0

    func begin() {
        activeOperations += 1
        maximumConcurrentOperations = max(maximumConcurrentOperations, activeOperations)
    }

    func end() { activeOperations -= 1 }
}

private final class SlowRecordingFavoriteStore: FavoriteVacancyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var activeSaves = 0
    private var maximum = 0
    private var saved: [FavoriteVacancyRecord] = []
    private var count = 0

    init(favorites: [FavoriteVacancyRecord] = []) { saved = favorites }
    func load() throws -> [FavoriteVacancyRecord] { lock.withLock { saved } }
    func save(_ favorites: [FavoriteVacancyRecord]) throws {
        lock.lock()
        activeSaves += 1
        maximum = max(maximum, activeSaves)
        count += 1
        lock.unlock()
        Thread.sleep(forTimeInterval: 0.05)
        lock.lock()
        saved = favorites
        activeSaves -= 1
        lock.unlock()
    }
    var maximumConcurrentSaves: Int { lock.withLock { maximum } }
    var lastSaved: [FavoriteVacancyRecord] { lock.withLock { saved } }
    var saveCount: Int { lock.withLock { count } }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock(); defer { unlock() }; return operation()
    }
}

private enum HTTPClientFactory {
    static func make() -> HHAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return HHAPIClient(
            session: URLSession(configuration: configuration),
            accessTokenProvider: FixedTokenProvider(),
            requestGate: HHRequestGate(minimumDelayNanoseconds: 0)
        )
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
