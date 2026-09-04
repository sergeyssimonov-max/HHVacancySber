import Foundation

struct VacancyCollectionProgress: Equatable, Sendable {
    let employerName: String
    let loadedCount: Int
    let partition: String
}

struct VacancyCompletenessError: LocalizedError, Equatable {
    let employerID: String
    let partition: String
    let expected: Int
    let actual: Int

    var errorDescription: String? {
        "Неполная выгрузка работодателя \(employerID), раздел «\(partition)»: ожидалось \(expected), получено \(actual)."
    }
}

struct VacancyCollectionService: Sendable {
    static let maximumAccessibleResults = 2_000
    static let perPage = 100
    private let client: any HHVacancyAPIClient
    private let now: @Sendable () -> Date

    init(client: any HHVacancyAPIClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    func collect(
        employers: [EmployerConfigurationEntry],
        areas: AreaDirectoryIndex,
        progress: @escaping @MainActor @Sendable (VacancyCollectionProgress) -> Void
    ) async throws -> [HHVacancySummary] {
        var all: [String: HHVacancySummary] = [:]
        for employer in employers {
            try Task.checkCancellation()
            let items: [HHVacancySummary]
            do {
                items = try await collectEmployer(employer, areas: areas, progress: progress)
            } catch is VacancyCompletenessError {
                items = try await collectEmployer(employer, areas: areas, progress: progress)
            }
            for item in items { all[item.id] = item }
        }
        return Array(all.values)
    }

    private func collectEmployer(
        _ employer: EmployerConfigurationEntry,
        areas: AreaDirectoryIndex,
        progress: @escaping @MainActor @Sendable (VacancyCollectionProgress) -> Void
    ) async throws -> [HHVacancySummary] {
        let request = HHVacancySearchRequest(employerID: employer.id)
        let values = try await collectPartition(
            request,
            areaNode: areas.root,
            areas: areas,
            employer: employer,
            progress: progress
        )
        return Array(values.values)
    }

    private func collectPartition(
        _ request: HHVacancySearchRequest,
        areaNode: HHAreaNode,
        areas: AreaDirectoryIndex,
        employer: EmployerConfigurationEntry,
        progress: @escaping @MainActor @Sendable (VacancyCollectionProgress) -> Void
    ) async throws -> [String: HHVacancySummary] {
        let initialResponse = try await probe(for: request)
        let expected = initialResponse.found
        if expected <= Self.maximumAccessibleResults {
            return try await fetchLeaf(
                request,
                expected: expected,
                initialResponse: initialResponse,
                employer: employer,
                progress: progress
            )
        }

        let children = areas.children(of: areaNode.id)
        if !children.isEmpty {
            var combined: [String: HHVacancySummary] = [:]
            for child in children {
                let childRequest = replacing(request, areaID: child.id)
                let childValues = try await collectPartition(
                    childRequest,
                    areaNode: child,
                    areas: areas,
                    employer: employer,
                    progress: progress
                )
                combined.merge(childValues) { current, _ in current }
            }
            if combined.count == expected { return combined }
        }

        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 946_684_800)
        let end = calendar.date(byAdding: .day, value: 1, to: now()) ?? now()
        return try await collectByDate(
            request,
            start: request.dateFrom ?? start,
            end: request.dateTo ?? end,
            expected: expected,
            employer: employer,
            progress: progress
        )
    }

    private func collectByDate(
        _ request: HHVacancySearchRequest,
        start: Date,
        end: Date,
        expected: Int,
        employer: EmployerConfigurationEntry,
        progress: @escaping @MainActor @Sendable (VacancyCollectionProgress) -> Void
    ) async throws -> [String: HHVacancySummary] {
        let span = end.timeIntervalSince(start)
        guard span > 300 else {
            return try await collectByDictionaries(request, expected: expected, employer: employer, progress: progress)
        }
        let midpoint = Date(timeIntervalSince1970: floor(start.timeIntervalSince1970 + span / 2))
        let secondStart = midpoint.addingTimeInterval(1)
        var combined: [String: HHVacancySummary] = [:]
        for (lower, upper) in [(start, midpoint), (secondStart, end)] where lower <= upper {
            let child = replacing(request, dateFrom: lower, dateTo: upper)
            let initialResponse = try await probe(for: child)
            let count = initialResponse.found
            let values = count <= Self.maximumAccessibleResults
                ? try await fetchLeaf(
                    child,
                    expected: count,
                    initialResponse: initialResponse,
                    employer: employer,
                    progress: progress
                )
                : try await collectByDate(child, start: lower, end: upper, expected: count, employer: employer, progress: progress)
            combined.merge(values) { current, _ in current }
        }
        guard combined.count == expected else {
            throw VacancyCompletenessError(employerID: request.employerID, partition: partitionName(request), expected: expected, actual: combined.count)
        }
        return combined
    }

    private enum DictionaryDimension: String {
        case experience, workFormat, schedule
    }

