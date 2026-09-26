import Foundation
import AppKit
import AFMChatCore

// Explicit opt-in integration probe. Uses a separate data directory and the real on-device model.
@main struct Probe {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            print("Usage: swift run AFMChatProbe <empty-data-directory>")
            return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: root.path) else {
            throw ChatError.storage("Probe directory must not already exist")
        }
        let store = try ConversationStore(root: root)
        let model = AppleModel()
        guard model.unavailableReason == nil else { throw ChatError.modelUnavailable(model.unavailableReason!) }
        print("MODEL \(model.displayName) context=\(model.contextSize)")
        let coordinator = ChatCoordinator(store: store, model: model)
        func send(_ id: UUID, _ prompt: String, image: Data? = nil) async throws -> String {
            let start = Date()
            try coordinator.send(conversationID: id, text: prompt, imageData: image)
            await coordinator.waitUntilIdle()
            let conversation = try store.conversation(id)
            guard let reply = conversation.messages.last, reply.role == .assistant,
                  reply.status == .complete, coordinator.lastError == nil else {
                throw ChatError.modelUnavailable(coordinator.lastError ?? "Incomplete response")
            }
            print("REPLY seconds=\(Date().timeIntervalSince(start)) text=\(reply.text)")
            return reply.text
        }
        let textID = try store.create(title: "Native text check")
        let text = try await send(textID, "請用繁體中文簡短回答：二加三等於多少？")
        guard text.contains("5") || text.contains("五") else { throw ChatError.modelUnavailable("Arithmetic probe mismatch") }

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 400, height: 300)).fill()
        NSColor.red.setFill(); NSBezierPath(ovalIn: NSRect(x: 40, y: 80, width: 120, height: 120)).fill()
        NSColor.blue.setFill(); NSBezierPath(rect: NSRect(x: 240, y: 80, width: 120, height: 120)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: root.appendingPathComponent("probe.png"))
        let imageID = try store.create(title: "Native image check")
        _ = try await send(imageID, "請用一句繁體中文描述圖片中的顏色與形狀。", image: png)

        func seed(_ title: String) async throws -> UUID {
            let id = try store.create(title: title)
            var messages: [ChatMessage] = []
            for i in 0..<40 {
                let user = ChatMessage(role: .user, text: "Project Bluebird is our community library project. The opening date is November 18. The budget is 420 dollars. Planning note \(i): arrange books by category, keep the entrance accessible, prepare clear signs, and ask volunteers to check returned items. We prefer short answers in Traditional Chinese. Please remember the project name, date, and budget.")
                let assistant = ChatMessage(role: .assistant, text: "Noted. Project Bluebird opens November 18 with a 420 dollar budget. We will prepare books, accessible entrances, signs, and volunteer checklists.")
                for message in [user, assistant] {
                    try store.append(id, event: .init(kind: .message, message: message))
                    messages.append(message)
                }
                let count = try await model.count(context: .init(messages: messages),
                    prompt: .init(role: .user, text: "我們的專案名稱、日期和預算是什麼？"), imageURL: nil)
                if count > model.contextSize - coordinator.outputReserve - 64 {
                    print("SEED messages=\(messages.count) tokens=\(count)")
                    return id
                }
            }
            throw ChatError.compactFailed("Could not seed enough history")
        }
        let compactID = try await seed("Native auto compact check")
        let before = try store.conversation(compactID).messages.count
        let answer = try await send(compactID, "我們的專案名稱、日期和預算是什麼？請簡短回答。")
        let compacted = try store.conversation(compactID)
        guard compacted.latestCompaction != nil, compacted.messages.count == before + 2,
              answer.localizedCaseInsensitiveContains("Bluebird"), answer.contains("420") else {
            throw ChatError.compactFailed("Compaction or retained-fact check failed")
        }
        print("SUMMARY \(compacted.latestCompaction!.summary)")
        let ui = try await seed("UI compact verification")
        print("UI_SEED \(ui.uuidString)")
        print("PASS native text, image response, automatic compaction, facts, original log retention")
    }
}
