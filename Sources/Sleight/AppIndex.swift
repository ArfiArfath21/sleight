import AppKit
import SleightCore

/// Installed and running apps, for "hey Sleight, switch to …".
enum AppIndex {
    struct App { let name: String; let url: URL }

    private static let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                                  "/System/Applications/Utilities", "/System/Library/CoreServices",
                                  NSHomeDirectory() + "/Applications"]

    static func all() -> [App] {
        var seen = Set<String>()
        var apps: [App] = []
        func add(_ name: String, _ url: URL) {
            guard !seen.contains(name) else { return }
            seen.insert(name)
            apps.append(App(name: name, url: url))
        }
        // Running apps first: "switch to" usually means one that's open.
        for r in NSWorkspace.shared.runningApplications where r.activationPolicy == .regular {
            if let name = r.localizedName, let url = r.bundleURL { add(name, url) }
        }
        let fm = FileManager.default
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for item in items where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(item)
                if folder.hasPrefix("/System/Library/CoreServices"), item != "Finder.app" { continue }
                add(url.deletingPathExtension().lastPathComponent, url)
            }
        }
        return apps
    }

    static func names() -> [String] { all().map(\.name) }

    static func find(_ spoken: String) -> App? {
        let apps = all()
        guard let name = VoiceCommands.bestApp(for: spoken, in: apps.map(\.name)) else { return nil }
        return apps.first { $0.name == name }
    }

    static func open(_ app: App) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: cfg)
    }
}
