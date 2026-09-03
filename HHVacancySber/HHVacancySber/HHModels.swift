//
//  HHModels.swift
//  HHVacancySber
//
//  Created by Codex on 05.07.2026.
//

import Foundation

struct HHVacancySearchResponse: Decodable {
    let items: [HHVacancySummary]
    let found: Int
    let pages: Int
    let page: Int
    let perPage: Int

    enum CodingKeys: String, CodingKey {
        case items
        case found
        case pages
        case page
        case perPage = "per_page"
    }
}

struct HHVacancySummary: Decodable, Identifiable {
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
}

struct HHVacancyDictionaries: Decodable, Sendable {
    let experience: [HHNamedItem]
    let workFormat: [HHNamedItem]
    let schedule: [HHNamedItem]

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

struct HHVacancySnippet: Decodable, Equatable {
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
