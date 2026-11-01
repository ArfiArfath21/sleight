import Foundation

/// A modifier key, for "press command shift T" and "hold shift".
public enum KeyModifier: String, CaseIterable, Codable, Sendable {
    case control, option, shift, command, function

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        case .function: return "fn"
        }
    }

    public var title: String { self == .function ? "Fn" : rawValue.capitalized }

    /// Spoken names, as the recogniser writes them.
    static let spoken: [String: KeyModifier] = [
        "command": .command, "commands": .command, "cmd": .command, "cmmd": .command,
        "shift": .shift, "shifts": .shift,
        "option": .option, "options": .option, "alt": .option, "alternate": .option,
        "control": .control, "ctrl": .control, "controls": .control,
        "function": .function, "fn": .function,
    ]
}

/// One key on the keyboard, by a layout-independent name the app turns into a
/// key code ("return", "pageDown", "f5", "t", "comma").
public struct KeyPress: Equatable, Sendable {
    public var key: String
    /// In the order macOS shows them (⌃⌥⇧⌘).
    public var modifiers: [KeyModifier]

    public init(_ key: String, modifiers: [KeyModifier] = []) {
        self.key = key
        self.modifiers = KeyModifier.allCases.filter(modifiers.contains)
    }

    /// "⌘⇧T", "Page down", "⌃C".
    public var label: String { modifiers.map(\.symbol).joined() + Keys.label(key) }
}

/// The keys voice can press, and the words for them.
public enum Keys {
    /// (name, label shown on screen, spoken forms).
    static let named: [(String, String, [String])] = [
        ("return", "Return", ["enter", "return", "enter key", "return key"]),
        ("escape", "Escape", ["escape", "esc", "escape key"]),
        ("tab", "Tab", ["tab", "tab key"]),
        ("space", "Space", ["space", "space bar", "spacebar"]),
        ("delete", "Delete", ["delete", "backspace", "back space", "delete key"]),
        ("forwardDelete", "Forward delete", ["forward delete", "delete forward"]),
        ("up", "↑", ["up", "up arrow", "arrow up", "up key"]),
        ("down", "↓", ["down", "down arrow", "arrow down", "down key"]),
        ("left", "←", ["left", "left arrow", "arrow left", "left key"]),
        ("right", "→", ["right", "right arrow", "arrow right", "right key"]),
        ("home", "Home", ["home", "home key"]),
        ("end", "End", ["end", "end key"]),
        ("pageUp", "Page up", ["page up"]),
        ("pageDown", "Page down", ["page down"]),
        ("comma", ",", ["comma"]),
        ("period", ".", ["period", "dot", "full stop"]),
        ("slash", "/", ["slash", "forward slash"]),
        ("backslash", "\\", ["backslash", "back slash"]),
        ("minus", "-", ["minus", "dash", "hyphen"]),
        ("equals", "=", ["equals", "equal", "plus"]),
        ("semicolon", ";", ["semicolon", "semi colon"]),
        ("quote", "'", ["quote", "apostrophe"]),
        ("grave", "`", ["backtick", "back tick", "grave"]),
        ("leftBracket", "[", ["left bracket", "open bracket"]),
        ("rightBracket", "]", ["right bracket", "close bracket"]),
    ]

    /// Letters as they come back from the recogniser.
    static let letterSounds: [String: String] = [
        "ay": "a", "bee": "b", "be": "b", "see": "c", "sea": "c", "dee": "d", "gee": "g",
        "aitch": "h", "eye": "i", "jay": "j", "kay": "k", "el": "l", "em": "m", "en": "n",
        "oh": "o", "pee": "p", "queue": "q", "cue": "q", "are": "r", "ess": "s", "tea": "t",
        "tee": "t", "you": "u", "vee": "v", "ex": "x", "why": "y", "zee": "z", "zed": "z",
    ]

    static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                              "ten", "eleven", "twelve"]

    /// Every spoken form → key name, longest first so "page down" beats "down".
    static let forms: [String: String] = {
        var m: [String: String] = [:]
        for (name, _, spoken) in named { for s in spoken { m[s] = name } }
        for c in "abcdefghijklmnopqrstuvwxyz" { m[String(c)] = String(c); m["letter \(c)"] = String(c) }
        for (sound, letter) in letterSounds { m[sound] = letter }
        for d in 0...9 { m[String(d)] = String(d); m[numberWords[d]] = String(d) }
        for n in 1...12 {
            for f in ["f\(n)", "f \(n)", "f \(numberWords[n])", "function \(n)"] { m[f] = "f\(n)" }
        }
        return m
    }()

    /// The key a phrase names, or nil.
    public static func key(named phrase: String) -> String? { forms[phrase] }

    /// What to show for a key name.
    public static func label(_ name: String) -> String {
        if let n = named.first(where: { $0.0 == name }) { return n.1 }
        return name.uppercased()
    }

    static let pressVerbs: Set<String> = ["press", "hit", "tap", "push", "key"]
    static let connectors: Set<String> = ["and", "plus", "with"]
    static let releaseAll: Set<String> = ["release", "let go", "release all", "release keys", "release all keys",
                                          "release everything", "let go of everything", "let go of the keys",
                                          "let go of keys", "let go all", "unhold", "stop holding"]

    /// "press command shift t", "hit page down", "control c", "hold shift",
    /// "release shift", "let go". nil = not a key command.
    static func command(_ words: [String], times: Int?) -> VoiceIntent? {
        let phrase = words.joined(separator: " ")
        if releaseAll.contains(phrase) { return .releaseKeys([]) }
        for verb in ["release", "let go of", "let go", "stop holding", "unhold"] where phrase.hasPrefix(verb + " ") {
            let rest = phrase.dropFirst(verb.count + 1).split(separator: " ").map(String.init)
            guard let mods = modifiers(rest), !mods.isEmpty else { return nil }
            return .releaseKeys(mods)
        }
        if words.first == "hold" {
            var rest = Array(words.dropFirst())
            if rest.first == "down" { rest.removeFirst() }
            guard let mods = modifiers(rest), !mods.isEmpty else { return nil }
            return .holdKeys(mods)
        }

        var rest = words[...]
        let verb = rest.first.map(pressVerbs.contains) ?? false
        if verb { rest = rest.dropFirst() }
        var mods: [KeyModifier] = []
        while let w = rest.first {
            if let m = KeyModifier.spoken[w] { mods.append(m); rest = rest.dropFirst(); continue }
            // "plus" between keys joins them; at the end it's the = key.
            if connectors.contains(w), !mods.isEmpty, rest.count > 1 { rest = rest.dropFirst(); continue }
            break
        }
        // Without "press", only a combination counts ("control c"), so a lone
        // word in conversation can't become a key press.
        guard verb || !mods.isEmpty else { return nil }
        var keyWords = rest.joined(separator: " ")
        if keyWords.hasSuffix(" key"), forms[keyWords] == nil { keyWords = String(keyWords.dropLast(4)) }
        guard let key = forms[keyWords] else { return nil }
        return .pressKey(KeyPress(key, modifiers: mods), times: times ?? 1)
    }

    /// "command and shift" → [.command, .shift]; nil if anything else is in there.
    static func modifiers(_ words: [String]) -> [KeyModifier]? {
        var out: [KeyModifier] = []
        for w in words {
            if connectors.contains(w) || w == "the" || w == "key" || w == "keys" { continue }
            guard let m = KeyModifier.spoken[w] else { return nil }
            if !out.contains(m) { out.append(m) }
        }
        return KeyModifier.allCases.filter(out.contains)
    }
}
