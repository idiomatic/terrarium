import Foundation

/// Per-VM state under `vms/<id>/`: `info.json`, `overlay.asif`, `nvram`, `console.log`, `serve.log`, and the control socket.
enum Runtime {
    struct Info: Codable {
        var id: String
        var pid: Int32
        var image: String
        var overlay: String?
        /// The recipe (`install:NAME` or `provision:NAME`), if any.
        var recipe: String?
        var windowed: Bool
        var state: String
        /// The guest's display size in pixels (`1280x800`), as the VNC framebuffer reports it; nil until known.
        var display: String?
        var started: Date
        /// The guest's OS (`windows`, `linux`, or `macos`), once the owner knows it.
        var guest: String?
    }

    static func dir(_ id: String) -> URL { Paths.vms.appendingPathComponent(id, isDirectory: true) }
    static func socketPath(_ id: String) -> String { dir(id).appendingPathComponent("sock").path }

    static func newID() throws -> String {
        try FileManager.default.createDirectory(at: Paths.vms, withIntermediateDirectories: true)
        while true {
            let id = (0..<4).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
            do {
                // Only this user can enter it: it holds password files and the guest's disk.
                try FileManager.default.createDirectory(at: dir(id), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                return id
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
    }

    static func write(_ info: Info) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(info).write(to: dir(info.id).appendingPathComponent("info.json"), options: .atomic)
    }

    static func read(_ id: String) -> Info? {
        guard let data = try? Data(contentsOf: dir(id).appendingPathComponent("info.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Info.self, from: data)
    }

    static func remove(_ id: String) {
        try? FileManager.default.removeItem(at: dir(id))
    }

    /// What is kept of a VM that ended: how and why, for `ps --deceased`.
    struct Deceased: Codable {
        var id: String
        var image: String
        var recipe: String?
        var started: Date
        var died: Date
        /// The owner's exit status: 0 for a VM that stopped cleanly.
        var status: Int32
        var reason: String
    }

    /// The most records kept.
    static let deceasedLimit = 20

    /// Records that `info`'s VM ended, and forgets the oldest records beyond `deceasedLimit`.
    static func bury(_ info: Info, status: Int32, reason: String) {
        let record = Deceased(id: info.id, image: info.image, recipe: info.recipe, started: info.started, died: Date(), status: status, reason: reason)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let folder = Paths.deceased
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? encoder.encode(record).write(to: folder.appendingPathComponent("\(info.id).json"), options: .atomic)
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for old in files.dropFirst(deceasedLimit) { try? FileManager.default.removeItem(at: old) }
    }

    /// The records, newest first.
    static func deceased() -> [Deceased] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.deceased, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? decoder.decode(Deceased.self, from: $0) } }
            .sorted { $0.died > $1.died }
    }

    /// Running VMs. Directories whose process is gone are removed, discarding their overlays.
    static func list() -> [Info] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: Paths.vms.path)) ?? []
        var live: [Info] = []
        for id in ids.sorted() {
            if let info = read(id), processIsAlive(info.pid) {
                live.append(info)
            } else if let attrs = try? FileManager.default.attributesOfItem(atPath: dir(id).path),
                      let made = attrs[.creationDate] as? Date, Date().timeIntervalSince(made) > 5 {
                // An owner that was killed could not say how it ended.
                if let info = read(id) { bury(info, status: 137, reason: "its process is gone: it was killed, or the Mac restarted") }
                remove(id)
            }
        }
        return live.sorted { $0.started < $1.started }
    }

    /// Finds a running VM by ID or unique ID prefix.
    static func resolve(_ reference: String) throws -> Info {
        guard !reference.isEmpty else { throw CLIError.usage("an empty VM ID matches nothing") }
        let matches = list().filter { $0.id.hasPrefix(reference) }
        switch matches.count {
        case 1: return matches[0]
        case 0: throw CLIError.failure("no running VM '\(reference)'")
        default: throw CLIError.failure("'\(reference)' is ambiguous: " + matches.map(\.id).joined(separator: ", "))
        }
    }

    /// The records of VMs that ended, as `ps --deceased` shows them.
    static func deceasedTable() -> String {
        let records = deceased()
        guard !records.isEmpty else { return "" }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stored = (try? Store.list()) ?? []
        let rows = [["ID", "IMAGE", "STARTED", "ENDED", "STATUS", "REASON"]] + records.map {
            [$0.id, Store.displayName($0.image, among: stored), day.string(from: $0.started), day.string(from: $0.died), String($0.status), $0.reason]
        }
        let widths = (0..<5).map { c in rows.map { $0[c].count }.max()! }
        return rows.map { row in
            row.enumerated().map { $0 == 5 ? $1 : $1.padding(toLength: widths[$0], withPad: " ", startingAt: 0) }.joined(separator: "  ")
                .trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    static func table() -> String {
        let vms = list()
        guard !vms.isEmpty else { return "" }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stored = (try? Store.list()) ?? []
        let rows = [["ID", "IMAGE", "STATE", "DISPLAY", "WINDOW", "STARTED"]] + vms.map {
            [$0.id, Store.displayName($0.image, among: stored), $0.state, $0.display ?? "-", $0.windowed ? "yes" : "no", day.string(from: $0.started)]
        }
        let widths = (0..<6).map { c in rows.map { $0[c].count }.max()! }
        return rows.map { row in
            row.enumerated().map { $1.padding(toLength: widths[$0], withPad: " ", startingAt: 0) }.joined(separator: "  ")
                .trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }
}
