import XCTest
@testable import SleightCore

final class VoiceTests: XCTestCase {
    func testWakePhraseAndMisspellings() {
        XCTAssertEqual(VoiceCommands.afterWakePhrase("Hey Sleight, scroll down.", word: .sleight), "scroll down.")
        XCTAssertEqual(VoiceCommands.afterWakePhrase("hey slight switch to Claude", word: .sleight), "switch to Claude")
        XCTAssertEqual(VoiceCommands.afterWakePhrase("OK, sleigh. Pause", word: .sleight), "Pause")
        XCTAssertEqual(VoiceCommands.afterWakePhrase("hey slate", word: .sleight), "")
        XCTAssertEqual(VoiceCommands.afterWakePhrase("Hey slide slide scroll down", word: .sleight), "scroll down")
        XCTAssertEqual(VoiceCommands.dropLeadingName("Slide slide scroll down", word: .sleight), "scroll down")
        XCTAssertEqual(VoiceCommands.afterWakePhrase("blah hey sleight back hey sleight next tab", word: .sleight), "next tab")
    }

    func testNameInConversationIsNotAWake() {
        XCTAssertNil(VoiceCommands.afterWakePhrase("there's a slight problem with the build", word: .sleight))
        XCTAssertNil(VoiceCommands.afterWakePhrase("sleight of hand", word: .sleight))
        XCTAssertNil(VoiceCommands.afterWakePhrase("hey everyone", word: .sleight))
    }

    func testJarvis() {
        XCTAssertEqual(VoiceCommands.wake(in: "Jarvis switch to Finder"), .init(command: "switch to Finder", strong: true))
        XCTAssertEqual(VoiceCommands.wake(in: "Hey Jarvis, mission control"), .init(command: "mission control", strong: true))
        XCTAssertEqual(VoiceCommands.wake(in: "Jarvis"), .init(command: "", strong: true))
        XCTAssertNil(VoiceCommands.wake(in: "I asked Jarvis about it yesterday"))
        XCTAssertNil(VoiceCommands.wake(in: "slide mission control"), "other words' spellings don't count")
        XCTAssertEqual(VoiceCommands.dropLeadingName("Jarvis Jarvis scroll down"), "scroll down")
    }

    func testCamera() {
        XCTAssertEqual(VoiceCommands.parse("camera on"), .cameraOn)
        XCTAssertEqual(VoiceCommands.parse("turn on the camera"), .cameraOn)
        XCTAssertEqual(VoiceCommands.parse("camera off"), .cameraOff)
        XCTAssertEqual(VoiceCommands.parse("stop watching"), .cameraOff)
    }

    func testMenuCommandsOfTheAppInFront() {
        let menu = ["New Window", "New Tab", "Export as PDF…", "Print…", "Close Tab", "Show Sidebar"]
        XCTAssertEqual(VoiceCommands.parse("export as PDF", menu: menu), .menuItem("Export as PDF…"))
        XCTAssertEqual(VoiceCommands.parse("click show sidebar", menu: menu), .menuItem("Show Sidebar"))
        XCTAssertEqual(VoiceCommands.parse("export as pdx", menu: menu), .menuItem("Export as PDF…"), "near miss")
        XCTAssertEqual(VoiceCommands.parse("new tab", menu: menu), .action(.newTab, times: 1), "built-in wins")
        XCTAssertNil(VoiceCommands.parse("prints", menu: menu), "short titles must match exactly")
        XCTAssertNil(VoiceCommands.parse("export as PDF"), "nothing without the menu")
    }

    func testEverydayCommands() {
        XCTAssertEqual(VoiceCommands.parse("close this tab"), .action(.closeTab, times: 1))
        XCTAssertEqual(VoiceCommands.parse("undo that"), .action(.undo, times: 1))
        XCTAssertEqual(VoiceCommands.parse("undo 3 times"), .action(.undo, times: 3))
        XCTAssertEqual(VoiceCommands.parse("copy"), .action(.copy, times: 1))
        XCTAssertEqual(VoiceCommands.parse("refresh"), .action(.reload, times: 1))
        XCTAssertEqual(VoiceCommands.parse("go to top"), .action(.scrollToTop, times: 1), "not an app called top")
        XCTAssertEqual(VoiceCommands.parse("press enter"), .action(.returnKey, times: 1))
        XCTAssertEqual(VoiceCommands.parse("find"), .action(.find, times: 1))
        XCTAssertEqual(VoiceCommands.parse("find invoices"), .search("invoices"))
    }

    func testNearMissesIncludingSpacing() {
        XCTAssertEqual(VoiceCommands.parse("camera of"), .cameraOff)
        XCTAssertEqual(VoiceCommands.parse("mission controls"), .action(.missionControl, times: 1))
        XCTAssertEqual(VoiceCommands.parse("full screen"), .action(.fullScreen, times: 1))
        XCTAssertEqual(VoiceCommands.parse("screen shot"), .action(.screenshot, times: 1))
        let menu = ["New Finder Window", "New Folder", "Get Info"]
        XCTAssertEqual(VoiceCommands.parse("new find the window", menu: menu), .menuItem("New Finder Window"))
    }

