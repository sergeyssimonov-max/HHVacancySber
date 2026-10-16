//
//  HHModels.swift
//  HHVacancySber
//
//  Created by Codex on 05.07.2026.
//

import Foundation

// One parsing policy for HH publication timestamps in lists and reports.
// Each owner keeps its own formatters; mutable Foundation objects are not shared across actors.
struct HHPublicationDateParser {
    private let standard = ISO8601DateFormatter()
    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return standard.date(from: value) ?? fractional.date(from: value)
    }
}

struct HHVacancySearchResponse: Decodable {
    let items: [HHVacancySummary]
    let found: Int
    let pages: Int
    let page: Int
    let perPage: Int
    let rejectedItemCount: Int

    init(items: [HHVacancySummary], found: Int, pages: Int, page: Int, perPage: Int, rejectedItemCount: Int = 0) {
        self.items = items
        self.found = found
        self.pages = pages
        self.page = page
        self.perPage = perPage
        self.rejectedItemCount = rejectedItemCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try values.decode([VacancyItem].self, forKey: .items)
        items = decoded.compactMap(\.value)
        rejectedItemCount = decoded.count - items.count
        found = try values.decode(Int.self, forKey: .found)
        pages = try values.decode(Int.self, forKey: .pages)
        page = try values.decode(Int.self, forKey: .page)
        perPage = try values.decode(Int.self, forKey: .perPage)
    }

    // Each wrapper consumes exactly one JSON element even if its vacancy fails
    // to decode. The page envelope remains strict, and `found` retains shortfalls.
    private struct VacancyItem: Decodable {
        let value: HHVacancySummary?
        init(from decoder: Decoder) throws {
            value = try? HHVacancySummary(from: decoder)
        }
    }

    enum CodingKeys: String, CodingKey {
        case items
        case found
        case pages
        case page
        case perPage = "per_page"
    }
}

struct HHVacancySummary: Codable, Identifiable {
    let id: String
    let name: String
    let employer: HHEmployer?
    let salary: HHSalary?
    let area: HHArea?
    let alternateURL: String?
    let url: String?
    let snippet: HHVacancySnippet?
    let department: HHNamedItem?
    let schedule: HHNamedItem?
    let workFormat: [HHNamedItem]?
    let publishedAt: String?
    let areas: [HHArea]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case employer
        case salary
        case area
        case alternateURL = "alternate_url"
        case url
        case snippet
        case department
        case schedule
        case workFormat = "work_format"
        case publishedAt = "published_at"
        case areas
    }

    init(
        id: String,
        name: String,
        employer: HHEmployer?,
        salary: HHSalary?,
        area: HHArea?,
        alternateURL: String?,
        url: String?,
        snippet: HHVacancySnippet?,
        department: HHNamedItem? = nil,
        schedule: HHNamedItem? = nil,
        workFormat: [HHNamedItem]? = nil,
        publishedAt: String? = nil,
        areas: [HHArea]? = nil
    ) {
        self.id = id
        self.name = name
        self.employer = employer
        self.salary = salary
        self.area = area
        self.alternateURL = alternateURL
        self.url = url
        self.snippet = snippet
        self.department = department
        self.schedule = schedule
        self.workFormat = workFormat
        self.publishedAt = publishedAt
        self.areas = areas
    }
}

struct HHNamedItem: Codable, Equatable {
    let id: String?
    let name: String?

