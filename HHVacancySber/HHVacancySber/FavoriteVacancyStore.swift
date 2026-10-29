import Foundation

struct FavoriteVacancyRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var employerID: String?
    var employerName: String
    var departmentName: String?
    var publishedAt: String?
    var location: VacancyLocation
    var salaryText: String?
    var alternateURL: String?
    var snippet: String?
    var descriptionHTML: String?
    var detailsSnapshot: HHVacancyDetails?
    var isArchived: Bool
    var archiveCheckedAt: Date?
    let favoritedAt: Date
    var updatedAt: Date

    init(result: VacancySearchResult, favoritedAt: Date, updatedAt: Date, archiveCheckedAt: Date? = nil) {
        id = result.id
        name = result.name
        employerID = result.employerID
        employerName = result.employerName
        departmentName = result.departmentName
        publishedAt = result.publishedAt
        location = result.location
        salaryText = result.salaryText
        alternateURL = result.alternateURL
        snippet = result.summary.snippet?.plainText.nilIfBlank
        descriptionHTML = result.htmlDescription.nilIfBlank
        detailsSnapshot = result.isDetailLoaded ? result.details : nil
        isArchived = result.isArchived
        self.archiveCheckedAt = archiveCheckedAt
        self.favoritedAt = favoritedAt
        self.updatedAt = updatedAt
    }

    @discardableResult
    mutating func update(from result: VacancySearchResult, at date: Date) -> Bool {
        let previous = self
        name = result.name.nilIfBlank ?? name
        employerID = result.employerID ?? employerID
        employerName = result.employerName.nilIfBlank ?? employerName
        departmentName = result.departmentName ?? departmentName
        publishedAt = result.publishedAt ?? publishedAt
        location = result.location
        salaryText = result.salaryText ?? salaryText
        alternateURL = result.alternateURL ?? alternateURL
        snippet = result.summary.snippet?.plainText.nilIfBlank ?? snippet
        descriptionHTML = result.htmlDescription.nilIfBlank ?? descriptionHTML
        if result.isDetailLoaded { detailsSnapshot = result.details }
        isArchived = result.isArchived
        archiveCheckedAt = result.archiveCheckedAt ?? archiveCheckedAt
        guard previous != self else { return false }
        updatedAt = date
        return true
    }

    mutating func updateArchiveStatus(_ archived: Bool, checkedAt: Date) {
        isArchived = archived
        archiveCheckedAt = checkedAt
        updatedAt = checkedAt
    }

    var searchResult: VacancySearchResult {
        let summary = HHVacancySummary(
            id: id,
            name: name,
            employer: HHEmployer(name: employerName, id: employerID),
            salary: nil,
            area: HHArea(id: location.cityID ?? location.subjectID, name: location.cityName ?? location.subjectName),
            alternateURL: alternateURL,
            url: nil,
            snippet: HHVacancySnippet(requirement: snippet, responsibility: nil),
            department: departmentName.map { HHNamedItem(name: $0) },
            publishedAt: publishedAt
        )
        let details = detailsSnapshot ?? HHVacancyDetails(
            id: id,
            name: name,
            employer: HHEmployer(name: employerName, id: employerID),
            area: summary.area,
            salary: nil,
            alternateURL: alternateURL,
            description: descriptionHTML,
            archived: isArchived,
            department: departmentName.map { HHNamedItem(name: $0) }
        )
        return VacancySearchResult(
            id: id,
            summary: summary,
            details: details,
            location: location,
            isDetailLoaded: detailsSnapshot != nil,
            persistedSalaryText: salaryText,
            isArchived: isArchived,
            archiveCheckedAt: archiveCheckedAt
        )
    }

    /// Combine the current search row with the persisted favorite's richer data.
    func merging(_ current: VacancySearchResult) -> VacancySearchResult {
        let saved = searchResult
        let useCurrentDetails = current.isDetailLoaded || current.hasFullDescription
        let details = useCurrentDetails ? current.details : saved.details
        let useCurrentStatus = (current.archiveCheckedAt ?? .distantPast) > (archiveCheckedAt ?? .distantPast)
        return VacancySearchResult(
            id: current.id, summary: current.summary, details: details, location: current.location,
            isDetailLoaded: current.isDetailLoaded || (!useCurrentDetails && saved.isDetailLoaded),
            isDetailLoading: current.isDetailLoading, detailErrorMessage: current.detailErrorMessage,
            persistedSalaryText: current.persistedSalaryText ?? salaryText,
            isArchived: useCurrentStatus ? current.isArchived : isArchived,
            archiveCheckedAt: useCurrentStatus ? current.archiveCheckedAt : archiveCheckedAt,
            exportDataNotice: current.exportDataNotice
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, employerID, employerName, departmentName, publishedAt, location, salaryText, alternateURL
        case snippet, descriptionHTML, detailsSnapshot, isArchived, archiveCheckedAt, favoritedAt, updatedAt
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(employerID, forKey: .employerID)
        try values.encode(employerName, forKey: .employerName)
        try values.encodeIfPresent(departmentName, forKey: .departmentName)
        try values.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try values.encode(location, forKey: .location)
        try values.encodeIfPresent(salaryText, forKey: .salaryText)
        try values.encodeIfPresent(alternateURL, forKey: .alternateURL)
        try values.encodeIfPresent(snippet, forKey: .snippet)
        try values.encodeIfPresent(descriptionHTML, forKey: .descriptionHTML)
        try values.encodeIfPresent(detailsSnapshot, forKey: .detailsSnapshot)
        try values.encode(isArchived, forKey: .isArchived)
        try values.encodeIfPresent(archiveCheckedAt, forKey: .archiveCheckedAt)
        try values.encode(favoritedAt, forKey: .favoritedAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        employerID = try values.decodeIfPresent(String.self, forKey: .employerID)
        employerName = try values.decode(String.self, forKey: .employerName)
        departmentName = try values.decodeIfPresent(String.self, forKey: .departmentName)
        publishedAt = try values.decodeIfPresent(String.self, forKey: .publishedAt)
        detailsSnapshot = try values.decodeIfPresent(HHVacancyDetails.self, forKey: .detailsSnapshot)
        if let stored = try values.decodeIfPresent(VacancyLocation.self, forKey: .location) {
            location = stored
        } else {
            location = .unknown
        }
        salaryText = try values.decodeIfPresent(String.self, forKey: .salaryText)
        alternateURL = try values.decodeIfPresent(String.self, forKey: .alternateURL)
        snippet = try values.decodeIfPresent(String.self, forKey: .snippet)
        descriptionHTML = try values.decodeIfPresent(String.self, forKey: .descriptionHTML)
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        archiveCheckedAt = try values.decodeIfPresent(Date.self, forKey: .archiveCheckedAt)
        favoritedAt = try values.decode(Date.self, forKey: .favoritedAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}

private struct FavoriteVacancyContainer: Codable {
    static let currentVersion = 2
    let version: Int
    let favorites: [FavoriteVacancyRecord]
}

private struct ContainerVersion: Decodable { let version: Int }

struct FavoriteLoadResult: Sendable {
    let records: [FavoriteVacancyRecord]
    let warning: String?
}

protocol FavoriteVacancyStoring: Sendable {
    func load() throws -> [FavoriteVacancyRecord]
    func loadWithWarning() throws -> FavoriteLoadResult
    func save(_ favorites: [FavoriteVacancyRecord]) throws
}

extension FavoriteVacancyStoring {
    func loadWithWarning() throws -> FavoriteLoadResult { .init(records: try load(), warning: nil) }
}

/// Serialize foreground termination flush with the background writer.
final class SerializedFavoriteStore: FavoriteVacancyStoring, @unchecked Sendable {
    private let store: any FavoriteVacancyStoring
    private let lock = NSLock()
    init(_ store: any FavoriteVacancyStoring) { self.store = store }
    func load() throws -> [FavoriteVacancyRecord] { try loadWithWarning().records }
    func loadWithWarning() throws -> FavoriteLoadResult {
        lock.lock(); defer { lock.unlock() }; return try store.loadWithWarning()
    }
    func save(_ favorites: [FavoriteVacancyRecord]) throws {
        lock.lock(); defer { lock.unlock() }; try store.save(favorites)
    }
}

enum FavoriteVacancyStoreError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case corruptedFile
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "Версия файла избранного \(version) не поддерживается."
        case .corruptedFile: return "Файл избранного повреждён."
        }
    }
}

