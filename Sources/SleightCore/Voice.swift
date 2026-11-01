import Foundation

/// What a spoken command asks for.
public enum VoiceIntent: Equatable, Sendable {
    /// One of the gesture actions, `times` in a row ("next tab twice").
    case action(ActionID, times: Int)
    /// Bring an app forward, launching it if needed.
    case switchTo(String)
    /// Type text into whatever has focus.
    case type(String)
    /// Spotlight search.
    case search(String)
    case rest, wake
    case pointerMode, gestureMode
    /// Camera (and so gestures) on or off.
    case cameraOn, cameraOff
    /// A menu command of the app in front, by its title ("Export as PDF…").
    case menuItem(String)
    /// A website ("open github.com") or a web search ("google best ramen").
    case openURL(String)
    case webSearch(String)
    /// An Apple Shortcut, by name.
    case runShortcut(String)
    case quit(String)
    /// Output volume, 0–100.
    case setVolume(Int)
    /// Continuous scrolling, and its speed while it runs.
    case autoScroll(up: Bool)
    case scrollFaster(steps: Int)
    case scrollSlower(steps: Int)
    case stopScrolling
    /// Conversation mode: commands without the wake word until "done".
    case startSession, endSession
    /// "never mind": close the listening chip without doing anything.
    case cancel
    /// A key or combination, `times` in a row ("press command shift T").
    case pressKey(KeyPress, times: Int)
    /// Modifiers held down until released ("hold shift" … "release").
    case holdKeys([KeyModifier])
    /// Let go of these modifiers; empty = all of them.
    case releaseKeys([KeyModifier])
}

/// The word that gets Sleight's attention. Picked by measurement: synthetic
/// speech in 8 voices through the on-device recogniser came back as "Jarvis"
/// 47 times out of 48, "Sleight" 0 times (it hears "slide", "slight",
/// "paste light"), which is why it is a setting and not the app's name.
public enum WakeWord: String, Codable, CaseIterable, Sendable {
    case jarvis, computer, friday, sleight

    public var title: String { rawValue.capitalized }

    /// Spellings the recogniser produces for it.
    var forms: Set<String> {
        switch self {
        case .jarvis: return ["jarvis", "jarvis's", "jervis", "javis", "jarvas"]
        case .computer: return ["computer", "computers", "computer's"]
        case .friday: return ["friday", "friday's"]
        case .sleight: return [
            "sleight", "slight", "sleigh", "slate", "slay", "sleights", "slights", "sleighs",
            "slates", "slays", "sleit", "sliet", "slait", "sleight's", "slight's",
            "slide", "slides", "slice", "sly", "sleet", "slate's", "slide's",
        ]
        }
    }

    /// "Sleight" is misheard as everyday words, so it needs "hey" in front.
    /// The others work alone.
    var needsGreeting: Bool { self == .sleight }

    /// "hey Sleight" heard as one word.
    var merged: Set<String> { self == .sleight ? ["heli", "haley", "hailey", "hayley", "halee", "heylight"] : [] }

    /// How to say it, for the UI.
    public var phrase: String { needsGreeting ? "hey \(title)" : title }
}

/// Turns transcripts into intents. Pure text in, intent out, so it can be
/// tested without a microphone.
///
/// The wake word comes first ("Jarvis, switch to Claude"), or alone, then the
/// command after a pause. Said in the middle of a sentence ("I asked Jarvis
/// yesterday") it does nothing: whatever follows must be a command.
public enum VoiceCommands {
    static let greetings: Set<String> = ["hey", "hi", "ok", "okay", "hay"]
    /// What "hey" turns into when heard badly. Too common to count on their own.
    static let weakGreetings: Set<String> = ["he", "a", "eh", "hey's", "high"]

