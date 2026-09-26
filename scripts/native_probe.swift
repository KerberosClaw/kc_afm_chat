import Foundation
import FoundationModels

@main struct NativeProbe {
    @MainActor static func main() async throws {
        let model = SystemLanguageModel.default
        print("availability=\(model.availability)")
        guard model.availability == .available else { return }
        print("variant=\(model.variant.displayName) context=\(model.contextSize)")
        let start = Date()
        let warm = try await LanguageModelSession(model: model).respond(
            to: "只回答：準備好了", options: .init(maximumResponseTokens: 32))
        print("warm=\(warm.content) elapsed=\(Date().timeIntervalSince(start))")
        if CommandLine.arguments.contains("--cancel") {
            var receivedText = false
            let task = Task { @MainActor in
                var count = 0
                do {
                    let session = LanguageModelSession(model: model)
                    for try await part in session.streamResponse(
                        to: "請用正體中文詳細介紹台灣茶的歷史，至少一千字。",
                        options: .init(maximumResponseTokens: 512)) {
                        count = part.content.count
                        receivedText = count > 0
                        try Task.checkCancellation()
                    }
                    print("stream_finished chars=\(count) cancelled=\(Task.isCancelled)")
                } catch { print("stream_ended=\(type(of: error)) chars=\(count)") }
            }
            let waitStart = Date()
            while !receivedText && Date().timeIntervalSince(waitStart) < 20 {
                try await Task.sleep(for: .milliseconds(100))
            }
            let cancelStart = Date()
            task.cancel()
            await task.value
            print("cancel_return_seconds=\(Date().timeIntervalSince(cancelStart))")
            let followStart = Date()
            let follow = try await LanguageModelSession(model: model).respond(
                to: "只回答：好", options: .init(maximumResponseTokens: 16))
            print("followup=\(follow.content) seconds=\(Date().timeIntervalSince(followStart))")
        }
    }
}