    init(id: String? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

struct HHVacancyAddress: Codable, Equatable {
    let city: String?
    let street: String?
    let building: String?
    let description: String?
    let lat: Double?
    let lng: Double?
    let metroStations: [HHMetroStation]?

    enum CodingKeys: String, CodingKey {
        case city, street, building, description, lat, lng
        case metroStations = "metro_stations"
    }
}

struct HHMetroStation: Codable, Equatable {
    let stationName: String?
    let lineName: String?

    enum CodingKeys: String, CodingKey {
        case stationName = "station_name"
        case lineName = "line_name"
    }
}

struct HHVacancyContacts: Codable, Equatable {
    let name: String?
    let phones: [HHVacancyPhone]?
}

struct HHVacancyPhone: Codable, Equatable {
    let country: String?
    let city: String?
    let number: String?
    let formatted: String?
    let comment: String?

    var displayText: String? {
        if let formatted = formatted?.nilIfBlank { return formatted }
        let components = [country, city, number].compactMap { $0?.nilIfBlank }
        return components.isEmpty ? nil : "+" + components.joined()
    }
}

struct HHVacancyLanguage: Codable, Equatable {
    let id: String?
    let name: String?
    let level: HHNamedItem?
}

struct HHVacancyTest: Codable, Equatable {
    let id: String?
    let required: Bool?
}

struct HHVacancyVideo: Codable, Equatable {
    let videoURL: String?
    let video: HHVacancyVideoLink?

    enum CodingKeys: String, CodingKey {
        case videoURL = "video_url"
        case video
    }
}

struct HHVacancyVideoLink: Codable, Equatable {
    let url: String?
}

struct HHInsiderInterview: Codable, Equatable {
    let url: String?
}

struct HHVacancyDetails: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let employer: HHEmployer?
    let area: HHArea?
    let salary: HHSalary?
    let salaryRange: HHSalaryRange?
    let alternateURL: String?
    let applyAlternateURL: String?
    let responseURL: String?
    let description: String?
    let brandedDescription: String?
    let archived: Bool?
    let closedForApplicants: Bool?
    let address: HHVacancyAddress?
    let experience: HHNamedItem?
    let employment: HHNamedItem?
    let employmentForm: HHNamedItem?
    let schedule: HHNamedItem?
    let workFormat: [HHNamedItem]?
    let workScheduleByDays: [HHNamedItem]?
    let workingDays: [HHNamedItem]?
    let workingHours: [HHNamedItem]?
    let workingTimeIntervals: [HHNamedItem]?
    let workingTimeModes: [HHNamedItem]?
    let flyInFlyOutDuration: [HHNamedItem]?
    let internship: Bool?
    let nightShifts: Bool?
    let keySkills: [HHNamedItem]?
    let professionalRoles: [HHNamedItem]?
    let languages: [HHVacancyLanguage]?
    let contacts: HHVacancyContacts?
    let publishedAt: String?
    let initialCreatedAt: String?
    let createdAt: String?
    let expiresAt: String?
    let archivedAt: String?
    let driverLicenseTypes: [HHNamedItem]?
    let civilLawContracts: [HHNamedItem]?
    let acceptIncompleteResumes: Bool?
    let acceptLaborContract: Bool?
    let acceptTemporary: Bool?
    let acceptHandicapped: Bool?
    let acceptKids: Bool?
    let ageRestriction: HHNamedItem?
    let inclusivenessDescription: String?
    let inclusivenessTypes: [String]?
    let responseLetterRequired: Bool?
    let hasTest: Bool?
    let test: HHVacancyTest?
    let allowMessages: Bool?
    let code: String?
    let department: HHNamedItem?
    let vacancyType: HHNamedItem?
    let insiderInterview: HHInsiderInterview?
    let videoVacancy: HHVacancyVideo?

    enum CodingKeys: String, CodingKey {
        case id, name, employer, area, salary, description, archived, address, experience
        case employment, schedule, internship, contacts, languages, code, department, test
        case salaryRange = "salary_range"
        case alternateURL = "alternate_url"
        case applyAlternateURL = "apply_alternate_url"
        case responseURL = "response_url"
        case brandedDescription = "branded_description"
        case closedForApplicants = "closed_for_applicants"
        case employmentForm = "employment_form"
        case workFormat = "work_format"
        case workScheduleByDays = "work_schedule_by_days"
        case workingDays = "working_days"
        case workingHours = "working_hours"
        case workingTimeIntervals = "working_time_intervals"
        case workingTimeModes = "working_time_modes"
        case flyInFlyOutDuration = "fly_in_fly_out_duration"
        case nightShifts = "night_shifts"
        case keySkills = "key_skills"
        case professionalRoles = "professional_roles"
        case publishedAt = "published_at"
        case initialCreatedAt = "initial_created_at"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case archivedAt = "archived_at"
        case driverLicenseTypes = "driver_license_types"
        case civilLawContracts = "civil_law_contracts"
        case acceptIncompleteResumes = "accept_incomplete_resumes"
        case acceptLaborContract = "accept_labor_contract"
        case acceptTemporary = "accept_temporary"
        case acceptHandicapped = "accept_handicapped"
        case acceptKids = "accept_kids"
        case ageRestriction = "age_restriction"
        case inclusivenessDescription = "inclusiveness_description"
        case inclusivenessTypes = "inclusiveness_types"
        case responseLetterRequired = "response_letter_required"
        case hasTest = "has_test"
        case allowMessages = "allow_messages"
        case vacancyType = "type"
        case insiderInterview = "insider_interview"
        case videoVacancy = "video_vacancy"
    }

    init(
        id: String,
        name: String,
        employer: HHEmployer?,
        area: HHArea?,
        salary: HHSalary?,
        alternateURL: String?,
        description: String?,
        archived: Bool? = nil,
        salaryRange: HHSalaryRange? = nil,
        applyAlternateURL: String? = nil,
        responseURL: String? = nil,
        brandedDescription: String? = nil,
        closedForApplicants: Bool? = nil,
        address: HHVacancyAddress? = nil,
        experience: HHNamedItem? = nil,
        employment: HHNamedItem? = nil,
        employmentForm: HHNamedItem? = nil,
        schedule: HHNamedItem? = nil,
        workFormat: [HHNamedItem]? = nil,
        workScheduleByDays: [HHNamedItem]? = nil,
        workingDays: [HHNamedItem]? = nil,
        workingHours: [HHNamedItem]? = nil,
        workingTimeIntervals: [HHNamedItem]? = nil,
        workingTimeModes: [HHNamedItem]? = nil,
        flyInFlyOutDuration: [HHNamedItem]? = nil,
        internship: Bool? = nil,
        nightShifts: Bool? = nil,
        keySkills: [HHNamedItem]? = nil,
        professionalRoles: [HHNamedItem]? = nil,
        languages: [HHVacancyLanguage]? = nil,
        contacts: HHVacancyContacts? = nil,
        publishedAt: String? = nil,
        initialCreatedAt: String? = nil,
        createdAt: String? = nil,
        expiresAt: String? = nil,
        archivedAt: String? = nil,
        driverLicenseTypes: [HHNamedItem]? = nil,
        civilLawContracts: [HHNamedItem]? = nil,
        acceptIncompleteResumes: Bool? = nil,
        acceptLaborContract: Bool? = nil,
        acceptTemporary: Bool? = nil,
        acceptHandicapped: Bool? = nil,
        acceptKids: Bool? = nil,
        ageRestriction: HHNamedItem? = nil,
        inclusivenessDescription: String? = nil,
        inclusivenessTypes: [String]? = nil,
        responseLetterRequired: Bool? = nil,
        hasTest: Bool? = nil,
        test: HHVacancyTest? = nil,
        allowMessages: Bool? = nil,
        code: String? = nil,
        department: HHNamedItem? = nil,
        vacancyType: HHNamedItem? = nil,
        insiderInterview: HHInsiderInterview? = nil,
        videoVacancy: HHVacancyVideo? = nil
    ) {
        self.id = id
        self.name = name
        self.employer = employer
        self.area = area
        self.salary = salary
        self.salaryRange = salaryRange
        self.alternateURL = alternateURL
        self.applyAlternateURL = applyAlternateURL
        self.responseURL = responseURL
        self.description = description
        self.brandedDescription = brandedDescription
        self.archived = archived
        self.closedForApplicants = closedForApplicants
        self.address = address
        self.experience = experience
        self.employment = employment
        self.employmentForm = employmentForm
        self.schedule = schedule
        self.workFormat = workFormat
        self.workScheduleByDays = workScheduleByDays
        self.workingDays = workingDays
        self.workingHours = workingHours
        self.workingTimeIntervals = workingTimeIntervals
        self.workingTimeModes = workingTimeModes
        self.flyInFlyOutDuration = flyInFlyOutDuration
        self.internship = internship
        self.nightShifts = nightShifts
        self.keySkills = keySkills
        self.professionalRoles = professionalRoles
        self.languages = languages
        self.contacts = contacts
        self.publishedAt = publishedAt
        self.initialCreatedAt = initialCreatedAt
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.archivedAt = archivedAt
        self.driverLicenseTypes = driverLicenseTypes
        self.civilLawContracts = civilLawContracts
        self.acceptIncompleteResumes = acceptIncompleteResumes
        self.acceptLaborContract = acceptLaborContract
        self.acceptTemporary = acceptTemporary
        self.acceptHandicapped = acceptHandicapped
        self.acceptKids = acceptKids
        self.ageRestriction = ageRestriction
        self.inclusivenessDescription = inclusivenessDescription
        self.inclusivenessTypes = inclusivenessTypes
        self.responseLetterRequired = responseLetterRequired
        self.hasTest = hasTest
        self.test = test
        self.allowMessages = allowMessages
        self.code = code
        self.department = department
        self.vacancyType = vacancyType
        self.insiderInterview = insiderInterview
        self.videoVacancy = videoVacancy
    }

}

struct HHEmployer: Codable, Equatable {
    let id: String?
    let name: String?
    let alternateURL: String?
    let trusted: Bool?
    let accreditedITEmployer: Bool?
    let rating: HHEmployerRating?

