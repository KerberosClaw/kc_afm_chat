import Foundation
import CSQLite

final class SearchIndex {
    private var db: OpaquePointer?
    init(url: URL) throws {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            let error = failure(); sqlite3_close(db); db = nil; throw error
        }
        do {
            try execute("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
            try execute("""
                CREATE TABLE IF NOT EXISTS conversations (
                  id TEXT PRIMARY KEY, title TEXT NOT NULL, updated REAL NOT NULL, preview TEXT NOT NULL);
                CREATE VIRTUAL TABLE IF NOT EXISTS messages USING fts5(conversation_id UNINDEXED, body);
                """)
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }

    private func failure() -> ChatError {
        .storage(db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite unavailable")
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func run(_ sql: String, values: [String]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        for (index, value) in values.enumerated() {
            let result = value.withCString { sqlite3_bind_text(stmt, Int32(index + 1), $0, -1,
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { throw failure() }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    func rebuild(_ conversations: [Conversation]) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try execute("DELETE FROM conversations; DELETE FROM messages;")
            for conversation in conversations { try project(conversation) }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }
    func update(_ conversation: Conversation) throws {
        try execute("BEGIN IMMEDIATE;")
        do { try project(conversation); try execute("COMMIT;") }
        catch { try? execute("ROLLBACK;"); throw error }
    }
    private func project(_ c: Conversation) throws {
        try run("INSERT OR REPLACE INTO conversations VALUES(?,?,?,?);", values: [
            c.id.uuidString, c.title, String(c.updatedAt.timeIntervalSince1970),
            String(c.messages.last?.text.prefix(100) ?? "")])
        try run("DELETE FROM messages WHERE conversation_id=?;", values: [c.id.uuidString])
        for message in c.messages where !message.text.isEmpty {
            try run("INSERT INTO messages(conversation_id,body) VALUES(?,?);",
                    values: [c.id.uuidString, message.text])
        }
    }
    func matchingIDs(_ query: String) throws -> Set<UUID> {
        // LIKE also supports Chinese substring queries without depending on a tokenizer.
        let escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        var stmt: OpaquePointer?
        let sql = #"""
            SELECT id FROM conversations WHERE title LIKE ? ESCAPE '\'
            UNION SELECT conversation_id FROM messages WHERE body LIKE ? ESCAPE '\';
            """#
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        for i: Int32 in [1, 2] {
            _ = ("%" + escaped + "%").withCString {
                sqlite3_bind_text(stmt, i, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
        var result = Set<UUID>()
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let value = sqlite3_column_text(stmt, 0) else { throw failure() }
            if let id = UUID(uuidString: String(cString: value)) { result.insert(id) }
        }
    }
}
