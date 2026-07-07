import XCTest

@MainActor
final class MashangxieKeyboardHostUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testKeyboardHostFieldAcceptsTypedText() throws {
        let app = launchKeyboardHostApp()
        let textView = app.textViews["keyboardHostTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 5), app.debugDescription)

        textView.tap()
        app.typeText("abc")

        XCTAssertTrue(
            textViewValue(textView).contains("abc"),
            "Host text view did not receive typed text.\n\(app.debugDescription)"
        )
    }

    func testCanAttemptMashangxieKeyboardSwitchWhenSystemMenuIsAccessible() throws {
        let (app, textView) = try launchHostAndSwitchToMashangxieKeyboard()

        let nKey = element(
            matching: labeledElements(app, "n"),
            timeout: 2
        )
        let iKey = element(
            matching: labeledElements(app, "i"),
            timeout: 2
        )
        XCTAssertNotNil(nKey, "Mashangxie keyboard did not expose the n key.\n\(app.debugDescription)")
        XCTAssertNotNil(iKey, "Mashangxie keyboard did not expose the i key.\n\(app.debugDescription)")

        nKey?.tap()
        iKey?.tap()

        let candidate = element(
            matching: labeledElements(app, "你"),
            timeout: 5
        )
        XCTAssertNotNil(candidate, "Chinese pinyin candidate '你' did not appear after typing ni.\n\(app.debugDescription)")

        candidate?.tap()
        XCTAssertTrue(
            textViewValue(textView).contains("你"),
            "Chinese candidate was not committed into the host text view.\n\(app.debugDescription)"
        )

        let nineGridSwitch = element(
            matching: labeledElements(app, "九键"),
            timeout: 2
        )
        XCTAssertNotNil(nineGridSwitch, "Mashangxie keyboard did not expose the 九键 switch.\n\(app.debugDescription)")
        nineGridSwitch?.tap()

        let symbolKey = element(
            matching: labeledElements(app, "符号"),
            timeout: 2
        )
        XCTAssertNotNil(symbolKey, "Mashangxie 9-key layout did not expose 符号.\n\(app.debugDescription)")
        symbolKey?.tap()

        let commonCategory = element(
            matching: labeledElements(app, "常用"),
            timeout: 2
        )
        let chineseCategory = element(
            matching: labeledElements(app, "中文"),
            timeout: 2
        )
        XCTAssertNotNil(commonCategory, "Chinese symbol panel did not expose 常用.\n\(app.debugDescription)")
        XCTAssertNotNil(chineseCategory, "Chinese symbol panel did not expose 中文.\n\(app.debugDescription)")

        let atKey = element(matching: labeledElements(app, "@"), timeout: 2)
        XCTAssertNotNil(atKey, "Chinese symbol panel did not expose @.\n\(app.debugDescription)")
        atKey?.tap()

        let sixKey = element(
            matching: labeledElements(app, "MNO"),
            timeout: 2
        )
        let fourKey = element(
            matching: labeledElements(app, "GHI"),
            timeout: 2
        )
        XCTAssertNotNil(sixKey, "Mashangxie 9-key layout did not expose MNO.\n\(app.debugDescription)")
        XCTAssertNotNil(fourKey, "Mashangxie 9-key layout did not expose GHI.\n\(app.debugDescription)")

        sixKey?.tap()
        fourKey?.tap()
        sixKey?.tap()
        fourKey?.tap()

        let t9Candidate = element(
            matching: labeledElements(app, "明") + labeledElements(app, "宁"),
            timeout: 5
        )
        XCTAssertNotNil(t9Candidate, "Chinese 9-key candidate did not appear after typing 6464.\n\(app.debugDescription)")

        t9Candidate?.tap()
        let finalText = textViewValue(textView)
        XCTAssertTrue(
            finalText.contains("你@明") || finalText.contains("你@宁"),
            "Chinese 9-key candidate was not committed into the host text view. Text: \(finalText)\n\(app.debugDescription)"
        )
    }

    func testMashangxieKeyboardModeSwitchingAndVoiceEntryPrepareComposition() throws {
        let (app, textView) = try launchHostAndSwitchToMashangxieKeyboard()

        let modeSwitch = element(
            matching: labeledElements(app, "九键"),
            timeout: 2
        )
        XCTAssertNotNil(modeSwitch, "Mashangxie keyboard did not expose the top 九键 switch.\n\(app.debugDescription)")

        let qKey = element(
            matching: labeledElements(app, "q"),
            timeout: 2
        )
        XCTAssertNotNil(qKey, "Chinese 26-key mode did not expose q.\n\(app.debugDescription)")

        let symbolsSwitch = element(
            matching: labeledElements(app, "More numbers")
                + labeledElements(app, "more numbers")
                + labeledElements(app, "更多数字")
                + labeledElements(app, "更多數字")
                + labeledElements(app, "123"),
            timeout: 2
        )
        XCTAssertNotNil(symbolsSwitch, "Keyboard did not expose the symbols/numbers switch.\n\(app.debugDescription)")
        symbolsSwitch?.tap()

        let oneKey = element(
            matching: labeledElements(app, "1"),
            timeout: 2
        )
        XCTAssertNotNil(oneKey, "Chinese numbers panel did not expose 1.\n\(app.debugDescription)")

        let returnKey = element(
            matching: labeledElements(app, "返回"),
            timeout: 2
        )
        XCTAssertNotNil(returnKey, "Chinese numbers panel did not expose 返回.\n\(app.debugDescription)")
        oneKey?.tap()
        returnKey?.tap()

        let nKey = element(
            matching: labeledElements(app, "n"),
            timeout: 2
        )
        let iKey = element(
            matching: labeledElements(app, "i"),
            timeout: 2
        )
        XCTAssertNotNil(nKey, "Chinese 26-key mode did not expose n.\n\(app.debugDescription)")
        XCTAssertNotNil(iKey, "Chinese 26-key mode did not expose i.\n\(app.debugDescription)")

        nKey?.tap()
        iKey?.tap()

        let micButton = app.buttons["keyboardMicButton"]
        XCTAssertTrue(micButton.waitForExistence(timeout: 2), "Keyboard mic button is missing.\n\(app.debugDescription)")
        micButton.tap()

        XCTAssertTrue(
            textViewValue(textView).contains("你"),
            "Voice entry did not prepare and commit the active Chinese composition before starting recording.\n\(app.debugDescription)"
        )
    }