    /// Lowercase (unless `keepCase`), no punctuation, single spaces.
    public static func normalize(_ s: String, keepCase: Bool = false) -> String {
        var out = ""
        for ch in keepCase ? s : s.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "'" { out.append(ch) } else { out.append(" ") }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    /// The transcript as spoken words: each keeps its original text (capitals,
    /// punctuation) for dictation, plus a bare lowercase key for matching.
    static func tokens(_ s: String) -> [(text: String, key: String)] {
        s.split(whereSeparator: \.isWhitespace).map { (String($0), normalize(String($0))) }
            .filter { !$0.1.isEmpty || $0.0.contains(where: { $0.isLetter || $0.isNumber }) }
    }

    static func join(_ t: ArraySlice<(text: String, key: String)>) -> String {
        t.map(\.text).joined(separator: " ")
    }

    /// Finds the last wake phrase in `transcript` and returns what follows it,
    /// as spoken (possibly empty), or nil when there's none.
    public static func afterWakePhrase(_ transcript: String, word: WakeWord = .jarvis) -> String? {
        let t = tokens(transcript)
        for i in stride(from: t.count - 1, through: 0, by: -1) where word.forms.contains(t[i].key) {
            if word.needsGreeting, i == 0 || !greetings.contains(t[i - 1].key) { continue }
            return dropLeadingName(join(t[(i + 1)...]), word: word)
        }
        return nil
    }

    /// A wake phrase, strong or weak. Weak ones (for "Sleight": "he slide",
    /// "heli", or the name at the very start) only count when a whole command
    /// follows, so everyday speech can't open the listening chip.
    public struct Wake: Equatable, Sendable {
        public let command: String
        public let strong: Bool
    }

    public static func wake(in transcript: String, word: WakeWord = .jarvis) -> Wake? {
        if let c = afterWakePhrase(transcript, word: word) {
            // A bare word mid-sentence isn't a call: it must end the transcript
            // so far (a pause before the command) or be followed by a command.
            if word.needsGreeting || c.isEmpty || parse(c) != nil { return Wake(command: c, strong: true) }
        }
        let t = tokens(transcript)
        func weak(from i: Int) -> Wake? {
            guard i <= t.count else { return nil }
            let c = dropLeadingName(join(t[i...]), word: word)
            return parse(c) != nil ? Wake(command: c, strong: false) : nil
        }
        guard word.needsGreeting else { return nil }
        for i in stride(from: t.count - 1, through: 0, by: -1) {
            if word.merged.contains(t[i].key), let w = weak(from: i + 1) { return w }
            if i + 1 < t.count, weakGreetings.contains(t[i].key), word.forms.contains(t[i + 1].key),
               let w = weak(from: i + 2) { return w }
        }
        if let first = t.first?.key, word.forms.contains(first), let w = weak(from: 1) { return w }
        return nil
    }

    /// Recognisers revise as they go ("hey slide" → "slide slide scroll down"):
    /// drop greeting and name words from the start of a command.
    public static func dropLeadingName(_ command: String, word: WakeWord = .jarvis) -> String {
        var t = tokens(command)[...]
        while let first = t.first?.key,
              word.forms.contains(first) || greetings.contains(first) || weakGreetings.contains(first)
                || word.merged.contains(first) {
            t = t.dropFirst()
        }
        return join(t)
    }

    // MARK: Commands

    /// Spoken forms of each action. The first is the one shown in the guide.
    public static let phrases: [(ActionID, [String])] = [
        (.scrollDown, ["scroll down", "down", "page down"]),
        (.scrollUp, ["scroll up", "up", "page up"]),
        (.scrollLeft, ["scroll left"]),
        (.scrollRight, ["scroll right"]),
        (.back, ["go back", "back"]),
        (.forward, ["go forward", "forward"]),
        (.nextTab, ["next tab"]),
        (.previousTab, ["previous tab", "last tab"]),
        (.newTab, ["new tab", "open a new tab"]),
        (.reopenTab, ["reopen tab", "reopen closed tab", "undo close tab"]),
        (.desktopLeft, ["desktop left", "previous desktop", "space left"]),
        (.desktopRight, ["desktop right", "next desktop", "space right"]),
        (.missionControl, ["mission control", "show all windows"]),
        (.appWindows, ["app windows", "show app windows"]),
        (.showDesktop, ["show desktop", "show the desktop"]),
        (.previousApp, ["previous app", "switch back", "last app"]),
        (.hideApp, ["hide app", "hide this", "hide"]),
        (.minimize, ["minimize", "minimise", "minimize window", "minimise window"]),
        (.fullScreen, ["full screen", "fullscreen", "toggle full screen"]),
        (.playPause, ["pause", "play", "play pause", "resume music", "pause music", "stop music"]),
        (.nextTrack, ["next track", "next song", "skip"]),
        (.previousTrack, ["previous track", "previous song"]),
        (.volumeUp, ["volume up", "louder", "turn it up"]),
        (.volumeDown, ["volume down", "quieter", "softer", "turn it down"]),
        (.mute, ["mute", "unmute"]),
        (.zoomIn, ["zoom in"]),
        (.zoomOut, ["zoom out"]),
        (.screenshot, ["screenshot", "take a screenshot", "take screenshot"]),
        (.screenshotSelection, ["screenshot selection", "screenshot a selection", "capture selection"]),
        (.screenshotTool, ["screenshot tool", "screen recording"]),
        (.spotlight, ["spotlight", "open spotlight"]),
        (.lockScreen, ["lock screen", "lock the screen", "lock"]),
        (.toggleKeyboard, ["keyboard", "show keyboard", "hide keyboard"]),
        (.closeTab, ["close tab", "close this tab", "close window", "close this window", "close it", "close this", "close"]),
        (.newWindow, ["new window", "open a new window"]),
        (.quitApp, ["quit", "quit app", "quit this app", "quit it"]),
        (.undo, ["undo", "undo that"]),
        (.redo, ["redo", "redo that"]),
        (.cut, ["cut", "cut that"]),
        (.copy, ["copy", "copy that", "copy this"]),
        (.paste, ["paste", "paste it", "paste that"]),
        (.selectAll, ["select all", "select everything"]),
        (.save, ["save", "save it", "save this", "save file"]),
        (.find, ["find", "find in page", "find on page"]),
        (.reload, ["reload", "refresh", "reload page", "refresh page", "reload this", "refresh this"]),
        (.scrollToTop, ["scroll to top", "go to top", "top", "back to top", "scroll all the way up"]),
        (.scrollToBottom, ["scroll to bottom", "go to bottom", "bottom", "scroll all the way down"]),
        (.returnKey, ["enter", "press enter", "return", "press return", "hit enter", "submit"]),
        (.escapeKey, ["escape", "press escape", "hit escape"]),
        (.tabKey, ["press tab", "tab key", "hit tab"]),
        (.spaceKey, ["press space", "space", "space bar", "hit space"]),
        (.deleteKey, ["delete", "backspace", "press delete", "hit delete"]),
    ]

    /// Fixed phrases that drive Sleight itself.
    static let controls: [(VoiceIntent, [String])] = [
        (.cancel, ["cancel", "never mind", "nevermind", "nothing", "forget it"]),
        (.rest, ["rest", "go to sleep", "sleep", "stop listening", "take a break", "go rest"]),
        (.wake, ["wake up", "wake", "start listening", "i'm back", "im back"]),
        (.cameraOn, ["camera on", "camera", "start camera", "turn on camera", "turn camera on",
                     "gestures on", "start gestures", "watch", "watch me", "eyes on"]),
        (.cameraOff, ["camera off", "stop camera", "turn off camera", "turn camera off",
                      "gestures off", "stop gestures", "stop watching", "eyes off"]),
        (.autoScroll(up: false), ["keep scrolling", "keep scrolling down", "auto scroll", "autoscroll", "auto scroll down",
                                  "start scrolling", "scroll slowly", "slow scroll", "scroll down slowly", "read mode",
                                  "scroll continuously", "keep going down"]),
        (.autoScroll(up: true), ["keep scrolling up", "auto scroll up", "autoscroll up", "scroll up slowly", "keep going up"]),
        (.scrollFaster(steps: 1), ["faster", "speed up", "quicker", "bit faster", "a bit faster", "little faster"]),
        (.scrollFaster(steps: 2), ["much faster", "a lot faster", "way faster"]),
        (.scrollSlower(steps: 1), ["slower", "slow down", "bit slower", "a bit slower", "little slower"]),
        (.scrollSlower(steps: 2), ["much slower", "a lot slower", "way slower"]),
        (.stopScrolling, ["stop", "stop scrolling", "pause scrolling", "hold on", "hold", "wait", "enough", "stop there"]),
        (.startSession, ["stay", "stay with me", "keep listening", "listen", "command mode", "conversation mode",
                         "continuous mode", "hands free", "let's go", "lets go", "stick around"]),
        (.endSession, ["done", "that's all", "thats all", "that's it", "thats it", "thanks", "thank you",
                       "finish", "finished", "exit", "goodbye", "bye", "dismiss", "i'm done", "im done"]),
        (.pointerMode, ["pointer mode", "pointer", "mouse mode", "cursor mode"]),
        (.gestureMode, ["gesture mode", "gestures", "exit pointer", "leave pointer mode", "stop pointer"]),
    ]
    /// Words that add nothing ("please scroll down").
    static let filler: Set<String> = ["please", "can", "you", "could", "would", "just", "now", "the", "sleight"]
    static let switchVerbs = ["switch to", "go to", "open", "launch", "show me", "bring up", "start", "focus"]
    static let typeVerbs: Set<String> = ["type", "say", "write", "dictate", "insert"]
    static let webVerbs = ["google", "search the web for", "search google for", "search online for", "web search",
                           "search the internet for", "look up online"]
    static let searchVerbs = ["search for", "search", "look up", "find"]
    static let shortcutVerbs = ["run shortcut", "run the shortcut", "run", "shortcut"]
    static let quitVerbs = ["quit", "close the app", "close app"]
    /// Endings that make "open github com" a website, not an app.
    static let domains: Set<String> = ["com", "org", "net", "io", "dev", "ai", "app", "co", "in", "uk", "me", "tv", "gg", "so"]

    /// Parses what came after the wake phrase. nil = not (yet) a command.
    public static func parse(_ command: String) -> VoiceIntent? {
        let raw = normalize(command)
        guard !raw.isEmpty else { return nil }

        // Free text keeps its own words and capitals (no filler stripping).
        let cased = normalize(command, keepCase: true).split(separator: " ")
        func original(_ tail: String) -> String {
            cased.suffix(tail.split(separator: " ").count).joined(separator: " ")
        }
        if let text = dictation(command) { return .type(text) }
        if let q = argument(raw, verbs: webVerbs, trimArticles: false) { return .webSearch(original(q)) }
        if let q = argument(raw, verbs: searchVerbs, trimArticles: false) { return .search(original(q)) }

        var words = raw.split(separator: " ").map(String.init)
        let (stripped, times) = repeatCount(words)
        words = stripped.filter { !filler.contains($0) }
        let phrase = words.joined(separator: " ")
        guard !phrase.isEmpty else { return nil }

        if let v = volumeLevel(words) { return .setVolume(v) }
        if let intent = fixed(phrase, times: times, nearMisses: false) { return intent }
        // Keys drop filler only from the front: "you" is also the letter U.
        var keyWords = stripped.filter { $0 != "please" }
        while let w = keyWords.first, filler.contains(w) { keyWords.removeFirst() }
        if let intent = Keys.command(keyWords, times: times) { return intent }
        if let intent = fixed(phrase, times: times) { return intent }
        if let name = argument(raw, verbs: shortcutVerbs, trimArticles: false) { return .runShortcut(original(name)) }
        if let app = argument(phrase, verbs: quitVerbs) { return .quit(app) }
        if let target = argument(phrase, verbs: switchVerbs) {
            if let url = website(target) { return .openURL(url) }
            return .switchTo(target)
        }
        if let url = website(phrase) { return .openURL(url) }
        return nil
    }

    /// A built-in action or control phrase: exact first, then a near miss
    /// ("camera of", "scrawl down"), comparing without spaces so a word heard
    /// split or joined still counts.
    static func fixed(_ phrase: String, times: Int?, nearMisses: Bool = true) -> VoiceIntent? {
        func act(_ a: ActionID) -> VoiceIntent { .action(a, times: times ?? defaultTimes(a)) }
        for (intent, forms) in controls where forms.contains(phrase) { return intent }
        for (a, forms) in phrases where forms.contains(phrase) { return act(a) }
        guard nearMisses else { return nil }
        let squashed = phrase.replacingOccurrences(of: " ", with: "")
        guard squashed.count >= 6 else { return nil }
        var best: (VoiceIntent, Double)?
        func consider(_ intent: VoiceIntent, _ forms: [String]) {
            for f in forms {
                let g = f.replacingOccurrences(of: " ", with: "")
                guard g.count >= 6 else { continue }
                let sim = similarity(squashed, g)
                if sim >= 0.8, sim > (best?.1 ?? 0) { best = (intent, sim) }
            }
        }
        for (intent, forms) in controls { consider(intent, forms) }
        for (a, forms) in phrases { consider(act(a), forms) }
        return best?.0
    }

    /// "type Hello, see you at six." → "Hello, see you at six." exactly as heard.
    /// nil when it isn't a type command or nothing follows the verb yet.
    public static func dictation(_ command: String) -> String? {
        let t = tokens(command)
        guard let first = t.first, typeVerbs.contains(first.key), t.count > 1 else { return nil }
        var text = join(t.dropFirst())
        // The recogniser sometimes puts a comma or colon after the verb.
        while let c = text.first, ",:;.-".contains(c) { text.removeFirst(); text = text.trimmingCharacters(in: .whitespaces) }
        return text.isEmpty ? nil : text
    }

    /// While scrolling continuously, these work without the wake word: the
    /// last few words of whatever was heard, if they are one of them.
    public static func scrollControl(atEndOf transcript: String) -> VoiceIntent? {
        let t = tokens(transcript)
        for n in stride(from: min(3, t.count), through: 1, by: -1) {
            let tail = t.suffix(n).map(\.key).joined(separator: " ")
            for (intent, forms) in controls where forms.contains(tail) {
                switch intent {
                case .scrollFaster, .scrollSlower, .stopScrolling, .autoScroll: return intent
                default: continue
                }
            }
            // "up" / "down" turn it around.
            if tail == "up" || tail == "scroll up" { return .autoScroll(up: true) }
            if tail == "down" || tail == "scroll down" { return .autoScroll(up: false) }
        }
        return nil
    }

    /// "type …", including "type" on its own with the words still to come.
    public static func startsDictation(_ command: String) -> Bool {
        tokens(command).first.map { typeVerbs.contains($0.key) } ?? false
    }

    /// "volume 30", "set volume to 50 percent", "volume to max".
    static func volumeLevel(_ words: [String]) -> Int? {
        guard let i = words.firstIndex(of: "volume") else { return nil }
        let rest = words[(i + 1)...].filter { !["to", "at", "percent", "%", "level"].contains($0) }
        guard rest.count == 1, let w = rest.first else { return nil }
        if ["max", "maximum", "full"].contains(w) { return 100 }
        if ["zero", "off", "min", "minimum"].contains(w) { return 0 }
        if ["half", "fifty"].contains(w) { return 50 }
        return Int(w.trimmingCharacters(in: CharacterSet(charactersIn: "%"))).map { min(max($0, 0), 100) }
    }

    /// "github com" → "github.com"; "news ycombinator com" → "news.ycombinator.com".
    static func website(_ phrase: String) -> String? {
        var words = phrase.split(separator: " ").map(String.init).filter { $0 != "dot" }
        guard words.count >= 2, let last = words.last, domains.contains(last) else { return nil }
        if words.first == "www" { words.removeFirst() }
        return words.joined(separator: ".")
    }

    /// Like `parse`, but also knows the menu commands of the app in front:
    /// "Jarvis, export as PDF", "Jarvis, click new window". Built-in commands win.
    public static func parse(_ command: String, menu: [String]) -> VoiceIntent? {
        if let intent = parse(command) { return intent }
        return menuItem(for: command, in: menu).map { .menuItem($0) }
    }

    /// The menu title that was said, exactly or nearly ("export as pdf" →
    /// "Export as PDF…"). Short titles must match exactly.
    public static func menuItem(for command: String, in titles: [String]) -> String? {
        var said = normalize(command)
        for verb in ["click on ", "click ", "choose ", "select ", "press ", "menu "] where said.hasPrefix(verb) {
            said = String(said.dropFirst(verb.count))
        }
        guard !said.isEmpty else { return nil }
        var best: (String, Double)?
        for t in titles {
            let n = normalize(t)
            guard !n.isEmpty else { continue }
            if n == said { return t }
            guard n.count >= 6, said.count >= 6 else { continue }
            // Without spaces: "new find the window" ≈ "newfinderwindow".
            let s = max(similarity(said, n), similarity(said.replacingOccurrences(of: " ", with: ""),
                                                        n.replacingOccurrences(of: " ", with: "")))
            // Long titles leave less room for a wrong match.
            if s >= (n.count >= 12 ? 0.8 : 0.85), s > (best?.1 ?? 0) { best = (t, s) }
        }
        return best?.0
    }

    /// Steps that are tiny on their own get a few in a row.
    static func defaultTimes(_ a: ActionID) -> Int {
        switch a {
        case .volumeUp, .volumeDown: return 3
        default: return 1
        }
    }

    /// "… twice", "… 3 times" → (words without the count, count).
    static func repeatCount(_ words: [String]) -> ([String], Int?) {
        let numbers = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                       "seven": 7, "eight": 8, "nine": 9, "ten": 10]
        guard let last = words.last else { return (words, nil) }
        if last == "twice" { return (Array(words.dropLast()), 2) }
        if last == "thrice" { return (Array(words.dropLast()), 3) }
        if last == "times" || last == "time", words.count >= 2 {
            let n = words[words.count - 2]
            if let v = Int(n) ?? numbers[n] { return (Array(words.dropLast(2)), min(max(v, 1), 10)) }
        }
        return (words, nil)
    }

