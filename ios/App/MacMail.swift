#if os(macOS) && DEBUG
import Foundation

/// Mail.app on this Mac, driven over Apple Events. Debug builds only: the store build has no Apple Events entitlement.
/// Mail stays on the Mac; only sender and subject go to /api/sort.
/// Gmail accounts are skipped: Mail.app's move only copies into a Gmail label and the mail stays in the inbox,
/// so Gmail is cleared through the Gmail connection instead.
enum MacMail {
    private static let sep = "\u{1F}", rowSep = "\u{1E}"

    private static func run(_ source: String) throws -> String {
        var err: NSDictionary?
        let out = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { throw APIError(message: "Mail: \(err[NSAppleScript.errorMessage] ?? err)") }
        return out?.stringValue ?? ""
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    struct Account: Identifiable { let name: String; let email: String; let count: Int; let isGmail: Bool; var id: String { name } }

    /// Every account Mail.app knows, with its inbox size. Gmail ones are listed but cannot be cleared from here.
    static func accounts() throws -> [Account] {
        let out = try run("""
        set us to (ASCII character 31)
        set rs to (ASCII character 30)
        set out to ""
        tell application "Mail"
            repeat with a in every account
                set n to 0
                try
                    set n to count of messages of mailbox "INBOX" of a
                end try
                set out to out & (name of a) & us & (server name of a) & us & n & us & (user name of a) & rs
            end repeat
        end tell
        return out
        """)
        return out.components(separatedBy: rowSep).compactMap { row in
            let f = row.components(separatedBy: sep)
            return f.count == 4 ? Account(name: f[0], email: f[3], count: Int(f[2]) ?? 0, isGmail: f[1].lowercased().contains("gmail")) : nil
        }
    }

    /// Every inbox message in every non-Gmail account. The id is "account<US>message id".
    static func inbox() throws -> [MailItem] {
        let out = try run("""
        set us to (ASCII character 31)
        set rs to (ASCII character 30)
        set out to ""
        tell application "Mail"
            repeat with a in every account
                if (server name of a) does not contain "gmail" then
                    try
                        repeat with m in (every message of mailbox "INBOX" of a)
                            set out to out & (name of a) & us & (id of m) & us & (sender of m) & us & (subject of m) & rs
                        end repeat
                    end try
                end if
            end repeat
        end tell
        return out
        """)
        return out.components(separatedBy: rowSep).compactMap { row in
            let f = row.components(separatedBy: sep)
            return f.count == 4 ? MailItem(id: f[0] + sep + f[1], from: f[2], subject: f[3]) : nil
        }
    }

    /// Files each message into Mailbag/<folder> in its own account; mail from people goes to Archive. Nothing is deleted.
    /// Returns how many of each kind really moved, counted by Mail itself, since any single move can fail.
    static func clear(_ messages: [Message]) throws -> (filed: Int, archived: Int) {
        var lines: [String] = []
        for m in messages {
            let f = m.id.components(separatedBy: sep)
            guard f.count == 2, let mid = Int(f[1]) else { continue }
            let acct = "account \(quoted(f[0]))"
            let dest = m.folder.map { "mailbox \(quoted($0)) of mailbox \"Mailbag\" of \(acct)" } ?? "mailbox \"Archive\" of \(acct)"
            let make = m.folder.map { "if not (exists mailbox \"Mailbag/\($0)\" of \(acct)) then make new mailbox with properties {name:\"Mailbag/\($0)\"} at \(acct)\n" } ?? ""
            let counter = m.folder == nil ? "nArchived" : "nFiled"
            lines.append("""
            try
                \(make)move (first message of mailbox "INBOX" of \(acct) whose id is \(mid)) to \(dest)
                set \(counter) to \(counter) + 1
            end try
            """)
        }
        let out = try run("set nFiled to 0\nset nArchived to 0\ntell application \"Mail\"\n\(lines.joined(separator: "\n"))\nend tell\nreturn (nFiled as string) & \",\" & (nArchived as string)")
        let n = out.split(separator: ",").map { Int($0) ?? 0 }
        return (n.first ?? 0, n.count > 1 ? n[1] : 0)
    }
}
#endif
