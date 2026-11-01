import Foundation
import SleightCore

/// The user's Apple Shortcuts, for "Jarvis, run Morning Routine". Listed once
/// in the background (and again when asked for one we don't know).
final class ShortcutsIndex {
    static let shared = ShortcutsIndex()
    private let lock = NSLock()
    private var names: [String] = []

    private init() { refresh() }

    var all: [String] { lock.withLock { names } }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.shell(["list"]).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            self?.lock.withLock { self?.names = found }
        }
    }

    func find(_ spoken: String) -> String? {
        let hit = VoiceCommands.bestApp(for: spoken, in: all)
        if hit == nil { refresh() }
        return hit
    }

    static func run(_ name: String) {
        DispatchQueue.global(qos: .userInitiated).async { _ = shell(["run", name]) }
    }

    @discardableResult
    private static func shell(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
