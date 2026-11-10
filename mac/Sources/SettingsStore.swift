import Foundation
import CoreFoundation

/// The registry is the sole source of parameter bounds/defaults. Unknown keys never reach WebKit.
final class SettingsStore {
    struct Rule { let initial: Double; let min: Double; let max: Double; let step: Double }
    private(set) var rules: [String: [String: Rule]] = [:]
    private(set) var theme = "beach"
    private(set) var lang = "auto"
    private(set) var params: [String: [String: Double]] = [:]
    let file: URL

    init(registry: URL, directory: URL) throws {
        file = directory.appendingPathComponent("settings.json")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: registry)) as? [String: Any]
        for item in root?["themes"] as? [[String: Any]] ?? [] {
            guard let id = item["id"] as? String, ["beach", "meadow"].contains(id), item["status"] as? String == "ready" else { continue }
            var entries: [String: Rule] = [:]
            for group in item["groups"] as? [[String: Any]] ?? [] {
                for p in group["params"] as? [[String: Any]] ?? [] {
                    guard let key = p["key"] as? String, let initial = p["default"] as? Double else { continue }
                    let options = p["options"] as? [String]
                    entries[key] = Rule(initial: initial, min: p["min"] as? Double ?? 0,
                                        max: p["max"] as? Double ?? Double(max(0, (options?.count ?? 1) - 1)), step: p["step"] as? Double ?? 1)
                }
            }
            if item["adaptive"] as? Bool == true {
                entries["adaptive"] = Rule(initial: 1, min: 0, max: 1, step: 1)
            }
            entries["seed"] = Rule(initial: Double(UInt32.random(in: 1...UInt32.max)), min: 0, max: Double(UInt32.max), step: 1)
            rules[id] = entries
            params[id] = entries.mapValues { $0.initial }
        }
        guard rules.count == 2 else { throw NSError(domain: "DesklandRegistry", code: 1) }
        if let data = try? Data(contentsOf: file), let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let id = saved["theme"] as? String, rules[id] != nil { theme = id }
            if let value = saved["lang"] as? String, ["auto", "en", "zh-CN"].contains(value) { lang = value }
            for (id, values) in saved["params"] as? [String: [String: Any]] ?? [:] {
                for (key, value) in values { if let n = validated(theme: id, key: key, value: value) { params[id]?[key] = n } }
            }
        }
        // Persist newly generated seeds once, not at every page load.
        try persist()
    }
    func validated(theme: String, key: String, value: Any) -> Double? {
        guard let rule = rules[theme]?[key], let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let n = number.doubleValue
        guard n.isFinite, n >= rule.min, n <= rule.max else { return nil }
        let ticks = (n - rule.min) / rule.step
        guard abs(ticks - ticks.rounded()) < 0.00001 else { return nil }
        return n
    }
    func select(_ id: String) throws {
        guard rules[id] != nil else { throw NSError(domain: "DesklandTheme", code: 1) }
        let old = theme; theme = id
        do { try persist() } catch { theme = old; throw error }
    }
    func set(theme id: String, key: String, value: Any) throws {
        guard let n = validated(theme: id, key: key, value: value) else { throw NSError(domain: "DesklandParameter", code: 1) }
        let old = params; params[id]?[key] = n
        do { try persist() } catch { params = old; throw error }
    }
    func language(_ value: String) throws {
        guard ["auto", "en", "zh-CN"].contains(value) else { throw NSError(domain: "DesklandLanguage", code: 1) }
        let old = lang; lang = value
        do { try persist() } catch { lang = old; throw error }
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "theme": theme, "lang": lang, "params": params], options: [.sortedKeys, .prettyPrinted])
        try data.write(to: file, options: .atomic)
    }
}