    /// "switch to claude" → "claude" for verb "switch to".
    static func argument(_ phrase: String, verbs: [String], trimArticles: Bool = true) -> String? {
        for v in verbs where phrase.hasPrefix(v + " ") {
            var rest = String(phrase.dropFirst(v.count + 1))
            guard trimArticles else { return rest }
            for article in ["the ", "app "] where rest.hasPrefix(article) { rest = String(rest.dropFirst(article.count)) }
            if rest.hasSuffix(" app") { rest = String(rest.dropLast(4)) }
            if !rest.isEmpty { return rest }
        }
        return nil
    }

    // MARK: Apps

    /// Spoken names that don't look like the app's real name.
    static let appAliases: [String: String] = [
        "vs code": "Visual Studio Code", "vscode": "Visual Studio Code", "code": "Visual Studio Code",
        "chrome": "Google Chrome", "browser": "Safari", "mail": "Mail", "email": "Mail",
        "terminal": "Terminal", "settings": "System Settings", "system preferences": "System Settings",
        "finder": "Finder", "files": "Finder", "messages": "Messages", "music": "Music",
        "teams": "Microsoft Teams", "word": "Microsoft Word", "excel": "Microsoft Excel",
        "powerpoint": "Microsoft PowerPoint", "outlook": "Microsoft Outlook",
        "cloud": "Claude", "clod": "Claude", "claud": "Claude",
    ]

