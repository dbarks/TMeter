import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let openAI = #"{"timestamp":"2026-09-03T12:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":9000},"last_token_usage":{"input_tokens":25000},"model_context_window":100000},"rate_limits":{"primary":{"used_percent":12},"secondary":{"used_percent":34}}}}"#
let parsedOpenAI = UsageReader.parseOpenAIJSONL(openAI, modified: Date(timeIntervalSince1970: 0))
expect(parsedOpenAI?.contextTokens == 25_000, "OpenAI context tokens")
expect(parsedOpenAI?.sessionTokens == 9_000, "OpenAI session tokens")
expect(parsedOpenAI?.contextPercent == 25, "OpenAI context percent")
expect(parsedOpenAI?.shortWindowPercent == 12, "OpenAI short limit")

let claude = #"{"type":"assistant","timestamp":"2026-09-03T12:00:00.000Z","uuid":"a","message":{"id":"m1","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30000,"output_tokens":50}}}"#
let parsedClaude = UsageReader.parseClaudeJSONL(claude, modified: Date(), plan: (8, 21))
expect(parsedClaude?.contextTokens == 30_030, "Claude current context")
expect(parsedClaude?.sessionTokens == 30_080, "Claude processed tokens")
expect(parsedClaude?.shortWindowPercent == 8, "Claude short limit")
expect(parsedClaude?.longWindowPercent == 21, "Claude weekly limit")

let duplicateClaude = claude + "\n" + claude
let parsedDuplicate = UsageReader.parseClaudeJSONL(duplicateClaude, modified: Date(), plan: nil)
expect(parsedDuplicate?.sessionTokens == 30_080, "Claude duplicate message suppression")

let plan = #"{"version":2,"samples":[{"t":1,"u":{"fh":3,"sd":4}},{"t":2,"u":{"fh":9,"sd":11}}]}"#.data(using: .utf8)!
let parsedPlan = UsageReader.parseClaudePlan(plan)
expect(parsedPlan?.0 == 9, "Claude latest five-hour plan usage")
expect(parsedPlan?.1 == 11, "Claude latest weekly plan usage")

print("All TMeter parser tests passed")
