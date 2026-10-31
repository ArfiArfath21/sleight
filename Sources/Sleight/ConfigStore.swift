import Foundation
import Combine
import SleightCore

/// Persists the config to ~/Library/Application Support/Sleight/config.json and
/// pushes every change to the pipeline.
final class ConfigStore: ObservableObject {
    @Published var config: SleightConfig {
        didSet {
            guard config != oldValue else { return }
            onChange?(config)
            scheduleSave()
        }
    }
    @Published var preferredCameraID: String? {
        didSet { UserDefaults.standard.set(preferredCameraID, forKey: "preferredCameraID") }
    }
    @Published var showStats: Bool {
        didSet { UserDefaults.standard.set(showStats, forKey: "showStats") }
    }
    @Published var showHints: Bool {
        didSet { UserDefaults.standard.set(showHints, forKey: "showHints") }
    }

    var onChange: ((SleightConfig) -> Void)?
    private var saveWork: DispatchWorkItem?

    static var fileURL: URL { Pipeline.supportDirectory.appendingPathComponent("config.json") }

    init() {
        if let data = try? Data(contentsOf: ConfigStore.fileURL), let cfg = try? SleightConfig.decode(from: data) {
            config = cfg
        } else {
            config = SleightConfig()
        }
        preferredCameraID = UserDefaults.standard.string(forKey: "preferredCameraID")
        showStats = UserDefaults.standard.bool(forKey: "showStats")
        showHints = UserDefaults.standard.object(forKey: "showHints") as? Bool ?? true
    }

    func reset() { config = SleightConfig() }

    private func scheduleSave() {
        saveWork?.cancel()
        let cfg = config
        let work = DispatchWorkItem {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? enc.encode(cfg) { try? data.write(to: ConfigStore.fileURL, options: .atomic) }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