    enum CodingKeys: String, CodingKey {
        case id, name, trusted
        case alternateURL = "alternate_url"
        case accreditedITEmployer = "accredited_it_employer"
        case rating = "employer_rating"
    }

    init(
        name: String?,
        id: String? = nil,
        alternateURL: String? = nil,
        trusted: Bool? = nil,
        accreditedITEmployer: Bool? = nil,
        rating: HHEmployerRating? = nil
    ) {
        self.id = id
        self.name = name
        self.alternateURL = alternateURL
        self.trusted = trusted
        self.accreditedITEmployer = accreditedITEmployer
        self.rating = rating
    }
}

struct HHEmployerRating: Codable, Equatable {
    let totalRating: String?
    let reviewsCount: Int?

    enum CodingKeys: String, CodingKey {
        case totalRating = "total_rating"
        case reviewsCount = "reviews_count"
    }
}

struct HHArea: Codable, Equatable {
    let id: String?
    let name: String?
    let url: String?

    init(id: String?, name: String?, url: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
    }
}

struct HHAreaNode: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let areas: [HHAreaNode]

    init(id: String, name: String, areas: [HHAreaNode] = []) {
        self.id = id
        self.name = name
        self.areas = areas
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        areas = try values.decodeIfPresent([HHAreaNode].self, forKey: .areas) ?? []
    }
}

struct HHVacancyDictionaries: Decodable, Sendable {
    let experience: [HHNamedItem]
    let workFormat: [HHNamedItem]
    let schedule: [HHNamedItem]

    init(experience: [HHNamedItem], workFormat: [HHNamedItem], schedule: [HHNamedItem]) {
        self.experience = experience
        self.workFormat = workFormat
        self.schedule = schedule
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        experience = try values.decode([HHNamedItem].self, forKey: .experience)
        workFormat = try values.decodeIfPresent([HHNamedItem].self, forKey: .workFormat) ?? []
        schedule = try values.decodeIfPresent([HHNamedItem].self, forKey: .schedule) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case experience, schedule
        case workFormat = "work_format"
    }
}

enum VacancyLocationKind: String, Codable, Equatable, Sendable {
    case subject
    case remote
    case unknown
}

struct VacancyLocation: Codable, Equatable, Sendable {
    let kind: VacancyLocationKind
    let subjectID: String?
    let subjectName: String?
    let cityID: String?
    let cityName: String?

    static let remote = VacancyLocation(
        kind: .remote,
        subjectID: nil,
        subjectName: nil,
        cityID: nil,
        cityName: nil
    )
    static let unknown = VacancyLocation(
        kind: .unknown,
        subjectID: nil,
        subjectName: nil,
        cityID: nil,
        cityName: nil
    )

    static func subject(id: String, name: String, cityID: String?, cityName: String?) -> VacancyLocation {
        VacancyLocation(
            kind: .subject,
            subjectID: id,
            subjectName: name,
            cityID: cityID,
            cityName: cityName
        )
    }

