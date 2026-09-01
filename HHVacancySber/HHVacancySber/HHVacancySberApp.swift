import SwiftUI

@main
struct HHVacancySberApp: App {
    @StateObject private var viewModel: VacancySearchViewModel

    init() { _viewModel = StateObject(wrappedValue: AppComposition.makeViewModel()) }

    var body: some Scene {
        Window("СберВакансии", id: "main") { ContentView(viewModel: viewModel) }
            .defaultSize(width: WindowLayoutPolicy.defaultSize.width, height: WindowLayoutPolicy.defaultSize.height)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
enum AppComposition {
    static func makeViewModel(environment: [String: String] = ProcessInfo.processInfo.environment) -> VacancySearchViewModel {
#if DEBUG
        if environment["HHVACANCYSBER_UI_TEST_MODE"] == "1" {
            return makeUITestViewModel(scenario: environment["HHVACANCYSBER_UI_TEST_SCENARIO"] ?? "default")
        }
#endif
        let defaultURL = Bundle.main.url(forResource: "employers", withExtension: "json")
        return VacancySearchViewModel(
            apiClient: HHAPIClient(),
            employerStore: EmployerConfigurationStore(bundledDefaultURL: defaultURL),
            favoritesStore: FavoriteVacancyStore()
        )
    }
}

#if DEBUG
private struct UITestEmployerStore: EmployerConfigurationStoring {
    func loadOrCreate() throws -> EmployerConfiguration {
        try EmployerConfiguration(version: 1, employers: [
            .init(id: "3529", name: "СБЕР", comment: "UI test")
        ]).validated()
    }
}

private struct UITestAPIClient: HHVacancyAPIClient {
    let scenario: String
    func validateVacanciesAccess() throws {}
    func areaTree() async throws -> HHAreaNode {
        .init(id: "113", name: "Россия", areas: [
            .init(id: "1", name: "Москва"),
            .init(id: "2", name: "Санкт-Петербург"),
            .init(id: "66", name: "Свердловская область", areas: [.init(id: "3", name: "Екатеринбург")])
        ])
    }
    func vacancyDictionaries() async throws -> HHVacancyDictionaries {
        .init(experience: [.init(id: "noExperience", name: "Нет опыта")], workFormat: [], schedule: [])
    }
    func searchVacancies(_ request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        if scenario == "searchError" { throw HHAPIError.requestFailed(statusCode: 503, message: "test") }
        let values = scenario == "empty" ? [] : UITestFixtures.summaries.filter { $0.employer?.id == request.employerID }
        let start = request.page * request.perPage
        let items = start < values.count ? Array(values[start..<min(start + request.perPage, values.count)]) : []
        return .init(items: items, found: values.count, pages: max(1, Int(ceil(Double(values.count) / Double(request.perPage)))), page: request.page, perPage: request.perPage)
    }
    func vacancyDetails(id: String) async throws -> HHVacancyDetails {
        guard let value = UITestFixtures.details[id] else { throw HHAPIError.invalidResponse }
        return value
    }
}

private enum UITestFixtures {
    static let summaries = [
        HHVacancySummary(
            id: "ui-1", name: "Системный аналитик", employer: .init(name: "СБЕР", id: "3529"),
            salary: .init(from: 150_000, to: 220_000, currency: "RUR", gross: false),
            area: .init(id: "1", name: "Москва"), alternateURL: "https://example.invalid/ui-1", url: nil,
            snippet: .init(requirement: "Анализ требований", responsibility: "Развитие системы"),
            department: .init(id: "3529-it", name: "Сбер. IT"), publishedAt: "2026-09-01T10:00:00+0300"
        ),
        HHVacancySummary(
            id: "ui-2", name: "Менеджер", employer: .init(name: "СБЕР", id: "3529"), salary: nil,
            area: .init(id: "3", name: "Екатеринбург"), alternateURL: "https://example.invalid/ui-2", url: nil,
            snippet: .init(requirement: nil, responsibility: "Работа с клиентами"), publishedAt: "2026-08-31T10:00:00+0300"
        )
    ]
    static let details = Dictionary(uniqueKeysWithValues: summaries.map {
        ($0.id, HHVacancyDetails(
            id: $0.id, name: $0.name, employer: $0.employer, area: $0.area, salary: $0.salary,
            alternateURL: $0.alternateURL, description: "<p>Полное описание вакансии.</p>", archived: false,
            department: $0.department
        ))
    })
}

private extension AppComposition {
    static func makeUITestViewModel(scenario: String) -> VacancySearchViewModel {
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("HHVacancySber-UI-areas-\(UUID().uuidString).json")
        return VacancySearchViewModel(
            apiClient: UITestAPIClient(scenario: scenario),
            employerStore: UITestEmployerStore(),
            areaStore: AreaDirectoryStore(fileURL: cacheURL),
            favoritesStore: InMemoryFavoriteVacancyStore(),
            currentDate: { Date(timeIntervalSince1970: 1_788_200_000) }
        )
    }
}
#endif
