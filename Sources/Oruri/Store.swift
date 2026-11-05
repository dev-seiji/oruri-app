import Foundation
import Security

/// Persistência simples em ~/Library/Application Support/Oruri.
enum Store {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Oruri", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let recordingsDirectory: URL = {
        let dir = directory.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let settingsKey = "settings.v1"
    private static var historyURL: URL { directory.appendingPathComponent("history.json") }
    private static var dictionaryURL: URL { directory.appendingPathComponent("dictionary.json") }

    // MARK: Settings

    static func loadSettings() -> Settings {
        let fallback = Settings()
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(fallback),
              let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return fallback }
        // Mescla com os padrões: campos novos ganham o valor padrão em vez de invalidar tudo.
        let merged = defaults.merging(saved) { _, new in new }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let settings = try? JSONDecoder().decode(Settings.self, from: mergedData)
        else { return fallback }
        return settings
    }

    static func saveSettings(_ settings: Settings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    // MARK: Usage

    private static let groqUsageKey = "usage.groq.v1"

    static func loadGroqUsage() -> GroqUsage {
        guard let data = UserDefaults.standard.data(forKey: groqUsageKey),
              let usage = try? JSONDecoder().decode(GroqUsage.self, from: data) else { return GroqUsage() }
        return usage
    }

    static func saveGroqUsage(_ usage: GroqUsage) {
        if let data = try? JSONEncoder().encode(usage) { UserDefaults.standard.set(data, forKey: groqUsageKey) }
    }

    // MARK: Dictionary

    static func loadDictionary() -> [DictionaryEntry] { load([DictionaryEntry].self, from: dictionaryURL) ?? [] }
    static func saveDictionary(_ entries: [DictionaryEntry]) { save(entries, to: dictionaryURL) }

    // MARK: History

    static func loadHistory() -> [Recording] {
        var items = load([Recording].self, from: historyURL) ?? []
        // Algo que ficou "processing" quando o app fechou não vai terminar sozinho.
        for i in items.indices where items[i].status == .processing {
            items[i].status = .failed
            items[i].error = "Interrupted when Oruri closed. Retry from History."
        }
        return items
    }

    static func saveHistory(_ items: [Recording], enabled: Bool) {
        if enabled {
            save(items, to: historyURL)
        } else {
            try? FileManager.default.removeItem(at: historyURL)
        }
    }

    static func audioURL(for recording: Recording) -> URL? {
        recording.audioFile.map { recordingsDirectory.appendingPathComponent($0) }
    }

    /// Apaga as gravações que nenhum item do histórico usa (sobras de falhas, do app fechado no meio, ou com o histórico desligado).
    static func purgeOrphanAudio(keeping recordings: [Recording]) {
        let used = Set(recordings.compactMap(\.audioFile))
        let files = (try? FileManager.default.contentsOfDirectory(at: recordingsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !used.contains(file.lastPathComponent) { try? FileManager.default.removeItem(at: file) }
    }

    static func deleteAudio(for recording: Recording) {
        if let url = audioURL(for: recording) { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Helpers

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Chaves de API guardadas no Keychain (nunca em UserDefaults nem no código).
enum Keychain {
    private static let service = "com.seiji.oruri"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
