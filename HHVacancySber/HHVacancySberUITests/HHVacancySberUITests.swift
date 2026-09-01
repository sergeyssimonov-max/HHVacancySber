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
}
