import Foundation
import Darwin
import ImageIO
import UniformTypeIdentifiers

@MainActor public final class ConversationStore {
    public let root: URL
    public private(set) var warnings: [String] = []
    private var conversations: [UUID: Conversation] = [:]
    private var index: SearchIndex?
    private var lockFD: Int32 = -1
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fm = FileManager.default

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AFMChat", isDirectory: true)
    }
    public init(root: URL) throws {
        self.root = root
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        try fm.createDirectory(at: root, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        lockFD = open(root.appendingPathComponent("writer.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { throw ChatError.storage("無法開啟資料目錄鎖") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            close(lockFD); lockFD = -1; throw ChatError.alreadyOpen
        }
        do {
            let sessions = root.appendingPathComponent("conversations", isDirectory: true)
            try fm.createDirectory(at: sessions, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            for dir in try fm.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil) {
                guard let id = UUID(uuidString: dir.lastPathComponent) else { continue }
                do { conversations[id] = try read(id) }
                catch { warnings.append("\(id.uuidString.prefix(8))：\(error.localizedDescription)") }
            }
            try rebuildIndex()
        } catch {
            close(lockFD); lockFD = -1; throw error
        }
    }
    deinit { if lockFD >= 0 { close(lockFD) } }

    public func list(search: String = "") -> [ConversationInfo] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? nil : try? index?.matchingIDs(query)
        return conversations.values.filter { c in
            if query.isEmpty { return true }
            if let matching { return matching.contains(c.id) }
            return c.title.localizedCaseInsensitiveContains(query)
                || c.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }.sorted { $0.updatedAt > $1.updatedAt }.map {
            .init(id: $0.id, title: $0.title, updatedAt: $0.updatedAt,
                  preview: String($0.messages.last?.text.prefix(100) ?? ""))
        }
    }
    public func conversation(_ id: UUID) throws -> Conversation {
        guard let value = conversations[id] else { throw ChatError.storage("找不到對話") }
        return value
    }
    @discardableResult public func create(title: String = "新對話") throws -> UUID {
        let id = UUID()
        try fm.createDirectory(at: directory(id), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        conversations[id] = Conversation(id: id, title: title, events: [])
        do { try append(id, event: .init(kind: .created, text: title)) }
        catch { conversations.removeValue(forKey: id); try? fm.removeItem(at: directory(id)); throw error }
        return id
    }
    public func rename(_ id: UUID, title: String) throws {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !title.isEmpty else { return }
        try append(id, event: .init(kind: .renamed, text: title))
    }
    public func delete(_ id: UUID) throws {
        _ = try conversation(id)
        // Move out of the replay directory first. A crash cannot resurrect a deleted conversation.
        let trash = root.appendingPathComponent("deleted-\(id.uuidString)")
        try fm.moveItem(at: directory(id), to: trash)
        conversations.removeValue(forKey: id)
        do { try fm.removeItem(at: trash) }
        catch { warnings.append("對話已從清單移除，但部分刪除檔案仍留在資料目錄：\(error.localizedDescription)") }
        do { try index?.rebuild(Array(conversations.values)) }
        catch { index = nil; warnings.append("搜尋索引暫時無法更新；刪除已完成。") }
    }
    public func append(_ id: UUID, event incoming: ChatEvent) throws {
        var conversation = try conversation(id)
        var event = incoming
        event.sequence = (conversation.events.last?.sequence ?? 0) + 1
        try validate(event, previous: conversation.events)
        var bytes = try encoder.encode(event); bytes.append(0x0A)
        let path = directory(id).appendingPathComponent("events.jsonl")
        if !fm.fileExists(atPath: path.path) {
            guard fm.createFile(atPath: path.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw ChatError.storage("無法建立對話檔案")
            }
        }
        let handle = try FileHandle(forWritingTo: path)
        defer { try? handle.close() }
        let oldSize = try handle.seekToEnd()
        do { try handle.write(contentsOf: bytes); try handle.synchronize() }
        catch { try? handle.truncate(atOffset: oldSize); try? handle.synchronize(); throw error }
        conversation.events.append(event)
        if event.kind == .created || event.kind == .renamed { conversation.title = event.text ?? conversation.title }
        conversations[id] = conversation
        // A projection failure must not make the caller retry an already durable event.
        do { try index?.update(conversation) }
        catch { index = nil; warnings.append("搜尋索引暫時無法更新；JSONL 已保存，下次啟動會重建。") }
    }
    public func saveImage(_ data: Data, conversationID: UUID) throws -> String {
        _ = try conversation(conversationID)
        guard data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_384, height <= 16_384,
              width * height <= 40_000_000 else { throw ChatError.storage("請選擇 20 MB、4,000 萬像素以內的有效圖片。") }
        let ext = UTType(type as String)?.preferredFilenameExtension ?? "image"
        let relative = "attachments/\(UUID().uuidString).\(ext)"
        let target = try imageURL(relative, conversationID: conversationID)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try data.write(to: target, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return relative
    }
    public func imageURL(_ relative: String, conversationID: UUID) throws -> URL {
        guard relative.hasPrefix("attachments/"), !relative.contains(".."),
              !relative.hasPrefix("/"), relative.split(separator: "/").count == 2 else {
            throw ChatError.invalidLog("圖片路徑不合法")
        }
        let base = directory(conversationID).resolvingSymlinksInPath()
        let target = base.appendingPathComponent(relative).resolvingSymlinksInPath()
        guard target.path.hasPrefix(base.path + "/") else { throw ChatError.invalidLog("圖片路徑超出對話資料夾") }
        return target
    }
    public func rebuildIndex() throws {
        index = nil
        let url = root.appendingPathComponent("index.sqlite")
        do { index = try SearchIndex(url: url); try index?.rebuild(Array(conversations.values)) }
        catch {
            index = nil
            let suffix = ".recovery-" + UUID().uuidString
            for ext in ["", "-wal", "-shm"] {
                let file = URL(fileURLWithPath: url.path + ext)
                if fm.fileExists(atPath: file.path) { try fm.moveItem(at: file, to: URL(fileURLWithPath: file.path + suffix)) }
            }
            index = try SearchIndex(url: url)
            try index?.rebuild(Array(conversations.values))
            warnings.append("搜尋索引已從 JSONL 重建；舊索引另存於資料目錄。")
        }
    }
    private func directory(_ id: UUID) -> URL {
        root.appendingPathComponent("conversations/\(id.uuidString)", isDirectory: true)
    }
    private func read(_ id: UUID) throws -> Conversation {
        let file = directory(id).appendingPathComponent("events.jsonl")
        var bytes = try Data(contentsOf: file)
        var repaired = false
        var partial: Data?
        if !bytes.isEmpty && bytes.last != 0x0A {
            let start = bytes.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
            let tail = bytes.subdata(in: start..<bytes.count)
            if (try? decoder.decode(ChatEvent.self, from: tail)) != nil {
                bytes.append(0x0A)
            } else {
                partial = tail
                bytes = bytes.subdata(in: 0..<start)
            }
            repaired = true
        }
        var events: [ChatEvent] = []
        for line in bytes.split(separator: 0x0A) {
            let event: ChatEvent
            do { event = try decoder.decode(ChatEvent.self, from: Data(line)) }
            catch { throw ChatError.invalidLog("第 \(events.count + 1) 筆 JSON 無法解析，檔案未被改寫。") }
            try validate(event, previous: events)
            events.append(event)
        }
        guard events.first?.kind == .created else { throw ChatError.invalidLog("缺少對話起始紀錄") }
        // Validate every complete event before repairing a tail, so corrupt logs remain untouched.
        if repaired {
            if let partial {
                try partial.write(to: directory(id).appendingPathComponent("partial-\(UUID().uuidString).recovery"))
                warnings.append("\(id.uuidString.prefix(8))：已隔離最後一筆未寫完的紀錄。")
            }
            try bytes.write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        let title = events.last { $0.kind == .created || $0.kind == .renamed }?.text ?? "對話"
        return Conversation(id: id, title: title, events: events)
    }
    private func validate(_ event: ChatEvent, previous: [ChatEvent]) throws {
        guard event.version == 1, event.sequence == (previous.last?.sequence ?? 0) + 1,
              !previous.contains(where: { $0.id == event.id }) else {
            throw ChatError.invalidLog("版本、序號或事件識別碼不一致")
        }
        if event.kind == .message {
            guard let m = event.message, !previous.contains(where: { $0.message?.id == m.id }) else {
                throw ChatError.invalidLog("訊息重複或缺少內容")
            }
        } else if event.message != nil { throw ChatError.invalidLog("事件種類與訊息內容不一致") }
        if event.kind == .compactionCompleted {
            guard let c = event.compaction, !c.summary.isEmpty,
                  previous.contains(where: { $0.message?.id == c.throughMessageID }) else {
                throw ChatError.invalidLog("摘要缺少有效的涵蓋範圍")
            }
        } else if event.compaction != nil { throw ChatError.invalidLog("摘要事件種類不一致") }
    }
}
