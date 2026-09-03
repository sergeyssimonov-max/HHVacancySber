import XCTest

final class HHVacancySberUITests: XCTestCase {
    private func launch(scenario: String = "default") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HHVACANCYSBER_UI_TEST_MODE"] = "1"
        app.launchEnvironment["HHVACANCYSBER_UI_TEST_SCENARIO"] = scenario
        app.launch()
        return app
    }

    func testSearchShowsConfiguredVacanciesAndLazyDetails() {
        let app = launch()
        let search = app.buttons["searchVacanciesButton"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["СБЕР"].exists)
        app.buttons["expandVacancy.ui-1"].click()
        XCTAssertTrue(app.staticTexts["Полное описание вакансии."].waitForExistence(timeout: 5))
    }

    func testToolbarUsesOneAlignedRowWithoutExternalFilterLabels() {
        let app = launch()
        let mode = app.descendants(matching: .any)["vacancyListModePicker"]
        let employer = app.descendants(matching: .any)["employerFilterPicker"]
        let region = app.descendants(matching: .any)["regionFilterPicker"]
        let refresh = app.buttons["searchVacanciesButton"]

        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(employer.exists)
        XCTAssertTrue(region.exists)
        XCTAssertTrue(refresh.exists)
        XCTAssertFalse(app.staticTexts["Работодатель"].exists)
        XCTAssertFalse(app.staticTexts["Субъект"].exists)
        XCTAssertEqual(mode.frame.midY, employer.frame.midY, accuracy: 6)
        XCTAssertEqual(employer.frame.midY, region.frame.midY, accuracy: 6)
        XCTAssertEqual(region.frame.midY, refresh.frame.midY, accuracy: 6)
        XCTAssertLessThan(mode.frame.maxX, employer.frame.minX)
        XCTAssertLessThan(employer.frame.maxX, region.frame.minX)
        XCTAssertLessThan(region.frame.maxX, refresh.frame.minX)

        refresh.click()
        let status = app.descendants(matching: .any)["vacancyUpdateStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        XCTAssertLessThan(status.frame.maxX, refresh.frame.minX)
        XCTAssertEqual(status.frame.midY, refresh.frame.midY, accuracy: 6)
    }

    func testEmployerDropdownListsOptionsAndFiltersResults() {
        let app = launch()
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Показано вакансий: 3"].exists)

        choose("СберРешения", from: "employerFilterPicker", in: app)

        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Показано вакансий: 1"].exists)
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-1"].exists)
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-2"].exists)

        choose("Все работодатели", from: "employerFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Показано вакансий: 3"].exists)
    }

    func testRegionDropdownCombinesWithEmployerAndCanShowNoMatches() {
        let app = launch()
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))

        choose("СБЕР", from: "employerFilterPicker", in: app)
        choose("Москва", from: "regionFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].exists)
        XCTAssertTrue(app.staticTexts["Показано вакансий: 1"].exists)
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-2"].exists)
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-3"].exists)

        choose("Свердловская область", from: "regionFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["vacancyTitle.ui-1"].exists)

        choose("Удалённо", from: "regionFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["Вакансий не найдено"].waitForExistence(timeout: 5))
    }

    func testEmptyResponseIsExplicit() {
        let app = launch(scenario: "empty")
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["Вакансий не найдено"].waitForExistence(timeout: 8))
    }

    func testSearchFailureIsExplicit() {
        let app = launch(scenario: "searchError")
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["Не удалось загрузить вакансии"].waitForExistence(timeout: 8))
    }

    private func choose(_ option: String, from pickerIdentifier: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)[pickerIdentifier]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        let item = app.menuItems[option]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing \(option) in \(pickerIdentifier)")
        item.click()
    }
}
