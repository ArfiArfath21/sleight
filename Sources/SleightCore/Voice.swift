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
    /// "never mind": close the listening chip without doing anything.
    case cancel
}

/// Turns transcripts into intents. Pure text in, intent out, so it can be
/// tested without a microphone.
///
/// The wake phrase is "hey Sleight". Speech recognisers rarely spell the name
/// right ("hey slight", "hey sleigh", "hey slate"), so close spellings count,
/// but only after a greeting word, so the name alone in conversation doesn't.
public enum VoiceCommands {
    static let greetings: Set<String> = ["hey", "hi", "ok", "okay", "hay"]
    /// What "hey" turns into when heard badly. Too common to count on their own.
    static let weakGreetings: Set<String> = ["he", "a", "eh", "hey's", "high"]
    /// "hey Sleight" heard as one word.
    static let merged: Set<String> = ["heli", "haley", "hailey", "hayley", "halee", "heylight"]
    static let names: Set<String> = [
        "sleight", "slight", "sleigh", "slate", "slay", "sleights", "slights", "sleighs",
        "slates", "slays", "sleit", "sliet", "slait", "sleight's", "slight's",
        "slide", "slides", "slice", "sly", "sleet", "slate's", "slide's",
    ]

    /// Lowercase (unless `keepCase`), no punctuation, single spaces.
    public static func normalize(_ s: String, keepCase: Bool = false) -> String {
        var out = ""
        for ch in keepCase ? s : s.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "'" { out.append(ch) } else { out.append(" ") }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    /// Finds the last "hey Sleight" in `transcript` and returns what follows it
    /// (possibly empty), or nil when there's no wake phrase.
    public static func afterWakePhrase(_ transcript: String) -> String? {
        let words = normalize(transcript, keepCase: true).split(separator: " ").map(String.init)
        let lower = words.map { $0.lowercased() }
        guard words.count >= 2 else { return nil }
        for i in stride(from: words.count - 2, through: 0, by: -1)
        where greetings.contains(lower[i]) && names.contains(lower[i + 1]) {
            return dropLeadingName(words[(i + 2)...].joined(separator: " "))
        }
        return nil
    }

    /// A wake phrase, strong or weak. Weak ones ("he slide", "heli", or the
    /// name at the very start, "slide mission control") only count when a whole
    /// command follows, so everyday speech can't open the listening chip.
    public struct Wake: Equatable, Sendable {
        public let command: String
        public let strong: Bool
    }

    public static func wake(in transcript: String) -> Wake? {
        if let c = afterWakePhrase(transcript) { return Wake(command: c, strong: true) }
        let words = normalize(transcript, keepCase: true).split(separator: " ").map(String.init)
        let lower = words.map { $0.lowercased() }
        func weak(from i: Int) -> Wake? {
            let c = dropLeadingName(words[i...].joined(separator: " "))
            return parse(c) != nil ? Wake(command: c, strong: false) : nil
        }
        for i in stride(from: words.count - 1, through: 0, by: -1) {
            if merged.contains(lower[i]), let w = weak(from: i + 1) { return w }
            if i + 1 < words.count, weakGreetings.contains(lower[i]), names.contains(lower[i + 1]), let w = weak(from: i + 2) { return w }
        }
        if let first = lower.first, names.contains(first), let w = weak(from: 1) { return w }
        return nil
    }

    /// Recognisers revise as they go ("hey slide" → "slide slide scroll down"):
    /// drop greeting and name words from the start of a command.
    public static func dropLeadingName(_ command: String) -> String {
        var words = normalize(command, keepCase: true).split(separator: " ").map(String.init)
        while let first = words.first?.lowercased(),
              names.contains(first) || greetings.contains(first) || weakGreetings.contains(first) || merged.contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    // MARK: Commands

    /// Spoken forms of each action. The first is the one shown in the guide.
    public static let phrases: [(ActionID, [String])] = [
        (.scrollDown, ["scroll down", "down", "page down"]),
        (.scrollUp, ["scroll up", "up", "page up"]),
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
    ]

    static let restPhrases = ["rest", "go to sleep", "sleep", "stop listening", "take a break", "go rest"]
    static let wakePhrases = ["wake up", "wake", "start listening", "i'm back", "im back"]
    static let cancelPhrases = ["cancel", "never mind", "nevermind", "nothing", "forget it"]
    static let pointerPhrases = ["pointer mode", "pointer", "mouse mode", "cursor mode"]
    static let gesturePhrases = ["gesture mode", "gestures", "exit pointer", "leave pointer mode", "stop pointer"]
    /// Words that add nothing ("please scroll down").
    static let filler: Set<String> = ["please", "can", "you", "could", "would", "just", "now", "the", "sleight"]
    static let switchVerbs = ["switch to", "go to", "open", "launch", "show me", "bring up", "start", "focus"]
    static let typeVerbs = ["type", "write", "dictate"]
    static let searchVerbs = ["search for", "search", "look up", "find"]

    /// Parses what came after the wake phrase. nil = not (yet) a command.
    public static func parse(_ command: String) -> VoiceIntent? {
        let raw = normalize(command)
        guard !raw.isEmpty else { return nil }

        // Free text keeps its own words and capitals (no filler stripping).
        let cased = normalize(command, keepCase: true).split(separator: " ")
        func original(_ tail: String) -> String {
            cased.suffix(tail.split(separator: " ").count).joined(separator: " ")
        }
        if let text = argument(raw, verbs: typeVerbs, trimArticles: false) { return .type(original(text)) }
        if let q = argument(raw, verbs: searchVerbs, trimArticles: false) { return .search(original(q)) }

        var words = raw.split(separator: " ").map(String.init)
        let (stripped, times) = repeatCount(words)
        words = stripped.filter { !filler.contains($0) }
        let phrase = words.joined(separator: " ")
        guard !phrase.isEmpty else { return nil }

        if cancelPhrases.contains(phrase) { return .cancel }
        if restPhrases.contains(phrase) { return .rest }
        if wakePhrases.contains(phrase) { return .wake }
        if pointerPhrases.contains(phrase) { return .pointerMode }
        if gesturePhrases.contains(phrase) { return .gestureMode }
        if let a = action(for: phrase) { return .action(a, times: times ?? defaultTimes(a)) }
        if let app = argument(phrase, verbs: switchVerbs) { return .switchTo(app) }
        return nil
    }

    /// Exact phrase first, then a near miss ("scrawl down"), never a guess
    /// between two different actions.
    static func action(for phrase: String) -> ActionID? {
        for (a, forms) in phrases where forms.contains(phrase) { return a }
        guard phrase.count >= 6 else { return nil }
        var best: (ActionID, Double)?
        for (a, forms) in phrases {
            for f in forms where f.count >= 6 {
                let s = similarity(phrase, f)
                if s >= 0.8, s > (best?.1 ?? 0) { best = (a, s) }
            }
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