struct FavoriteVacancyStore: FavoriteVacancyStoring, @unchecked Sendable {
    private let configuredFileURL: URL?
    private let fileManager: FileManager
    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        configuredFileURL = fileURL
        self.fileManager = fileManager
    }

    var fileURL: URL {
        get throws {
            if let configuredFileURL { return configuredFileURL }
            return try ApplicationSupportLocation.fileURL(named: "favorites.json", fileManager: fileManager)
        }
    }

    func load() throws -> [FavoriteVacancyRecord] { try loadWithWarning().records }

    func loadWithWarning() throws -> FavoriteLoadResult {
        let fileURL = try self.fileURL
        guard fileManager.fileExists(atPath: fileURL.path) else { return .init(records: [], warning: nil) }
        let data = try Data(contentsOf: fileURL)
        if data.trimmingJSONWhitespace == Data("[]".utf8) { return .init(records: [], warning: nil) }
        let decoder = JSONDecoder.favoritesDecoder
        guard let version = try? decoder.decode(ContainerVersion.self, from: data).version else {
            _ = try CorruptFileBackup.copy(fileURL, fileManager: fileManager)
            throw FavoriteVacancyStoreError.corruptedFile
        }
        guard version == 1 || version == FavoriteVacancyContainer.currentVersion else {
            throw FavoriteVacancyStoreError.unsupportedVersion(version)
        }
        struct Recovery: Decodable { let favorites: [RecoverableItem<FavoriteVacancyRecord>] }
        guard let container = try? decoder.decode(Recovery.self, from: data) else {
            _ = try CorruptFileBackup.copy(fileURL, fileManager: fileManager)
            throw FavoriteVacancyStoreError.corruptedFile
        }
        var seen = Set<String>()
        let records = container.favorites.compactMap(\.value).filter { seen.insert($0.id).inserted }
        let skipped = container.favorites.count - records.count
        var warning: String?
        if skipped > 0 {
            let backup = try CorruptFileBackup.copy(fileURL, fileManager: fileManager)
            warning = "Избранное восстановлено частично: пропущено записей \(skipped). Копия исходного файла: \(backup.lastPathComponent)."
        }
        if version == 1 && skipped == 0 {
            do { try save(records) }
            catch { warning = "Не удалось обновить формат избранного: \(error.localizedDescription). Прочитанные записи сохранены в памяти." }
        }
        return .init(records: records, warning: warning)
    }

    func save(_ favorites: [FavoriteVacancyRecord]) throws {
        let fileURL = try self.fileURL
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let value = FavoriteVacancyContainer(version: FavoriteVacancyContainer.currentVersion, favorites: favorites)
        try JSONEncoder.favoritesEncoder.encode(value).write(to: fileURL, options: .atomic)
    }
}

final class InMemoryFavoriteVacancyStore: FavoriteVacancyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [FavoriteVacancyRecord]
    init(favorites: [FavoriteVacancyRecord] = []) { records = favorites }
    func load() throws -> [FavoriteVacancyRecord] { lock.lock(); defer { lock.unlock() }; return records }
    func save(_ favorites: [FavoriteVacancyRecord]) throws { lock.lock(); records = favorites; lock.unlock() }
}

private extension JSONEncoder {
    static var favoritesEncoder: JSONEncoder {
        let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; value.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return value
    }
}
private extension JSONDecoder {
    static var favoritesDecoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}
private extension Data {
    var trimmingJSONWhitespace: Data {
        Data(drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }).reversed().drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }).reversed())
    }
}
