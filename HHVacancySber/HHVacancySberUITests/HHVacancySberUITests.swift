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

    func testStatisticsPDFButtonIsAlignedAndAvailableForFilteredRows() {
        let app = launch()
        let report = app.buttons["exportStatisticsPDFButton"]
        let refresh = app.buttons["searchVacanciesButton"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertFalse(report.isEnabled)
        XCTAssertEqual(report.frame.maxX, refresh.frame.maxX, accuracy: 2)
        refresh.click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        XCTAssertTrue(report.isEnabled)
        XCTAssertEqual(report.frame.maxX, app.buttons["Экспорт в PDF"].firstMatch.frame.maxX, accuracy: 2)
        XCTAssertEqual(report.label, "Статистика в PDF")
        XCTAssertEqual(report.images.count, 0)
        XCTAssertEqual(report.frame.height, 32, accuracy: 2)
        XCTAssertEqual(report.frame.height, app.buttons["Экспорт в PDF"].firstMatch.frame.height, accuracy: 1)
        choose("СБЕР", from: "employerFilterPicker", in: app)
        choose("Москва", from: "regionFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["Показано вакансий: 1"].exists)
        XCTAssertTrue(report.isEnabled)
        XCTAssertEqual(report.frame.maxX, refresh.frame.maxX, accuracy: 2)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Statistics PDF borderless command"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFavoritePDFCommandsHaveMatchingHeightAndNoLeadingStatisticsIcon() {
        let app = launch()
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        app.buttons["☆ В избранное"].firstMatch.click()
        let favoriteMode = app.radioButtons.matching(NSPredicate(format: "label BEGINSWITH %@", "Избранное")).firstMatch
        XCTAssertTrue(favoriteMode.waitForExistence(timeout: 5))
        favoriteMode.click()
        let report = app.buttons["exportStatisticsPDFButton"]
        let favorites = app.buttons["exportFavoritesPDFButton"]
        let personal = app.buttons["exportVacancyPDF.ui-1"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        XCTAssertTrue(report.isEnabled)
        XCTAssertEqual(report.frame.height, favorites.frame.height, accuracy: 1)
        XCTAssertEqual(report.frame.height, personal.frame.height, accuracy: 1)
        XCTAssertEqual(report.frame.midY, favorites.frame.midY, accuracy: 1)
        XCTAssertLessThan(favorites.frame.maxX, report.frame.minX)
        XCTAssertEqual(report.frame.maxX, personal.frame.maxX, accuracy: 2)
        XCTAssertEqual(report.images.count, 0)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Matching PDF commands in favorites"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStatisticsCommandRemainsAvailableForEmptyCombinedFilter() {
        let app = launch()
        app.buttons["searchVacanciesButton"].click()
        XCTAssertTrue(app.staticTexts["vacancyTitle.ui-1"].waitForExistence(timeout: 8))
        choose("СБЕР", from: "employerFilterPicker", in: app)
        choose("Удалённо", from: "regionFilterPicker", in: app)
        XCTAssertTrue(app.staticTexts["Вакансий не найдено"].waitForExistence(timeout: 5))
        let report = app.buttons["exportStatisticsPDFButton"]
        XCTAssertTrue(report.isEnabled)
        XCTAssertEqual(report.label, "Статистика в PDF")
        XCTAssertEqual(report.frame.height, 32, accuracy: 2)
        XCTAssertTrue(app.staticTexts["Показано вакансий: 0"].exists)
    }

    private func choose(_ option: String, from pickerIdentifier: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)[pickerIdentifier]
        guard picker.waitForExistence(timeout: 5) else {
            XCTFail("Missing picker \(pickerIdentifier)")
            return
        }
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: picker
        )
        guard XCTWaiter.wait(for: [hittable], timeout: 5) == .completed else {
            XCTFail("Picker \(pickerIdentifier) is not ready for interaction")
            return
        }
        picker.click()
        let item = app.menuItems[option]
        guard item.waitForExistence(timeout: 5) else {
            XCTFail("Missing \(option) in \(pickerIdentifier)")
            return
        }
        item.click()
    }
}
