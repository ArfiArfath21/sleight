import AppKit

/// The menu commands of the app in front, read through Accessibility, so
/// "Jarvis, export as PDF" presses File → Export as PDF…. Rebuilt off the main
/// thread whenever another app comes forward.
final class MenuIndex {
    private struct Item { let title: String; let element: AXUIElement }

    private let queue = DispatchQueue(label: "sleight.menus", qos: .utility)
    private let lock = NSLock()
    private var items: [Item] = []
    var onChange: (() -> Void)?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appChanged),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        appChanged()
    }

    var titles: [String] { lock.withLock { items.map(\.title) } }

    /// Presses the item with this title. False if it's gone or disabled.
    @discardableResult
    func press(_ title: String) -> Bool {
        guard let item = lock.withLock({ items.first { $0.title == title } }) else { return false }
        return AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success
    }

    @objc private func appChanged() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let pid = app.processIdentifier
        queue.async { [weak self] in
            let found = Self.read(pid: pid)
            guard let self else { return }
            self.lock.withLock { self.items = found }
            DispatchQueue.main.async { self.onChange?() }
        }
    }

    private static func read(pid: pid_t) -> [Item] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let bar: AXUIElement = attribute(app, kAXMenuBarAttribute) else { return [] }
        var out: [Item] = []
        var seen = Set<String>()
        // Skip the Apple menu: it's the same everywhere and full of risky items.
        for top in children(bar).dropFirst() {
            for menu in children(top) { collect(menu, depth: 0, into: &out, seen: &seen) }
        }
        return out
    }

    private static func collect(_ menu: AXUIElement, depth: Int, into out: inout [Item], seen: inout Set<String>) {
        for item in children(menu) {
            let title: String = attribute(item, kAXTitleAttribute) ?? ""
            let enabled: Bool = attribute(item, kAXEnabledAttribute) ?? false
            let sub = children(item)
            if !sub.isEmpty {
                if depth < 1 { for m in sub { collect(m, depth: depth + 1, into: &out, seen: &seen) } }
            } else if enabled, !title.isEmpty, !seen.contains(title), out.count < 400 {
                seen.insert(title)
                out.append(Item(title: title, element: item))
            }
        }
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] {
        attribute(e, kAXChildrenAttribute) ?? []
    }

    private static func attribute<T>(_ e: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
