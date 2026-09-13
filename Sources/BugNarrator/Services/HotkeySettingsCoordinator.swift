import Foundation

struct HotkeySettingsSnapshot {
    var startRecording: HotkeyShortcut
    var stopRecording: HotkeyShortcut
    var captureScreenshot: HotkeyShortcut

    subscript(action: HotkeyAction) -> HotkeyShortcut {
        get {
            switch action {
            case .startRecording: startRecording
            case .stopRecording: stopRecording
            case .captureScreenshot: captureScreenshot
            }
        }
        set {
            switch action {
            case .startRecording: startRecording = newValue
            case .stopRecording: stopRecording = newValue
            case .captureScreenshot: captureScreenshot = newValue
            }
        }
    }
}

struct HotkeySettingsConflict {
    let action: HotkeyAction
    let shortcut: HotkeyShortcut
}

final class HotkeySettingsCoordinator {
    struct Keys {
        let startRecording: String
        let legacyRecording: String
        let legacyStartRecording: String
        let stopRecording: String
        let obsoleteMarker: String
        let captureScreenshot: String
        let didMigrateLegacyBuiltIns: String
    }

    private let defaults: UserDefaults
    private let legacyDefaultsDomains: [String]
    private let keys: Keys
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = DiagnosticsLogger(category: .settings)

    init(defaults: UserDefaults, legacyDefaultsDomains: [String], keys: Keys) {
        self.defaults = defaults
        self.legacyDefaultsDomains = legacyDefaultsDomains
        self.keys = keys
    }

    func loadAndNormalize() -> HotkeySettingsSnapshot {
        var snapshot = HotkeySettingsSnapshot(
            startRecording: load(key: keys.startRecording, legacyKeys: [keys.legacyStartRecording, keys.legacyRecording]),
            stopRecording: load(key: keys.stopRecording, legacyKeys: []),
            captureScreenshot: load(key: keys.captureScreenshot, legacyKeys: [])
        )

        removeObsoleteMarkerIfNeeded()
        migrateLegacyBuiltInsIfNeeded(snapshot: &snapshot)
        normalizeConflicts(snapshot: &snapshot)
        return snapshot
    }

    func persistChange(
        action: HotkeyAction,
        previousShortcut: HotkeyShortcut,
        snapshot: HotkeySettingsSnapshot
    ) -> HotkeySettingsConflict? {
        let changedShortcut = snapshot[action]
        if changedShortcut.isEnabled,
           let conflictingAction = HotkeyAction.allCases.first(where: {
               $0 != action && snapshot[$0] == changedShortcut
           }) {
            persist(previousShortcut, for: action)
            logger.warning(
                "hotkey_conflict_rejected",
                "A conflicting hotkey assignment was rejected.",
                metadata: [
                    "action": action.title,
                    "conflict_action": conflictingAction.title,
                    "shortcut": changedShortcut.displayString
                ]
            )
            return HotkeySettingsConflict(action: conflictingAction, shortcut: changedShortcut)
        }

        persist(changedShortcut, for: action)
        return nil
    }

    private func load(key: String, legacyKeys: [String]) -> HotkeyShortcut {
        if let data = dataValue(forKey: key),
           let shortcut = try? decoder.decode(HotkeyShortcut.self, from: data) {
            return shortcut
        }

        for legacyKey in legacyKeys {
            if let data = dataValue(forKey: legacyKey),
               let shortcut = try? decoder.decode(HotkeyShortcut.self, from: data) {
                defaults.set(data, forKey: key)
                return shortcut
            }
        }
        return .disabled
    }

    private func migrateLegacyBuiltInsIfNeeded(snapshot: inout HotkeySettingsSnapshot) {
        guard defaults.object(forKey: keys.didMigrateLegacyBuiltIns) == nil else { return }
        var clearedActions: [String] = []

        for action in HotkeyAction.allCases {
            guard let legacyShortcut = action.legacyBuiltInShortcut,
                  snapshot[action] == legacyShortcut else { continue }
            snapshot[action] = .disabled
            persist(.disabled, for: action)
            clearedActions.append(action.title)
        }

        defaults.set(true, forKey: keys.didMigrateLegacyBuiltIns)
        if !clearedActions.isEmpty {
            logger.info(
                "legacy_hotkey_defaults_cleared",
                "Cleared previously built-in hotkey defaults so shortcuts start unassigned.",
                metadata: ["cleared_actions": clearedActions.joined(separator: ",")]
            )
        }
    }

    private func normalizeConflicts(snapshot: inout HotkeySettingsSnapshot) {
        var seen = Set<HotkeyShortcut>()
        for action in HotkeyAction.allCases {
            let shortcut = snapshot[action]
            if shortcut.isEnabled && seen.contains(shortcut) {
                snapshot[action] = .disabled
            } else if shortcut.isEnabled {
                seen.insert(shortcut)
            }
            persist(snapshot[action], for: action)
        }
    }

    private func removeObsoleteMarkerIfNeeded() {
        guard defaults.object(forKey: keys.obsoleteMarker) != nil else { return }
        defaults.removeObject(forKey: keys.obsoleteMarker)
        logger.info(
            "removed_obsolete_marker_hotkey",
            "Removed the obsolete standalone marker hotkey assignment during settings load."
        )
    }

    private func persist(_ shortcut: HotkeyShortcut, for action: HotkeyAction) {
        guard let data = try? encoder.encode(shortcut) else { return }
        defaults.set(data, forKey: storageKey(for: action))
    }

    private func storageKey(for action: HotkeyAction) -> String {
        switch action {
        case .startRecording: keys.startRecording
        case .stopRecording: keys.stopRecording
        case .captureScreenshot: keys.captureScreenshot
        }
    }

    private func dataValue(forKey key: String) -> Data? {
        if let data = defaults.data(forKey: key) { return data }
        for domainName in legacyDefaultsDomains {
            guard let domain = defaults.persistentDomain(forName: domainName),
                  let data = domain[key] as? Data else { continue }
            defaults.set(data, forKey: key)
            return data
        }
        return nil
    }
}