    var displayName: String {
        switch kind {
        case .remote:
            return "Удалённо"
        case .unknown:
            return "Регион не определён"
        case .subject:
            if let cityName = cityName?.nilIfBlank, cityName != subjectName {
                return "\(cityName), \(subjectName ?? "Регион не определён")"
            }
            return subjectName?.nilIfBlank ?? "Регион не определён"
        }
    }

    var filterID: String {
        switch kind {
        case .remote: return "remote"
        case .unknown: return "unknown"
        case .subject: return "subject:\(subjectID ?? "unknown")"
        }
    }
}

struct HHSalary: Codable, Equatable {
    let from: Int?
    let to: Int?
    let currency: String?
    let gross: Bool?

    var displayText: String? {
        let fromText = from.map(Self.formatAmount)
        let toText = to.map(Self.formatAmount)
        let currencyText = currencyDisplayName

        let amount: String
        switch (fromText, toText) {
        case let (from?, to?):
            amount = "\(from)-\(to)"
        case let (from?, nil):
            amount = "от \(from)"
        case let (nil, to?):
            amount = "до \(to)"
        case (nil, nil):
            return nil
        }

        if let gross {
            return "\(amount) \(currencyText), \(gross ? "до вычета" : "на руки")"
        }

        return "\(amount) \(currencyText)"
    }

