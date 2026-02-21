//
//  CryptoSageUITests.swift
//  CryptoSageUITests
//
//  Created by DM on 5/2/25.
//

import XCTest

final class CryptoSageUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    @MainActor
    func testTimeframeSwitchSmoke() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Move to market/trading context if the tab exists.
        let marketTab = app.tabBars.buttons["Market"].firstMatch
        if marketTab.waitForExistence(timeout: 3) {
            marketTab.tap()
        }
        
        let labels = ["1m", "5m", "15m", "30m", "1H", "4H", "24H", "1W", "1M", "3M", "6M", "1Y", "3Y", "ALL"]
        var tappedCount = 0
        for label in labels {
            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 1) {
                button.tap()
                tappedCount += 1
            }
        }
        
        XCTAssertGreaterThan(tappedCount, 0, "Expected at least one timeframe button to be available.")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
