import Foundation

@main
struct LiveCheck {
    static func main() {
        let reader = UsageReader()
        do {
            let value = try reader.readOpenAI()
            print("ChatGPT OK: context=\(value.contextTokens)/\(value.contextLimit), session=\(value.sessionTokens)")
        } catch {
            FileHandle.standardError.write(Data("ChatGPT FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }

        do {
            let value = try reader.readClaude()
            print("Claude OK: context=\(value.contextTokens)/\(value.contextLimit), session=\(value.sessionTokens)")
        } catch {
            FileHandle.standardError.write(Data("Claude FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
