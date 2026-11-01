import XCTest
@testable import SleightCore

final class VoiceTests: XCTestCase {
    func testWakePhraseAndMisspellings() {
        XCTAssertEqual(VoiceCommands.afterWakePhrase("Hey Sleight, scroll down."), "scroll down")
        XCTAssertEqual(VoiceCommands.afterWakePhrase("hey slight switch to Claude"), "switch to Claude")
        XCTAssertEqual(VoiceCommands.afterWakePhrase("OK, sleigh. Pause"), "Pause")
        XCTAssertEqual(VoiceCommands.afterWakePhrase("hey slate"), "")
        XCTAssertEqual(VoiceCommands.afterWakePhrase("Hey slide slide scroll down"), "scroll down")
        XCTAssertEqual(VoiceCommands.dropLeadingName("Slide slide scroll down"), "scroll down")
        XCTAssertEqual(VoiceCommands.afterWakePhrase("blah hey sleight back hey sleight next tab"), "next tab")
    }

    func testNameInConversationIsNotAWake() {
        XCTAssertNil(VoiceCommands.afterWakePhrase("there's a slight problem with the build"))
        XCTAssertNil(VoiceCommands.afterWakePhrase("sleight of hand"))
        XCTAssertNil(VoiceCommands.afterWakePhrase("hey everyone"))
    }

    func testWeakWakeNeedsARealCommand() {
        XCTAssertEqual(VoiceCommands.wake(in: "He slide mission control"), .init(command: "mission control", strong: false))
        XCTAssertEqual(VoiceCommands.wake(in: "Slide mission control"), .init(command: "mission control", strong: false))
        XCTAssertEqual(VoiceCommands.wake(in: "Heli rest"), .init(command: "rest", strong: false))
        XCTAssertEqual(VoiceCommands.wake(in: "Hey slide"), .init(command: "", strong: true))
        XCTAssertNil(VoiceCommands.wake(in: "we had a slight problem with the build"))
        XCTAssertNil(VoiceCommands.wake(in: "slight problem here"))
        XCTAssertNil(VoiceCommands.wake(in: "he slide"))
    }

    func testActions() {
        XCTAssertEqual(VoiceCommands.parse("scroll down"), .action(.scrollDown, times: 1))
        XCTAssertEqual(VoiceCommands.parse("please go back"), .action(.back, times: 1))
        XCTAssertEqual(VoiceCommands.parse("pause"), .action(.playPause, times: 1))
        XCTAssertEqual(VoiceCommands.parse("next tab twice"), .action(.nextTab, times: 2))
        XCTAssertEqual(VoiceCommands.parse("scroll down three times"), .action(.scrollDown, times: 3))
        XCTAssertEqual(VoiceCommands.parse("volume up"), .action(.volumeUp, times: 3))
        XCTAssertEqual(VoiceCommands.parse("scrawl down"), .action(.scrollDown, times: 1))
        XCTAssertEqual(VoiceCommands.parse("Mission Control."), .action(.missionControl, times: 1))
    }

    func testSleightControl() {
        XCTAssertEqual(VoiceCommands.parse("rest"), .rest)
        XCTAssertEqual(VoiceCommands.parse("go to sleep"), .rest)
        XCTAssertEqual(VoiceCommands.parse("wake up"), .wake)
        XCTAssertEqual(VoiceCommands.parse("never mind"), .cancel)
        XCTAssertEqual(VoiceCommands.parse("pointer mode"), .pointerMode)
    }

    func testArguments() {
        XCTAssertEqual(VoiceCommands.parse("switch to Claude"), .switchTo("claude"))
        XCTAssertEqual(VoiceCommands.parse("open the Safari app"), .switchTo("safari"))
        XCTAssertEqual(VoiceCommands.parse("type Hello there"), .type("Hello there"))
        XCTAssertEqual(VoiceCommands.parse("search for flights to Goa"), .search("flights to Goa"))
        XCTAssertNil(VoiceCommands.parse("switch to"), "wait for the app name")
        XCTAssertNil(VoiceCommands.parse("what's the weather like"))
        XCTAssertNil(VoiceCommands.parse(""))
    }

    func testAppMatching() {
        let apps = ["Claude", "Safari", "Google Chrome", "Visual Studio Code", "Xcode", "Slack", "Notes", "Notion"]
        XCTAssertEqual(VoiceCommands.bestApp(for: "claude", in: apps), "Claude")
        XCTAssertEqual(VoiceCommands.bestApp(for: "cloud", in: apps), "Claude")
        XCTAssertEqual(VoiceCommands.bestApp(for: "chrome", in: apps), "Google Chrome")
        XCTAssertEqual(VoiceCommands.bestApp(for: "vs code", in: apps), "Visual Studio Code")
        XCTAssertEqual(VoiceCommands.bestApp(for: "x code", in: apps), "Xcode")
        XCTAssertEqual(VoiceCommands.bestApp(for: "notion", in: apps), "Notion")
        XCTAssertEqual(VoiceCommands.bestApp(for: "slak", in: apps), "Slack")
        XCTAssertNil(VoiceCommands.bestApp(for: "photoshop", in: apps))
    }
}