    /// The app in `candidates` that best matches what was said, or nil.
    public static func bestApp(for spoken: String, in candidates: [String]) -> String? {
        let q = normalize(spoken)
        guard !q.isEmpty else { return nil }
        let keyed = candidates.map { ($0, normalize($0)) }
        if let exact = keyed.first(where: { $0.1 == q }) { return exact.0 }
        if let alias = appAliases[q], let hit = keyed.first(where: { $0.1 == normalize(alias) }) { return hit.0 }
        // A whole word of the name ("chrome" → "Google Chrome"), shortest name first.
        let byLength = keyed.sorted { $0.1.count < $1.1.count }
        if let word = byLength.first(where: { $0.1.split(separator: " ").contains(Substring(q)) }) { return word.0 }
        if q.count >= 3, let prefix = byLength.first(where: { $0.1.hasPrefix(q) }) { return prefix.0 }
        // Misheard spelling.
        var best: (String, Double)?
        for (name, n) in keyed {
            let s = similarity(q, n)
            if s >= 0.75, s > (best?.1 ?? 0) { best = (name, s) }
        }
        return best?.0
    }

    // MARK: Text distance

    /// 1 − edit distance / longer length.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty || !y.isEmpty else { return 1 }
        var prev = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in stride(from: 1, through: y.count, by: 1) {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        let d = x.isEmpty ? y.count : prev[y.count]
        return 1 - Double(d) / Double(max(x.count, y.count))
    }
}