    func testWebShortcutsQuitVolume() {
        XCTAssertEqual(VoiceCommands.parse("open github com"), .openURL("github.com"))
        XCTAssertEqual(VoiceCommands.parse("go to news dot ycombinator dot com"), .openURL("news.ycombinator.com"))
        XCTAssertEqual(VoiceCommands.parse("youtube.com"), .openURL("youtube.com"))
        XCTAssertEqual(VoiceCommands.parse("open Safari"), .switchTo("safari"))
        XCTAssertEqual(VoiceCommands.parse("google best ramen in Bangalore"), .webSearch("best ramen in Bangalore"))
        XCTAssertEqual(VoiceCommands.parse("search for invoices"), .search("invoices"), "Spotlight stays Spotlight")
        XCTAssertEqual(VoiceCommands.parse("run Morning Routine"), .runShortcut("Morning Routine"))
        XCTAssertEqual(VoiceCommands.parse("quit Slack"), .quit("slack"))
        XCTAssertEqual(VoiceCommands.parse("quit"), .action(.quitApp, times: 1))
        XCTAssertEqual(VoiceCommands.parse("set volume to 30 percent"), .setVolume(30))
        XCTAssertEqual(VoiceCommands.parse("volume max"), .setVolume(100))
        XCTAssertEqual(VoiceCommands.parse("volume up"), .action(.volumeUp, times: 3))
    }

    func testScrolling() {
        XCTAssertEqual(VoiceCommands.parse("scroll right"), .action(.scrollRight, times: 1))
        XCTAssertEqual(VoiceCommands.parse("scroll left twice"), .action(.scrollLeft, times: 2))
        XCTAssertEqual(VoiceCommands.parse("keep scrolling"), .autoScroll(up: false))
        XCTAssertEqual(VoiceCommands.parse("keep scrolling up"), .autoScroll(up: true))
        XCTAssertEqual(VoiceCommands.parse("much faster"), .scrollFaster(steps: 2))
        XCTAssertEqual(VoiceCommands.parse("stop scrolling"), .stopScrolling)
        // While scrolling: the last words of whatever was heard, no wake word.
        XCTAssertEqual(VoiceCommands.scrollControl(atEndOf: "this article is long. Faster"), .scrollFaster(steps: 1))
        XCTAssertEqual(VoiceCommands.scrollControl(atEndOf: "okay slow down"), .scrollSlower(steps: 1))
        XCTAssertEqual(VoiceCommands.scrollControl(atEndOf: "Stop."), .stopScrolling)
        XCTAssertEqual(VoiceCommands.scrollControl(atEndOf: "go back up"), .autoScroll(up: true))
        XCTAssertNil(VoiceCommands.scrollControl(atEndOf: "this is a good paragraph"))
    }

    func testScrollLeftRightMoveSideways() {
        let c = SleightConfig()
        guard case .scrollFlick(let r)? = ActionMapper.fire(.scrollRight, speed: nil, config: c).first,
              case .scrollFlick(let l)? = ActionMapper.fire(.scrollLeft, speed: nil, config: c).first else {
            return XCTFail("expected scroll flicks")
        }
        XCTAssertEqual(r.y, 0); XCTAssertLessThan(r.x, 0)
        XCTAssertEqual(l.y, 0); XCTAssertGreaterThan(l.x, 0)
    }

    func testConversationMode() {
        XCTAssertEqual(VoiceCommands.parse("stay"), .startSession)
        XCTAssertEqual(VoiceCommands.parse("keep listening"), .startSession)
        XCTAssertEqual(VoiceCommands.parse("that's all"), .endSession)
        XCTAssertEqual(VoiceCommands.parse("Thanks!"), .endSession)
        XCTAssertEqual(VoiceCommands.parse("stop listening"), .rest, "rest still rests")
    }

    func testWeakWakeNeedsARealCommand() {
        XCTAssertEqual(VoiceCommands.wake(in: "He slide mission control", word: .sleight), .init(command: "mission control", strong: false))
        XCTAssertEqual(VoiceCommands.wake(in: "Slide mission control", word: .sleight), .init(command: "mission control", strong: false))
        XCTAssertEqual(VoiceCommands.wake(in: "Heli rest", word: .sleight), .init(command: "rest", strong: false))
        XCTAssertEqual(VoiceCommands.wake(in: "Hey slide", word: .sleight), .init(command: "", strong: true))
        XCTAssertNil(VoiceCommands.wake(in: "we had a slight problem with the build", word: .sleight))
        XCTAssertNil(VoiceCommands.wake(in: "slight problem here", word: .sleight))
        XCTAssertNil(VoiceCommands.wake(in: "he slide", word: .sleight))
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
        XCTAssertEqual(VoiceCommands.parse("Type: Hello, see you at 6. Thanks!"), .type("Hello, see you at 6. Thanks!"))
        XCTAssertEqual(VoiceCommands.afterWakePhrase("Jarvis, type Don't forget the milk."), "type Don't forget the milk.")
        XCTAssertEqual(VoiceCommands.parse("insert my email"), .type("my email"))
        XCTAssertEqual(VoiceCommands.parse("say On my way, see you soon!"), .type("On my way, see you soon!"))
        XCTAssertNil(VoiceCommands.parse("type"), "wait for the words")
        XCTAssertTrue(VoiceCommands.startsDictation("Type."))
        XCTAssertEqual(VoiceCommands.parse("Type. Meet me at six."), .type("Meet me at six."), "words after a pause")
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
