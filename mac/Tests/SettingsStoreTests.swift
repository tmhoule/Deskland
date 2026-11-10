import Foundation

@main
struct SettingsStoreTests {
    static func main() throws {
        let registry = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SettingsStore(registry: registry, directory: directory)
        precondition(Set(store.rules.keys) == Set(["beach", "meadow"]))
        precondition(store.params["beach"]?["sigma"] == 85 && store.params["meadow"]?["sigma"] == 72)
        let seeds = [store.params["beach"]!["seed"]!, store.params["meadow"]!["seed"]!]
        try store.set(theme: "beach", key: "sigma", value: 100)
        try store.set(theme: "meadow", key: "showCat", value: 0)
        try store.set(theme: "meadow", key: "adaptive", value: 0)
        try store.select("meadow")
        try store.language("en")
        let loaded = try SettingsStore(registry: registry, directory: directory)
        precondition(loaded.theme == "meadow" && loaded.lang == "en")
        precondition(loaded.params["beach"]?["sigma"] == 100 && loaded.params["meadow"]?["showCat"] == 0 && loaded.params["meadow"]?["adaptive"] == 0)
        precondition(seeds == [loaded.params["beach"]!["seed"]!, loaded.params["meadow"]!["seed"]!])
        for (theme, key, value) in [("lake", "sigma", 100 as Any), ("beach", "unknown", 1), ("beach", "sigma", 201), ("meadow", "showCat", true), ("beach", "sigma", "85"), ("meadow", "cover", Double.nan), ("beach", "seed", -1), ("meadow", "flow", 0.123), ("meadow", "adaptive", 2), ("beach", "adaptive", 1)] {
            precondition(store.validated(theme: theme, key: key, value: value) == nil, "Reject \(theme).\(key): \(value)")
        }
        do { try store.select("lake"); preconditionFailure("Locked theme selected") } catch {}
        do { try store.language("fr"); preconditionFailure("Unsupported locale") } catch {}
        // A failed atomic write must roll back the in-memory transaction as well.
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        do { try loaded.set(theme: "beach", key: "sigma", value: 120); preconditionFailure("Write should fail") } catch {}
        precondition(loaded.params["beach"]?["sigma"] == 100)
        print("Settings store tests passed: defaults, allowlist, bounds/types, persistence, stable seeds, rollback")
    }
}