    private var currencyDisplayName: String {
        switch currency {
        case "RUR", "RUB":
            return "руб."
        case let value?:
            return value
        case nil:
            return ""
        }
    }

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter
    }()
    private static let amountFormatterLock = NSLock()

    private static func formatAmount(_ amount: Int) -> String {
        amountFormatterLock.lock()
        defer { amountFormatterLock.unlock() }
        return amountFormatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

struct HHSalaryRange: Codable, Equatable {
    let from: Int?
    let to: Int?
    let currency: String?
    let gross: Bool?
    let mode: HHNamedItem?
    let frequency: HHNamedItem?

    init(
        from: Int? = nil,
        to: Int? = nil,
        currency: String? = nil,
        gross: Bool? = nil,
        mode: HHNamedItem? = nil,
        frequency: HHNamedItem? = nil
    ) {
        self.from = from
        self.to = to
        self.currency = currency
        self.gross = gross
        self.mode = mode
        self.frequency = frequency
    }

    var displayText: String? {
        let legacy = HHSalary(from: from, to: to, currency: currency, gross: gross)
        let suffix = [mode?.name?.nilIfBlank, frequency?.name?.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: ", ")
        guard let amount = legacy.displayText else { return suffix.nilIfBlank }
        return suffix.isEmpty ? amount : "\(amount), \(suffix)"
    }
}

struct HHVacancySnippet: Codable, Equatable {
    let requirement: String?
    let responsibility: String?

    var plainText: String {
        [requirement, responsibility]
            .compactMap { $0?.readableHTMLText.nilIfBlank }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct VacancySearchResult: Identifiable {
    let id: String
    let summary: HHVacancySummary
    let details: HHVacancyDetails
    let location: VacancyLocation
    let isDetailLoaded: Bool
    let isDetailLoading: Bool
    let detailErrorMessage: String?
    let persistedSalaryText: String?
    let isArchived: Bool
    let archiveCheckedAt: Date?
    let exportDataNotice: String?
    let isTechnologyRelated: Bool
    let isInformationSecurityRelated: Bool

    var field: VacancyField {
        isInformationSecurityRelated ? .informationSecurity : (isTechnologyRelated ? .technology : .general)
    }

    init(
        id: String,
        summary: HHVacancySummary,
        details: HHVacancyDetails,
        location: VacancyLocation = .unknown,
        isDetailLoaded: Bool = false,
        isDetailLoading: Bool = false,
        detailErrorMessage: String? = nil,
        persistedSalaryText: String? = nil,
        isArchived: Bool? = nil,
        archiveCheckedAt: Date? = nil,
        exportDataNotice: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.details = details
        self.location = location
        self.isDetailLoaded = isDetailLoaded
        self.isDetailLoading = isDetailLoading
        self.detailErrorMessage = detailErrorMessage
        self.persistedSalaryText = persistedSalaryText
        self.isArchived = isArchived ?? details.archived ?? false
        self.archiveCheckedAt = archiveCheckedAt
        self.exportDataNotice = exportDataNotice
        let roles = (details.professionalRoles ?? []).compactMap(\.name)
        let context = [summary.snippet?.plainText, details.description?.readableHTMLText]
            .compactMap { $0 }.joined(separator: "\n")
        self.isInformationSecurityRelated = VacancyInformationSecurityClassifier.matches(
            title: details.name, roles: roles, context: context
        )
        self.isTechnologyRelated = isInformationSecurityRelated || VacancyTechnologyClassifier.matches(
            title: details.name, roles: roles, context: context
        )
    }

    init(summary: HHVacancySummary, location: VacancyLocation) {
        self.init(
            id: summary.id, summary: summary,
            details: HHVacancyDetails(
                id: summary.id, name: summary.name, employer: summary.employer,
                area: summary.area, salary: summary.salary, alternateURL: summary.alternateURL,
                description: nil, schedule: summary.schedule, workFormat: summary.workFormat,
                department: summary.department
            ),
            location: location
        )
    }

    var name: String {
        details.name
    }

    var employerName: String {
        details.employer?.name?.nilIfBlank ?? summary.employer?.name?.nilIfBlank ?? "Работодатель не указан"
    }

    var employerID: String? {
        details.employer?.id?.nilIfBlank ?? summary.employer?.id?.nilIfBlank
    }

    var departmentName: String? {
        details.department?.name?.nilIfBlank ?? summary.department?.name?.nilIfBlank
    }

    var publishedAt: String? {
        summary.publishedAt ?? details.publishedAt
    }

    var areaName: String {
        location.displayName
    }

    var salaryText: String? {
        details.salaryRange?.displayText ?? details.salary?.displayText
            ?? summary.salary?.displayText ?? persistedSalaryText
    }

    var alternateURL: String? {
        details.alternateURL?.nilIfBlank ?? summary.alternateURL?.nilIfBlank
    }

    var htmlDescription: String {
        details.description?.nilIfBlank ?? ""
    }

    var plainTextDescription: String? {
        details.description?.readableHTMLText.nilIfBlank
    }

    var hasFullDescription: Bool {
        details.description?.nilIfBlank != nil
    }

    func updatingArchiveStatus(_ archived: Bool, checkedAt: Date) -> VacancySearchResult {
        VacancySearchResult(
            id: id, summary: summary, details: details, location: location,
            isDetailLoaded: isDetailLoaded, isDetailLoading: isDetailLoading,
            detailErrorMessage: detailErrorMessage, persistedSalaryText: persistedSalaryText,
            isArchived: archived, archiveCheckedAt: checkedAt, exportDataNotice: exportDataNotice
        )
    }

    func updatingDetailState(
        isLoading: Bool,
        errorMessage: String?
    ) -> VacancySearchResult {
        VacancySearchResult(
            id: id,
            summary: summary,
            details: details,
            location: location,
            isDetailLoaded: isDetailLoaded,
            isDetailLoading: isLoading,
            detailErrorMessage: errorMessage,
            persistedSalaryText: persistedSalaryText,
            isArchived: isArchived,
            archiveCheckedAt: archiveCheckedAt,
            exportDataNotice: exportDataNotice
        )
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var readableHTMLText: String {
        // Bound temporary Foundation allocations during bulk vacancy conversion.
        autoreleasepool {
            var value = self
            value = value.replacingOccurrences(
                of: "<(script|style)\\b[^>]*>[\\s\\S]*?</\\1>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            value = value.replacingOccurrences(of: "<\\s*br\\s*/?\\s*>", with: "\n", options: [.regularExpression, .caseInsensitive])
            value = value.replacingOccurrences(of: "<\\s*li\\b[^>]*>", with: "\n• ", options: [.regularExpression, .caseInsensitive])
            value = value.replacingOccurrences(of: "</\\s*(p|div|h[1-6]|li|ul|ol|blockquote)\\s*>", with: "\n", options: [.regularExpression, .caseInsensitive])
            value = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            value = value
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
            value = value.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            value = value.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            value = value.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

}

/// Local, deterministic classification. Employer names and generic office skills are
/// deliberately excluded. Broad job names are accepted only in titles/role names;
/// descriptions require an explicit technical field, not just “аналитика” or “IT”.
enum VacancyTechnologyClassifier {
    static func matches(title: String, roles: [String] = [], context: String = "") -> Bool {
        matches(rolePattern, in: ([title] + roles).joined(separator: " "))
            || matches(fieldPattern, in: ([title] + roles + [context]).joined(separator: " "))
    }

    private static func matches(_ pattern: NSRegularExpression, in text: String) -> Bool {
        let normalized = text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "‑", with: "-")
        return pattern.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) != nil
    }

    private static func expression(_ alternatives: [String]) -> NSRegularExpression {
        // Unicode boundaries prevent short acronyms matching inside unrelated words.
        try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:" + alternatives.joined(separator: "|") + ")(?![\\p{L}\\p{N}])")
    }

    private static let rolePattern = expression([
        #"(?:it|ит|ict|икт|интернет|ai|ии|bi|qa|qc|ml|1с|1c|erp|crm|bpm|sql|dba|cto|cio|cdo)"#,
        #"(?:разработчик|программист|тестировщик|аналитик|дата[ -]?саентист|дата[ -]?инженер|системотехник|биоинформатик)[а-я]*"#,
        #"(?:архитектор[а-я]* (?:решени[а-я]*|данных|по|программ[а-я]*|информационн[а-я]*|предприяти[а-я]*)|solution[s]? architect|enterprise architect|data architect)"#,
        #"(?:developer|programmer|tester|analyst|analytics|product[ -]+(?:manager|owner|designer)|scrum[ -]+master|agile[ -]+coach)"#,
        #"(?:управлен[а-я]*|менеджер[а-я]*|владелец|руководител[а-я]*|дизайнер[а-я]*) (?:\S+ ){0,2}продукт[а-я]*"#,
        #"(?:техническ[а-я]+ (?:поддержк[а-я]*|писател[а-я]*)|системн[а-я]+ администратор[а-я]*|сетев[а-я]+ инженер[а-я]*)"#,
        #"(?:java|python|javascript|typescript|kotlin|swift|golang|scala|c\+\+|c#|[.]net|react|angular|vue|unity|unreal)"#
    ])

    private static let fieldPattern = expression([
        #"(?:информационн[а-я]+ (?:технолог[а-я]*|систем[а-я]*|безопасност[а-я]*|и коммуникационн[а-я]+ технолог[а-я]*)|кибербезопасност[а-я]*|телеком[а-я]*)"#,
        #"(?:frontend|backend|full[ -]?stack|front[ -]?end|back[ -]?end|devops|sre|mlops|llmops|dataops|finops|low[ -]?code|no[ -]?code|rpa|rag|llm|etl|elt|olap|lakehouse|hadoop|spark|kubernetes|[аa]нтифрод[а-я]*|пентест[а-я]*)"#,
        #"(?:веб|web|мобильн[а-я]+|программного обеспечения|игр|1с|1c)[ -]*разработ[а-я]*|разработ[а-я]* (?:программ[а-я]*|по|игр|на 1[сc]|мобильн[а-я]+|веб[а-я]*)"#,
        #"(?:системн[а-я]+ программирован[а-я]*|встраиваем[а-я]+ систем[а-я]*|embedded|software|firmware|game[ -]?(?:design|development))"#,
        #"(?:архитектур[а-я]* (?:программ[а-я]*|решени[а-я]*|данных|предприяти[а-я]*)|корпоративн[а-я]+ архитектур[а-я]*|системн[а-я]+ интеграц[а-я]*|(?:внедрен[а-я]*|сопровожден[а-я]*) (?:информационн[а-я]+ систем[а-я]*|программн[а-я]+ обеспечен[а-я]*))"#,
        #"(?:(?:ручн[а-я]+|автоматизированн[а-я]+|нагрузочн[а-я]+) тестирован[а-я]*|тестирован[а-я]* (?:по|программ[а-я]*)|quality assurance)"#,
        #"(?:защит[а-я]* (?:информац[а-я]*|персональн[а-я]+ данных)|(?:безопасност[а-я]*|конфиденциальност[а-я]*) данных)"#,
        #"(?:(?:платформенн[а-я]+|сетев[а-я]+|системн[а-я]+) инженери[а-я]*|(?:системн[а-я]+|сетев[а-я]+) администрирован[а-я]*|администрирован[а-я]* (?:баз[а-я]* данных|сервер[а-я]*)|облачн[а-я]+ (?:технолог[а-я]*|инфраструктур[а-я]*)|(?:it|ит)[ -]инфраструктур[а-я]*)"#,
        #"(?:техническ[а-я]+ поддержк[а-я]*|техническ[а-я]+ писатель[а-я]*|technical (?:support|writer)|ux|ui|гейм[ -]?дизайн[а-я]*|дизайн[а-я]* интерфейс[а-я]*|продуктов[а-я]+ дизайн[а-я]*|компьютерн[а-я]+ график[а-я]*)"#,
        #"(?:(?:управлен[а-я]*|менеджмент) (?:it|ит|продукт[а-я]*)|(?:it|ит)[ -](?:проект[а-я]*|менеджмент)|цифров[а-я]+ трансформац[а-я]*|автоматизац[а-я]* бизнес[ -]процесс[а-я]*|роботизац[а-я]* процесс[а-я]*|методолог[а-я]* разработ[а-я]*)"#,
        #"(?:(?:системн[а-я]+|бизнес|количественн[а-я]+) [аa]нализ[а-я]*|бизнес-анализ[а-я]*|(?:операционн[а-я]+|продуктов[а-я]+|финансов[а-я]+|hr|риск|предиктивн[а-я]+|самообслуживаем[а-я]+)[ -]аналитик[а-я]*|[аa]/[вb][ -]тест[а-я]*|анализ[а-я]* временн[а-я]+ ряд[а-я]*|process mining|бизнес[ -]интеллект[а-я]*)"#,
        #"(?:(?:работ[а-я]*|сбор[а-я]*|подготовк[а-я]*|очистк[а-я]*|обработк[а-я]*|анализ[а-я]*|аналитик[а-я]*|исследован[а-я]*|визуализац[а-я]*|моделирован[а-я]*|инженери[а-я]*|интеграц[а-я]*|миграц[а-я]*|хранилищ[а-я]*|витрин[а-я]*|озер[а-я]*|платформ[а-я]*|качеств[а-я]*|управлен[а-я]*|каталог[а-я]*|происхожден[а-я]*|наблюдаемост[а-я]*|стратеги[а-я]*|разметк[а-я]*|аннотирован[а-я]*) (?:с )?данны[а-я]*|(?:больш[а-я]*|неструктурированн[а-я]*|полуструктурированн[а-я]*|графов[а-я]*|синтетическ[а-я]*) данны[а-я]*)"#,
        #"(?:потоков[а-я]+ обработк[а-я]* данных|контрол[а-я]* качеств[а-я]* \(qa\)|отчетност[а-я]* и дашборд[а-я]*)"#,
        #"(?:data (?:science|scientist|engineer[a-z]*|analyst|analytics|governance|quality|warehouse|lake|platform|mining)|big data|business intelligence|дашборд[а-я]*|dashboard[a-z]*|аналитическ[а-я]+ (?:систем[а-я]*|инженери[а-я]*)|мастер[ -]данны[а-я]*|нормативно[ -]справочн[а-я]+ информац[а-я]*|метаданны[а-я]*|графов[а-я]+ аналитик[а-я]*|граф[а-я]* знани[а-я]*|инженери[а-я]* признак[а-я]*|наук[а-я]* о данных|статистическ[а-я]+ моделирован[а-я]*)"#,
        #"(?:(?:машинн[а-я]+|глубок[а-я]+) обучен[а-я]*|искусственн[а-я]+ интеллект[а-я]*|больш[а-я]+ языков[а-я]+ модел[а-я]*|векторн[а-я]+ поиск[а-я]*|(?:агентн[а-я]+|мультимодальн[а-я]+|объясним[а-я]+|медицинск[а-я]+) ии|обработк[а-я]* естественн[а-я]+ язык[а-я]*|компьютерн[а-я]+ зрени[а-я]*|видеоаналитик[а-я]*|(?:распознаван[а-я]*|синтез[а-я]*) речи|рекомендательн[а-я]+ систем[а-я]*|поисков[а-я]+ технолог[а-я]*|обучен[а-я]* с подкреплени[а-я]*|промпт[ -]инжиниринг[а-я]*|(?:обучен[а-я]*|оценк[а-я]*|дообучен[а-я]*) модел[а-я]*|(?:этик[а-я]*|регулирован[а-я]*|безопасност[а-я]*) ии)"#,
        #"(?:machine learning|deep learning|artificial intelligence|generative ai|edge ai|agentic ai|nlp|computer vision|reinforcement learning|prompt engineer[a-z]*|ai[ -](?:консалтинг|продукт[а-я]*)|ии[ -]продукт[а-я]*)"#,
        #"(?:интернет[ -]вещей|iot|iiot|робототехник[а-я]*|(?:беспилотн[а-я]+|автономн[а-я]+|геоинформационн[а-я]+|распределенн[а-я]+) систем[а-я]*|биоинформатик[а-я]*|финтех[а-я]*|fintech|(?:высокопроизводительн[а-я]+|научн[а-я]+|квантов[а-я]+) вычислен[а-я]*|блокчейн[а-я]*|blockchain|цифров[а-я]+ двойник[а-я]*|промышленн[а-я]+ автоматизац[а-я]*|умн[а-я]+ (?:производств[а-я]*|город[а-я]*)|hr[ -]?tech|edtech|legaltech|govtech)"#
    ])
}

/// The more specific security field takes visual precedence over general technology.
/// This is derived from vacancy content, so existing offline favorites need no migration.
enum VacancyField {
    case general, technology, informationSecurity
}

/// Explicit security disciplines match anywhere; ambiguous adjacent skills only in
/// job titles/roles. Generic compliance instructions do not turn every employee into IB.
enum VacancyInformationSecurityClassifier {
    static func matches(title: String, roles: [String] = [], context: String = "") -> Bool {
        if ([title] + roles).contains(where: {
            contains(securityPattern, in: normalize($0)) || contains(adjacentRolePattern, in: normalize($0))
        }) { return true }
        return context.components(separatedBy: CharacterSet(charactersIn: ".;!\n")).contains { fragment in
            let text = normalize(fragment)
            guard contains(securityPattern, in: text) else { return false }
            return !contains(boilerplatePattern, in: text) || contains(securityWorkPattern, in: text)
        }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "[‐‑–—−]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func contains(_ pattern: NSRegularExpression, in text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func expression(_ alternatives: [String]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])(?:"# + alternatives.joined(separator: "|") + #")(?![\p{L}\p{N}])"#)
    }

    private static let securityPattern = expression([
        // Core disciplines, Russian and English job names, unambiguous abbreviations.
        #"(?:информационн[а-я]+|компьютерн[а-я]+|облачн[а-я]+|сетев[а-я]+|криптографическ[а-я]+) безопасност[а-я]*"#,
        #"кибер[ -]?(?:безопасност[а-я]*|защит[а-я]*|устойчивост[а-я]*)|киберугроз[а-я]*|госсопка"#,
        #"(?:information|cyber|computer|network|cloud|application|data|software|product|infrastructure|ai|it)[ -]?security|infosec|devsecops|appsec|secops|security (?:engineer|architect|analyst|researcher|officer)|ciso"#,
        #"иб|сзи|скзи|тзи|soc|siem|soar|ndr|edr|xdr|waf|dlp|dcap|iam|pam|ids|ips|ddos|испдн"#,
        #"защит[а-я]* (?:информац[а-я]*|(?:персональн[а-я]+|конфиденциальн[а-я]+) данных|данных|(?:коммерческ[а-я]+|государственн[а-я]+) тайн[а-я]*)"#,
        #"инженерно[ -]техническ[а-я]+ защит[а-я]*|информационно[ -]аналитическ[а-я]+ систем[а-я]* безопасност[а-я]*"#,
        #"(?:систем[а-я]*|средств[а-я]*) (?:криптографическ[а-я]+ )?защит[а-я]* информац[а-я]*"#,
        #"безопасност[а-я]* (?:информационн[а-я]+ технолог[а-я]*|компьютерн[а-я]+ систем[а-я]*|приложени[а-я]*|кода|api|(?:веб|web)[ -]приложени[а-я]*|мобильн[а-я]+ приложени[а-я]*|контейнер[а-я]*|ci/cd|периметр[а-я]*|беспроводн[а-я]+ сет[а-я]*|электронн[а-я]+ почт[а-я]*|данных|баз[а-я]* данных)"#,
        #"безопасн[а-я]+ (?:разработк[а-я]*|sdlc)|secure (?:sdlc|coding|development)|(?:sast|dast|sca)"#,
        // Offensive security, vulnerability research and defensive operations.
        #"(?:оценк[а-я]*|анализ[а-я]*) защищенност[а-я]*|(?:анализ[а-я]*|моделирован[а-я]*) угроз[а-я]*|(?:анализ[а-я]*|управлен[а-я]*|исследован[а-я]*) уязвимост[а-я]*"#,
        #"(?:тестирован[а-я]* на проникновен[а-я]*|пентест[а-я]*|penetration test[a-z]*|pentest[a-z]*|этичн[а-я]+ хакинг[а-я]*|ethical hack[a-z]*|(?:red|blue|purple)[ -]team[a-z]*|bug[ -]bounty|threat[ -]hunting|threat intelligence)"#,
        #"защит[а-я]* (?:веб[ -]приложени[а-я]*|конечн[а-я]+ точ[а-я]*|от (?:ddos|вредоносн[а-я]+ код[а-я]*))|антифишинг[а-я]*|антивирусн[а-я]+ защит[а-я]*"#,
        #"межсетев[а-я]+ экранирован[а-я]*|(?:обнаружен[а-я]*|предотвращен[а-я]*) вторжени[а-я]*|(?:обнаружен[а-я]*|предупрежден[а-я]*) компьютерн[а-я]+ атак[а-я]*"#,
        #"вредоносн[а-я]+ (?:программн[а-я]+ обеспечен[а-я]*|код[а-я]*)|malware|ransomware|фишинг[а-я]*"#,
        #"центр[а-я]* мониторинг[а-я]* и реагирован[а-я]*|цифров[а-я]+ криминалистик[а-я]*|компьютерно[ -]техническ[а-я]+ экспертиз[а-я]*|форензик[а-я]*|(?:digital |computer )?forensics"#,
        // Identity, data protection, cryptography, regulated environments.
        #"управлен[а-я]* (?:идентификаци[а-я]* и доступ[а-я]*|привилегированн[а-я]+ доступ[а-я]*|секрет[а-я]*)|многофакторн[а-я]+ аутентификаци[а-я]*|zero[ -]trust"#,
        #"конфиденциальност[а-я]* данных|предотвращен[а-я]* утеч[а-я]* данных|контрол[а-я]* доступ[а-я]* к баз[а-я]* данных|маскирован[а-я]* данных"#,
        #"криптограф[а-я]*|инфраструктур[а-я]* открыт[а-я]+ ключ[а-я]*|удостоверяющ[а-я]+ центр[а-я]*|стеганограф[а-я]*|pki|hsm"#,
        #"режим[а-я]* секретност[а-я]*|противодействи[а-я]* техническ[а-я]+ разведк[а-я]*|защит[а-я]* от утеч[а-я]* по техническ[а-я]+ канал[а-я]*"#,
        #"безопасност[а-я]* (?:критическ[а-я]+ информационн[а-я]+ инфраструктур[а-я]*|объект[а-я]* кии|государственн[а-я]+ информационн[а-я]+ систем[а-я]*|асу тп)|аттестаци[а-я]* объект[а-я]* информатизаци[а-я]*"#,
        #"фстэк|(?:требован[а-я]*|лицензи[а-я]*) фсб|(?:гост[ -]р[ -])?(?:исо/мэк[ -])27001|(?:гост[ -]р[ -])57580(?:[.][0-9]+)?|iso[ /-]*(?:iec[ /-]*)?27001|pci[ -]dss"#,
        #"антифрод[а-я]*|anti[ -]?fraud|безопасност[а-я]* платеж[а-я]*"#,
        #"безопасност[а-я]* (?:искусственн[а-я]+ интеллект[а-я]*|модел[а-я]* машинн[а-я]+ обучени[а-я]*|ии|интернет[а-я]* вещей|виртуализаци[а-я]*|беспилотн[а-я]+ и автономн[а-я]+ систем[а-я]*|цепоч[а-я]* поставок программн[а-я]+ обеспечени[а-я]*)|защит[а-я]* от атак на ии"#,
        #"управлен[а-я]* конфигураци[а-я]* безопасност[а-я]*"#
    ])

    // These fields were requested too, but are also ordinary IT/legal/business duties.
    // A dedicated job/role name is stronger evidence than a passing mention in a description.
    private static let adjacentRolePattern = expression([
        #"анализ[а-я]* (?:исходн[а-я]+ код[а-я]*|состав[а-я]* программн[а-я]+ обеспечени[а-я]*|сетев[а-я]+ трафик[а-я]*)"#,
        #"динамическ[а-я]+ тестирован[а-я]* приложени[а-я]*|сегментаци[а-я]* сет[а-я]*|песочниц[а-я]*"#,
        #"(?:реагирован[а-я]*|расследован[а-я]*) (?:на )?инцидент[а-я]*|incident response"#,
        #"аутентификаци[а-я]* и авторизаци[а-я]*|классификаци[а-я]* данных|электронн[а-я]+ подпис[а-я]*|управлен[а-я]* ключ[а-я]*"#,
        #"непрерывност[а-я]* деятельност[а-я]*|аварийн[а-я]+ восстановлен[а-я]*|резервн[а-я]+ копирован[а-я]*|disaster recovery|business continuity"#,
        #"соответстви[а-я]* требован[а-я]* банк[а-я]* россии|взаимодействи[а-я]* с регулятор[а-я]*"#
    ])

    private static let boilerplatePattern = expression([
        #"(?:соблюд[а-я]*|выполн[а-я]*|следова[а-я]*) (?:[а-я]+ ){0,4}(?:требован[а-я]*|правил[а-я]*|политик[а-я]*|регламент[а-я]*|норм[а-я]*)"#,
        #"знани[а-я]* основ|согласи[а-я]* на обработк[а-я]*|ознакомлен[а-я]* с политик[а-я]*"#
    ])

    private static let securityWorkPattern = expression([
        #"(?:разработк[а-я]*|внедрен[а-я]*|проектирован[а-я]*|администрирован[а-я]*|аудит[а-я]*|мониторинг[а-я]*|расследован[а-я]*|моделирован[а-я]*|тестирован[а-я]*|управлен[а-я]*|контрол[а-я]*|обеспечени[а-я]*) (?:[а-я]+ ){0,3}(?:иб|информационн[а-я]+ безопасност[а-я]*|сзи|скзи|siem|soc|dlp|waf|уязвимост[а-я]*|угроз[а-я]*|защит[а-я]*)"#
    ])
}
