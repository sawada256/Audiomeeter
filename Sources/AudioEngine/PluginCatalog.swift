import Foundation
import Combine

struct PluginCatalogEntry: Codable, Identifiable, Equatable {
    var name: String
    var manufacturer: String
    var category: String
    var identifier: String
    var path: String
    var id: String { path + "|" + identifier }
}

private struct PluginScanRecord: Codable {
    var fingerprint: String
    var entries: [PluginCatalogEntry]
    var error: String?
}

@MainActor
final class PluginCatalog: ObservableObject {
    static let shared = PluginCatalog()
    @Published private(set) var entries: [PluginCatalogEntry] = []
    @Published private(set) var scanning = false
    @Published private(set) var progress = ""
    @Published private(set) var failures: [String] = []
    private var records: [String: PluginScanRecord] = [:]
    private var scanTask: Task<Void, Never>?
    private let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VoicemeeterMac/plugin-catalog.json")

    private init() {
        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode([String: PluginScanRecord].self, from: data) {
            records = cache
        }
        publish()
    }

    func cancel() { scanTask?.cancel() }

    func scan(force: Bool = false) {
        guard !scanning else { return }
        guard PluginRuntime.shared.available else { progress = "VST3ホストが利用できません。"; return }
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let bundledHost = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libVMPluginHost.dylib")
        let host = FileManager.default.fileExists(atPath: bundledHost.path) ? bundledHost :
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/plugin-host/libVMPluginHost.dylib")
        scanning = true
        scanTask = Task {
            let paths = await Task.detached(priority: .utility) { Self.discover() }.value
            let pathSet = Set(paths.map(\.path))
            records = records.filter { pathSet.contains($0.key) }
            for (index, url) in paths.enumerated() {
                if Task.isCancelled { break }
                progress = "\(index + 1) / \(paths.count) · \(url.deletingPathExtension().lastPathComponent)"
                let fingerprint = Self.fingerprint(url)
                if !force, records[url.path]?.fingerprint == fingerprint { continue }
                let result = await Task.detached(priority: .utility) {
                    Self.inspect(url, executable: executable, host: host, fingerprint: fingerprint)
                }.value
                records[url.path] = result
                publish()
                save()
            }
            publish()
            save()
            progress = Task.isCancelled ? "スキャンを停止しました" : "\(entries.count) エフェクト · \(failures.count) 件の読込エラー"
            scanning = false
            scanTask = nil
        }
    }

    private func publish() {
        entries = records.values.flatMap(\.entries).filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        failures = records.sorted { $0.key < $1.key }.compactMap { path, record in
            record.error.map { "\(URL(fileURLWithPath: path).lastPathComponent): \($0)" }
        }
    }
    private func save() {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: cacheURL, options: .atomic) }
    }
    nonisolated private static func discover() -> [URL] {
        let manager = FileManager.default
        let roots = [URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3"),
                     manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Audio/Plug-Ins/VST3")]
        var results: [String: URL] = [:]
        for root in roots {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "vst3" {
                results[url.resolvingSymlinksInPath().path] = url.resolvingSymlinksInPath()
                enumerator.skipDescendants()
            }
        }
        return results.values.sorted { $0.path < $1.path }
    }
    nonisolated private static func fingerprint(_ url: URL) -> String {
        let executable = Bundle(url: url)?.executableURL ?? url
        return [url, executable].map {
            let values = try? $0.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0)"
        }.joined(separator: "|")
    }
    nonisolated private static func inspect(_ url: URL, executable: URL, host: URL, fingerprint: String) -> PluginScanRecord {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("vm-scan-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        do {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--scan-vst3", host.path, url.path, outputURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(20)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning {
                process.terminate()
                // A plugin can ignore SIGTERM. Reap it without leaving a scan process behind.
                Thread.sleep(forTimeInterval: 0.1)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                return PluginScanRecord(fingerprint: fingerprint, entries: [], error: "20秒でタイムアウト（再スキャンで再試行）")
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return PluginScanRecord(fingerprint: fingerprint, entries: [], error: "スキャナー終了コード \(process.terminationStatus)")
            }
            let entries = try JSONDecoder().decode([PluginCatalogEntry].self, from: Data(contentsOf: outputURL))
            return PluginScanRecord(fingerprint: fingerprint, entries: entries, error: nil)
        } catch {
            return PluginScanRecord(fingerprint: fingerprint, entries: [], error: error.localizedDescription)
        }
    }
}