    func testVoiceEntryAfterRimeInsertsSimulatedFinalTranscription() throws {
        let (app, textView) = try launchHostAndSwitchToMashangxieKeyboard(
            additionalArguments: ["--mashangxie-ui-test-auto-transcription"]
        )

        let nKey = element(
            matching: labeledElements(app, "n"),
            timeout: 2
        )
        let iKey = element(
            matching: labeledElements(app, "i"),
            timeout: 2
        )
        XCTAssertNotNil(nKey, "Chinese 26-key mode did not expose n.\n\(app.debugDescription)")
        XCTAssertNotNil(iKey, "Chinese 26-key mode did not expose i.\n\(app.debugDescription)")

        nKey?.tap()
        iKey?.tap()

        let micButton = app.buttons["keyboardMicButton"]
        XCTAssertTrue(micButton.waitForExistence(timeout: 2), "Keyboard mic button is missing.\n\(app.debugDescription)")
        micButton.tap()

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if textViewValue(textView).contains("你语音") {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail(
            "Voice entry after Rime did not insert simulated final transcription. Text: \(textViewValue(textView))\n\(app.debugDescription)"
        )
    }

    private func launchHostAndSwitchToMashangxieKeyboard(
        additionalArguments: [String] = []
    ) throws -> (XCUIApplication, XCUIElement) {
        let app = launchKeyboardHostApp(additionalArguments: additionalArguments)
        let textView = app.textViews["keyboardHostTextView"]
        XCTAssertTrue(textView.waitForExistence(timeout: 5), app.debugDescription)
        textView.tap()

        let switcher = firstExistingElement(in: [
            app.buttons["下一个键盘"],
            app.buttons["Next keyboard"],
            app.buttons["Next Keyboard"],
            app.buttons["Globe"],
            app.buttons["键盘"],
            app.buttons["地球"],
            app.buttons.containing(NSPredicate(format: "value CONTAINS[c] %@", "码上写")).firstMatch,
        ])

        guard let switcher, switcher.waitForExistence(timeout: 2) else {
            throw XCTSkip("The simulator did not expose a keyboard switcher accessibility element.")
        }

        if textValue(switcher).contains("码上写") {
            switcher.tap()
        } else {
            switcher.press(forDuration: 1.0)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let candidate = firstExistingElement(in: [
                app.buttons["码上写"],
                app.staticTexts["码上写"],
                springboard.buttons["码上写"],
                springboard.staticTexts["码上写"],
            ])

            XCTAssertNotNil(
                candidate,
                "Keyboard switch menu did not expose Mashangxie.\nApp:\n\(app.debugDescription)\nSpringBoard:\n\(springboard.debugDescription)"
            )
            candidate?.tap()
        }

        let mashangxieOnlyKey = element(matching: [
            labeledElements(app, "九键"),
            labeledElements(app, "26键"),
            labeledElements(app, "EN"),
        ].flatMap { $0 }, timeout: 5)
        XCTAssertTrue(
            mashangxieOnlyKey != nil,
            "Mashangxie keyboard did not become visible after switching.\n\(app.debugDescription)"
        )
        if let qwertySwitch = element(matching: labeledElements(app, "26键"), timeout: 0.5) {
            qwertySwitch.tap()
            XCTAssertNotNil(
                element(matching: labeledElements(app, "九键"), timeout: 2),
                "Mashangxie keyboard did not switch back to 26-key mode.\n\(app.debugDescription)"
            )
        }
        return (app, textView)
    }

    private func launchKeyboardHostApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mashangxie-ui-test-keyboard-host"] + additionalArguments
        app.launch()
        return app
    }

    private func firstExistingElement(in elements: [XCUIElement]) -> XCUIElement? {
        elements.first { $0.exists }
    }

    private func element(matching elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = firstExistingElement(in: elements) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return firstExistingElement(in: elements)
    }

    private func labeledElements(_ app: XCUIApplication, _ label: String) -> [XCUIElement] {
        [
            app.buttons[label],
            app.keys[label],
            app.staticTexts[label],
            app.descendants(matching: .any)[label],
        ]
    }

    private func textViewValue(_ textView: XCUIElement) -> String {
        textValue(textView)
    }

    private func textValue(_ element: XCUIElement) -> String {
        if let value = element.value as? String {
            return value
        }
        return element.label
    }
}
