import AppKit
import AVFoundation
import ApplicationServices

// Temporary permission stub: requests Camera + Accessibility so grants are in
// place (tied to the signing identity + bundle ID) before the real app lands.

let app = NSApplication.shared
app.setActivationPolicy(.regular)

func statusText() -> String {
    let cam: String
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: cam = "granted"
    case .denied: cam = "DENIED"
    case .restricted: cam = "restricted"
    case .notDetermined: cam = "not asked yet"
    @unknown default: cam = "unknown"
    }
    let ax = AXIsProcessTrusted() ? "granted" : "NOT granted"
    return "Camera: \(cam)\nAccessibility: \(ax)"
}

func writeStatus() {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Maestro", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? statusText().write(to: dir.appendingPathComponent("permissions.txt"), atomically: true, encoding: .utf8)
}

AVCaptureDevice.requestAccess(for: .video) { _ in
    DispatchQueue.main.async {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        _ = CGRequestPostEventAccess()
        writeStatus()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in writeStatus() }

        let alert = NSAlert()
        alert.messageText = "Maestro permissions"
        alert.informativeText = statusText() + "\n\nGrant Accessibility in System Settings → Privacy & Security → Accessibility, then press Re-check."
        alert.addButton(withTitle: "Re-check")
        alert.addButton(withTitle: "Done")
        app.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            writeStatus()
            alert.informativeText = statusText() + "\n\nGrant Accessibility in System Settings → Privacy & Security → Accessibility, then press Re-check."
        }
        writeStatus()
        app.terminate(nil)
    }
}

app.run()
