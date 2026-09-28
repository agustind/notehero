// Notes live in SQLite, in the same file and schema the tinyjs builds used,
// so upgrading keeps every note.
import Foundation
import SQLite3

struct Note: Identifiable, Equatable {
    let id: Int64
    var body: String
    let created: Int64   // ms since 1970
    var updated: Int64   // ms since 1970
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class NotesDB {
    private var db: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw NSError(domain: "NoteHero", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Can't open \(path)"])
        }
        exec("""
            CREATE TABLE IF NOT EXISTS notes (
              id INTEGER PRIMARY KEY,
              body TEXT NOT NULL DEFAULT '',
              created INTEGER NOT NULL,
              updated INTEGER NOT NULL
            )
            """)
    }

    deinit { sqlite3_close(db) }

    static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func list() -> [Note] {
        query("SELECT id, body, created, updated FROM notes ORDER BY updated DESC")
    }

    func create(body: String) -> Note? {
        let now = Self.now
        return query("INSERT INTO notes (body, created, updated) VALUES (?, ?, ?) RETURNING id, body, created, updated",
                     .text(body), .int(now), .int(now)).first
    }

    func save(id: Int64, body: String) -> Int64 {
        let now = Self.now
        _ = query("UPDATE notes SET body = ?, updated = ? WHERE id = ?", .text(body), .int(now), .int(id))
        return now
    }

    func remove(id: Int64) {
        _ = query("DELETE FROM notes WHERE id = ?", .int(id))
    }

    // MARK: - plumbing

    private enum Arg { case text(String), int(Int64) }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func query(_ sql: String, _ args: Arg...) -> [Note] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        for (i, arg) in args.enumerated() {
            switch arg {
            case .text(let s): sqlite3_bind_text(st, Int32(i + 1), s, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int64(st, Int32(i + 1), n)
            }
        }
        var rows: [Note] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard sqlite3_column_count(st) == 4 else { continue }
            let body = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? ""
            rows.append(Note(id: sqlite3_column_int64(st, 0), body: body,
                             created: sqlite3_column_int64(st, 2), updated: sqlite3_column_int64(st, 3)))
        }
        return rows
    }
}
