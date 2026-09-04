import Foundation

struct AreaDirectorySnapshot: Sendable {
    let index: AreaDirectoryIndex
    let warning: String?
}

struct AreaDirectoryIndex: Sendable {
    let root: HHAreaNode
    private let nodes: [String: HHAreaNode]
    private let parents: [String: String]

    init(root: HHAreaNode) throws {
        guard root.id == "113" else { throw AreaDirectoryError.invalidRoot }
        var collected: [String: HHAreaNode] = [:]
        var parentMap: [String: String] = [:]
        var stack = Set<String>()

        func visit(_ node: HHAreaNode, parent: String?) throws {
            guard stack.insert(node.id).inserted else { throw AreaDirectoryError.cycle(node.id) }
            guard collected[node.id] == nil else { throw AreaDirectoryError.duplicateID(node.id) }
            collected[node.id] = node
            if let parent { parentMap[node.id] = parent }
            for child in node.areas { try visit(child, parent: node.id) }
            stack.remove(node.id)
        }
        try visit(root, parent: nil)
        self.root = root
        nodes = collected
        parents = parentMap
    }

    var subjects: [HHAreaNode] { root.areas }
    func children(of id: String) -> [HHAreaNode] { nodes[id]?.areas ?? [] }

    func location(for summary: HHVacancySummary) -> VacancyLocation {
        let remoteIDs = Set(["REMOTE", "remote"])
        if summary.workFormat?.contains(where: { remoteIDs.contains($0.id ?? "") }) == true
            || summary.schedule?.id == "remote" {
            return .remote
        }
        let locations: [HHArea]
        if let areas = summary.areas, !areas.isEmpty {
            locations = areas
        } else {
            locations = summary.area.map { [$0] } ?? []
        }
        guard locations.count == 1, let areaID = locations[0].id, areaID != root.id,
              let subject = subjectAncestor(for: areaID) else { return .unknown }
        if areaID == subject.id {
            let federalCity = areaID == "1" || areaID == "2"
            return .subject(id: subject.id, name: subject.name, cityID: federalCity ? areaID : nil, cityName: federalCity ? subject.name : nil)
        }
        return .subject(id: subject.id, name: subject.name, cityID: areaID, cityName: locations[0].name)
    }

    private func subjectAncestor(for areaID: String) -> HHAreaNode? {
        var current = areaID
        while let parent = parents[current] {
            if parent == root.id { return nodes[current] }
            current = parent
        }
        return nil
    }
}

enum AreaDirectoryError: LocalizedError, Equatable {
    case invalidRoot
    case unsupportedVersion(Int)
    case duplicateID(String)
    case cycle(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidRoot: return "Справочник регионов hh.ru не содержит корень России 113."
        case .unsupportedVersion(let value): return "Версия кэша регионов \(value) не поддерживается."
        case .duplicateID(let id): return "В справочнике регионов повторяется ID \(id)."
        case .cycle(let id): return "В справочнике регионов обнаружен цикл у ID \(id)."
        case .unavailable: return "Справочник регионов недоступен и локальный кэш отсутствует."
        }
    }
}

private struct AreaDirectoryCache: Codable {
    static let currentVersion = 1
    let version: Int
    let fetchedAt: Date
    let root: HHAreaNode
}

struct AreaDirectoryStore: @unchecked Sendable {
    static let defaultTTL: TimeInterval = 7 * 24 * 60 * 60
    private let configuredFileURL: URL?
    private let fileManager: FileManager
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    init(fileURL: URL? = nil, fileManager: FileManager = .default, ttl: TimeInterval = defaultTTL, now: @escaping @Sendable () -> Date = { Date() }) {
        configuredFileURL = fileURL
        self.fileManager = fileManager
        self.ttl = ttl
        self.now = now
    }

    var fileURL: URL {
        if let configuredFileURL { return configuredFileURL }
        return ApplicationSupportLocation.fileURL(named: "areas.json", fileManager: fileManager)
    }

    func load(using client: any HHVacancyAPIClient) async throws -> AreaDirectorySnapshot {
        let cached = try? readCache()
        let cachedIndex = cached.flatMap { try? AreaDirectoryIndex(root: $0.root) }
        if let cached, let cachedIndex,
           now().timeIntervalSince(cached.fetchedAt) >= 0,
           now().timeIntervalSince(cached.fetchedAt) < ttl {
            return AreaDirectorySnapshot(index: cachedIndex, warning: nil)
        }
        do {
            let root = try await client.areaTree()
            try Task.checkCancellation()
            let index = try AreaDirectoryIndex(root: root)
            do {
                try write(root: root)
            } catch {
                return AreaDirectorySnapshot(
                    index: index,
                    warning: "Не удалось сохранить кэш регионов: \(error.localizedDescription)"
                )
            }
            return AreaDirectorySnapshot(index: index, warning: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let cachedIndex {
                return AreaDirectorySnapshot(index: cachedIndex, warning: "Используется устаревший кэш регионов: \(error.localizedDescription)")
            }
            throw AreaDirectoryError.unavailable
        }
    }

    private func readCache() throws -> AreaDirectoryCache {
        let cache = try JSONDecoder.areaDecoder.decode(AreaDirectoryCache.self, from: Data(contentsOf: fileURL))
        guard cache.version == AreaDirectoryCache.currentVersion else { throw AreaDirectoryError.unsupportedVersion(cache.version) }
        return cache
    }

    private func write(root: HHAreaNode) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cache = AreaDirectoryCache(version: AreaDirectoryCache.currentVersion, fetchedAt: now(), root: root)
        try JSONEncoder.areaEncoder.encode(cache).write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var areaEncoder: JSONEncoder {
        let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; value.outputFormatting = [.prettyPrinted, .sortedKeys]; return value
    }
}
private extension JSONDecoder {
    static var areaDecoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}
