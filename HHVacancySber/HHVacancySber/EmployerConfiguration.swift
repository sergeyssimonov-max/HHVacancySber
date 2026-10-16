import Foundation

struct EmployerConfigurationEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let comment: String
    let jointVenture: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, comment
        case jointVenture = "joint_venture"
    }

    init(id: String, name: String, comment: String, jointVenture: Bool? = nil) {
        self.id = id
        self.name = name
        self.comment = comment
        self.jointVenture = jointVenture
    }
}

struct EmployerConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let version: Int
    let employers: [EmployerConfigurationEntry]

    func validated() throws -> EmployerConfiguration {
        guard version == Self.currentVersion else { throw EmployerConfigurationError.unsupportedVersion(version) }
        guard !employers.isEmpty else { throw EmployerConfigurationError.empty }
        var ids = Set<String>()
        for employer in employers {
            guard !employer.id.isEmpty,
                  employer.id.utf8.allSatisfy({ (48...57).contains($0) }),
                  employer.id.first != "0",
                  employer.name.nilIfBlank != nil,
                  employer.comment.nilIfBlank != nil else {
                throw EmployerConfigurationError.invalidEntry(employer.id)
            }
            guard ids.insert(employer.id).inserted else { throw EmployerConfigurationError.duplicateID(employer.id) }
        }
        return self
    }
}

enum EmployerConfigurationError: LocalizedError, Equatable {
    case missingBundledDefault
    case empty
    case unsupportedVersion(Int)
    case invalidEntry(String)
    case duplicateID(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledDefault: return "В приложении отсутствует базовый employers.json."
        case .empty: return "Список работодателей пуст."
        case .unsupportedVersion(let version): return "Версия employers.json \(version) не поддерживается."
        case .invalidEntry(let id): return "Некорректная запись работодателя: \(id)."
        case .duplicateID(let id): return "Идентификатор работодателя \(id) указан повторно."
        }
    }
}

protocol EmployerConfigurationStoring: Sendable {
    func loadOrCreate() throws -> EmployerConfiguration
}

struct EmployerConfigurationStore: EmployerConfigurationStoring, @unchecked Sendable {
    private let configuredFileURL: URL?
    private let bundledDefaultURL: URL?
    private let fileManager: FileManager

    init(fileURL: URL? = nil, bundledDefaultURL: URL? = nil, fileManager: FileManager = .default) {
        configuredFileURL = fileURL
        self.bundledDefaultURL = bundledDefaultURL
        self.fileManager = fileManager
    }

    var fileURL: URL {
        get throws {
            if let configuredFileURL { return configuredFileURL }
            return try ApplicationSupportLocation.fileURL(named: "employers.json", fileManager: fileManager)
        }
    }

    func loadOrCreate() throws -> EmployerConfiguration {
        let fileURL = try self.fileURL
        if !fileManager.fileExists(atPath: fileURL.path) {
            guard let bundledDefaultURL else { throw EmployerConfigurationError.missingBundledDefault }
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Data(contentsOf: bundledDefaultURL)
            _ = try JSONDecoder().decode(EmployerConfiguration.self, from: data).validated()
            try data.write(to: fileURL, options: .atomic)
        }
        let current = try JSONDecoder().decode(EmployerConfiguration.self, from: Data(contentsOf: fileURL)).validated()
        // Upgrade only the exact shipped default. Any user edit, including a
        // comment, removal or reordering, makes the runtime file authoritative.
        if let bundledDefaultURL {
            for legacyName in ["employers.legacy-v1.json", "employers.legacy-44.json", "employers.legacy-45.json"] {
                let legacyURL = bundledDefaultURL.deletingLastPathComponent().appendingPathComponent(legacyName)
                if fileManager.fileExists(atPath: legacyURL.path) {
                    let legacy = try JSONDecoder().decode(EmployerConfiguration.self, from: Data(contentsOf: legacyURL)).validated()
                    if current == legacy {
                        let data = try Data(contentsOf: bundledDefaultURL)
                        let updated = try JSONDecoder().decode(EmployerConfiguration.self, from: data).validated()
                        if updated != current {
                            try data.write(to: fileURL, options: .atomic)
                        }
                        return updated
                    }
                }
            }
        }
        return current
    }
}
