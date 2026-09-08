import Foundation

struct MeterSnapshot: Equatable {
    let provider: String
    let source: String
    let model: String?
    let contextTokens: Int
    let contextLimit: Int
    let sessionTokens: Int
    let shortWindowPercent: Double?
    let longWindowPercent: Double?
    let updatedAt: Date
    let contextLimitIsEstimated: Bool

    var contextPercent: Double {
        guard contextLimit > 0 else { return 0 }
        return min(100, max(0, Double(contextTokens) / Double(contextLimit) * 100))
    }
}

enum MeterError: Error, LocalizedError {
    case noData(String)

    var errorDescription: String? {
        switch self {
        case .noData(let message): return message
        }
    }
}

final class UsageReader {
    private let fileManager: FileManager
    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
    }

    func readOpenAI() throws -> MeterSnapshot {
        let root = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let candidates = recentFiles(in: root) { $0.pathExtension == "jsonl" }
        for file in candidates.prefix(40) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if let snapshot = Self.parseOpenAIJSONL(text, modified: modifiedDate(file)) {
                return snapshot
            }
        }
        throw MeterError.noData("No ChatGPT Work or Codex token session found")
    }

    func readClaude() throws -> MeterSnapshot {
        let support = home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
        let root = support.appendingPathComponent("local-agent-mode-sessions", isDirectory: true)
        let candidates = recentFiles(in: root) {
            $0.pathExtension == "jsonl" &&
            $0.lastPathComponent != "audit.jsonl" &&
            !$0.path.contains("/subagents/") &&
            $0.path.contains("/.claude/projects/")
        }
        let planURL = support.appendingPathComponent("plan-usage-history.json")
        let planData = try? Data(contentsOf: planURL)
        let plan = planData.flatMap(Self.parseClaudePlan)

        for file in candidates.prefix(60) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if let snapshot = Self.parseClaudeJSONL(text, modified: modifiedDate(file), plan: plan) {
                return snapshot
            }
        }
        throw MeterError.noData("No Claude Work token session found")
    }

    private func recentFiles(in root: URL, matching predicate: (URL) -> Bool) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: []
        ) else { return [] }

        var files: [(URL, Date)] = []
        for case let url as URL in enumerator {
            guard predicate(url) else { continue }
            files.append((url, modifiedDate(url)))
        }
        return files.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private func modifiedDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    static func parseOpenAIJSONL(_ text: String, modified: Date) -> MeterSnapshot? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any],
                  let contextLimit = int(info["model_context_window"]),
                  let contextTokens = int(last["input_tokens"]),
                  let sessionTokens = int(total["total_tokens"]) else { continue }

            let limits = payload["rate_limits"] as? [String: Any]
            let primary = limits?["primary"] as? [String: Any]
            let secondary = limits?["secondary"] as? [String: Any]
            return MeterSnapshot(
                provider: "ChatGPT",
                source: "Codex and Work local session",
                model: nil,
                contextTokens: contextTokens,
                contextLimit: contextLimit,
                sessionTokens: sessionTokens,
                shortWindowPercent: double(primary?["used_percent"]),
                longWindowPercent: double(secondary?["used_percent"]),
                updatedAt: parseDate(root["timestamp"]) ?? modified,
                contextLimitIsEstimated: false
            )
        }
        return nil
    }

    static func parseClaudeJSONL(_ text: String, modified: Date,
                                 plan: (Double?, Double?)?) -> MeterSnapshot? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var latestUsage: [String: Any]?
        var latestModel: String?
        var latestDate = modified
        var sessionTokens = 0
        var seen = Set<String>()

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = root["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }

            let identity = (message["id"] as? String)
                ?? (root["uuid"] as? String)
                ?? "\(root["timestamp"] ?? "")|\(usage["output_tokens"] ?? "")"
            if seen.insert(identity).inserted {
                sessionTokens += claudeUsageTotal(usage)
            }
            latestUsage = usage
            latestModel = message["model"] as? String
            latestDate = parseDate(root["timestamp"]) ?? latestDate
        }

        guard let usage = latestUsage else { return nil }
        let currentInput = (int(usage["input_tokens"]) ?? 0)
            + (int(usage["cache_creation_input_tokens"]) ?? 0)
            + (int(usage["cache_read_input_tokens"]) ?? 0)
        let configuredLimit = UserDefaults.standard.integer(forKey: "ClaudeContextLimit")
        let contextLimit = configuredLimit > 0 ? configuredLimit : 200_000

        return MeterSnapshot(
            provider: "Claude",
            source: "Claude Work local session",
            model: latestModel,
            contextTokens: currentInput,
            contextLimit: contextLimit,
            sessionTokens: sessionTokens,
            shortWindowPercent: plan?.0,
            longWindowPercent: plan?.1,
            updatedAt: latestDate,
            contextLimitIsEstimated: true
        )
    }

    static func parseClaudePlan(_ data: Data) -> (Double?, Double?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = root["samples"] as? [[String: Any]],
              let latest = samples.max(by: { (double($0["t"]) ?? 0) < (double($1["t"]) ?? 0) }),
              let usage = latest["u"] as? [String: Any] else { return nil }
        return (double(usage["fh"]), double(usage["sd"]))
    }

    private static func claudeUsageTotal(_ usage: [String: Any]) -> Int {
        (int(usage["input_tokens"]) ?? 0)
        + (int(usage["cache_creation_input_tokens"]) ?? 0)
        + (int(usage["cache_read_input_tokens"]) ?? 0)
        + (int(usage["output_tokens"]) ?? 0)
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
