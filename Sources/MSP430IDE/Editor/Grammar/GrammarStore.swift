import Foundation

/// Loads TextMate grammars from disk on first access.
///
/// Lookup order (last wins, so users can override bundled grammars):
///   1. App bundle `Grammars/*.tmLanguage.json` (resources shipped with the IDE)
///   2. `~/Library/Application Support/MSP430IDE/Grammars/*.tmLanguage.json`
///
/// Index is built from each grammar's `fileTypes` field. To add a new
/// language, drop a `.tmLanguage.json` file in either location whose
/// `fileTypes` lists the relevant extensions.
final class GrammarStore {
    static let shared = GrammarStore()

    private(set) var grammarsByExtension: [String: TMGrammar] = [:]
    private var loaded = false
    private let lock = NSLock()

    func grammar(forExtension ext: String) -> TMGrammar? {
        ensureLoaded()
        return grammarsByExtension[ext.lowercased()]
    }

    func reload() {
        lock.lock()
        defer { lock.unlock() }
        loaded = false
        grammarsByExtension = [:]
        loadLocked()
    }

    var userGrammarsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("MSP430IDE/Grammars", isDirectory: true)
    }

    private func ensureLoaded() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loadLocked()
    }

    private func loadLocked() {
        var index: [String: TMGrammar] = [:]

        // 1. Bundle's Grammars/ resource directory
        if let bundleURL = Bundle.module.resourceURL?.appendingPathComponent("Grammars", isDirectory: true) {
            mergeGrammars(at: bundleURL, into: &index)
        }

        // 2. User dir (overrides bundle)
        let userURL = userGrammarsDirectory
        if FileManager.default.fileExists(atPath: userURL.path) {
            mergeGrammars(at: userURL, into: &index)
        }

        grammarsByExtension = index
        loaded = true
    }

    private func mergeGrammars(at directory: URL, into index: inout [String: TMGrammar]) {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for url in entries where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let grammar = try JSONDecoder().decode(TMGrammar.self, from: data)
                for ext in grammar.fileTypes ?? [] {
                    index[ext.lowercased()] = grammar
                }
            } catch {
                FileHandle.standardError.write("GrammarStore: failed to load \(url.lastPathComponent): \(error)\n".data(using: .utf8) ?? Data())
            }
        }
    }
}