    private func collectByDictionaries(
        _ request: HHVacancySearchRequest,
        expected: Int,
        employer: EmployerConfigurationEntry,
        progress: @escaping @MainActor @Sendable (VacancyCollectionProgress) -> Void
    ) async throws -> [String: HHVacancySummary] {
        let dictionaries = try await client.vacancyDictionaries()
        let dimensions: [(DictionaryDimension, [String])] = [
            (.experience, dictionaries.experience.compactMap(\.id)),
            (.workFormat, dictionaries.workFormat.compactMap(\.id)),
            (.schedule, dictionaries.schedule.compactMap(\.id))
        ].filter { !$0.1.isEmpty }
        return try await collectByDictionaryDimension(
            request,
            expected: expected,
            dimensions: dimensions,
            dimensionIndex: 0,
            employer: employer,
            progress: progress
        )
    }

    private func collectByDictionaryDimension(
        _ request: HHVacancySearchRequest,
        expected: Int,
        dimensions: [(DictionaryDimension, [String])],
        dimensionIndex: Int,
        employer: EmployerConfigurationEntry,
        progress: @escaping @MainActor @Sendable (VacancyCollectionProgress) -> Void
    ) async throws -> [String: HHVacancySummary] {
        guard dimensionIndex < dimensions.count else {
            throw VacancyCompletenessError(employerID: request.employerID, partition: partitionName(request), expected: expected, actual: 0)
        }
        let (dimension, values) = dimensions[dimensionIndex]
        var combined: [String: HHVacancySummary] = [:]
        for value in values {
            let child = replacing(request, dimension: dimension, value: value)
            let initialResponse = try await probe(for: child)
            let count = initialResponse.found
            let values = count <= Self.maximumAccessibleResults
                ? try await fetchLeaf(
                    child,
                    expected: count,
                    initialResponse: initialResponse,
                    employer: employer,
                    progress: progress
                )
                : try await collectByDictionaryDimension(
                    child,
                    expected: count,
                    dimensions: dimensions,
                    dimensionIndex: dimensionIndex + 1,
                    employer: employer,
                    progress: progress
                )
            combined.merge(values) { current, _ in current }
        }
        guard combined.count == expected else {
            throw VacancyCompletenessError(employerID: request.employerID, partition: partitionName(request), expected: expected, actual: combined.count)
        }
        return combined
    }

    private func replacing(
        _ request: HHVacancySearchRequest,
        dimension: DictionaryDimension,
        value: String
    ) -> HHVacancySearchRequest {
        HHVacancySearchRequest(
            employerID: request.employerID,
            areaID: request.areaID,
            page: request.page,
            perPage: request.perPage,
            dateFrom: request.dateFrom,
            dateTo: request.dateTo,
            experience: dimension == .experience ? value : request.experience,
            workFormat: dimension == .workFormat ? value : request.workFormat,
            schedule: dimension == .schedule ? value : request.schedule
        )
    }

    private func probe(for request: HHVacancySearchRequest) async throws -> HHVacancySearchResponse {
        try await client.searchVacancies(replacing(request, page: 0, perPage: Self.perPage))
    }

    private func fetchLeaf(
        _ request: HHVacancySearchRequest,
        expected: Int,
        initialResponse: HHVacancySearchResponse,
        employer: EmployerConfigurationEntry,
        progress: @escaping @MainActor @Sendable (VacancyCollectionProgress) -> Void
    ) async throws -> [String: HHVacancySummary] {
        guard expected > 0 else { return [:] }
        let pages = Int(ceil(Double(expected) / Double(Self.perPage)))
        var result: [String: HHVacancySummary] = [:]
        guard initialResponse.found == expected else {
            throw VacancyCompletenessError(
                employerID: request.employerID,
                partition: partitionName(request),
                expected: expected,
                actual: initialResponse.found
            )
        }
        for item in initialResponse.items { result[item.id] = item }
        await progress(.init(
            employerName: employer.name,
            loadedCount: result.count,
            partition: partitionName(request)
        ))
        for page in 1..<pages {
            try Task.checkCancellation()
            let response = try await client.searchVacancies(replacing(request, page: page, perPage: Self.perPage))
            guard response.found == expected else {
                throw VacancyCompletenessError(employerID: request.employerID, partition: partitionName(request), expected: expected, actual: response.found)
            }
            for item in response.items { result[item.id] = item }
            await progress(.init(employerName: employer.name, loadedCount: result.count, partition: partitionName(request)))
        }
        guard result.count == expected else {
            throw VacancyCompletenessError(employerID: request.employerID, partition: partitionName(request), expected: expected, actual: result.count)
        }
        return result
    }

    private func partitionName(_ request: HHVacancySearchRequest) -> String {
        var values = ["area=\(request.areaID)"]
        if request.dateFrom != nil || request.dateTo != nil { values.append("date") }
        if let experience = request.experience { values.append("experience=\(experience)") }
        if let workFormat = request.workFormat { values.append("work_format=\(workFormat)") }
        if let schedule = request.schedule { values.append("schedule=\(schedule)") }
        return values.joined(separator: ", ")
    }

    private func replacing(
        _ request: HHVacancySearchRequest,
        areaID: String? = nil,
        page: Int? = nil,
        perPage: Int? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        experience: String? = nil
    ) -> HHVacancySearchRequest {
        HHVacancySearchRequest(
            employerID: request.employerID,
            areaID: areaID ?? request.areaID,
            page: page ?? request.page,
            perPage: perPage ?? request.perPage,
            dateFrom: dateFrom ?? request.dateFrom,
            dateTo: dateTo ?? request.dateTo,
            experience: experience ?? request.experience,
            workFormat: request.workFormat,
            schedule: request.schedule
        )
    }
}
