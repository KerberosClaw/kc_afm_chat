import Foundation
import Testing
@testable import AFMChatCore

private func temporaryRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("afm-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor @Test func replayAndRebuildPreserveMessagesAndTitles() throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var store: ConversationStore? = try .init(root: root)
    let id = try store!.create()
    try store!.append(id, event: .init(kind: .message, message: .init(role: .user, text: "台灣茶 100%_測試")))
    try store!.rename(id, title: "茶的歷史")
    store = nil
    try FileManager.default.removeItem(at: root.appendingPathComponent("index.sqlite"))
    let restored = try ConversationStore(root: root)
    #expect(try restored.conversation(id).messages.count == 1)
    #expect(restored.list(search: "100%_").map(\.id) == [id])
    #expect(restored.list(search: "茶的").first?.title == "茶的歷史")
    #expect(restored.list(search: "不存在").isEmpty)
}

@MainActor @Test func truncatedTailIsPreservedAndCompleteRecordsSurvive() throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var store: ConversationStore? = try .init(root: root)
    let id = try store!.create(); store = nil
    let dir = root.appendingPathComponent("conversations/\(id.uuidString)")
    let file = dir.appendingPathComponent("events.jsonl")
    let writer = try FileHandle(forWritingTo: file)
    try writer.seekToEnd(); try writer.write(contentsOf: Data("{\"sequence\":2".utf8)); try writer.close()
    let restored = try ConversationStore(root: root)
    #expect(try restored.conversation(id).events.count == 1)
    #expect(!restored.warnings.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasSuffix(".recovery") })
    try restored.append(id, event: .init(kind: .message, message: .init(role: .user, text: "still works")))
    #expect(try restored.conversation(id).events.last?.sequence == 2)
}

@MainActor @Test func corruptCompleteLineIsNotSilentlyDiscarded() throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var store: ConversationStore? = try .init(root: root)
    let id = try store!.create(); store = nil
    let file = root.appendingPathComponent("conversations/\(id.uuidString)/events.jsonl")
    var bytes = try Data(contentsOf: file); bytes.append(Data("broken\n".utf8)); try bytes.write(to: file)
    let restored = try ConversationStore(root: root)
    #expect(restored.list().isEmpty)
    #expect(!restored.warnings.isEmpty)
    #expect(try Data(contentsOf: file) == bytes)
}

@MainActor @Test func corruptInteriorWithPartialTailRemainsByteIdentical() throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    var store: ConversationStore? = try .init(root: root)
    let id = try store!.create(); store = nil
    let file = root.appendingPathComponent("conversations/\(id.uuidString)/events.jsonl")
    var bytes = try Data(contentsOf: file)
    bytes.append(Data("corrupt complete line\n{partial".utf8)); try bytes.write(to: file)
    let restored = try ConversationStore(root: root)
    #expect(restored.list().isEmpty)
    #expect(try Data(contentsOf: file) == bytes)
}

@MainActor @Test func onlyOneWriterAndNoAttachmentTraversal() throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try ConversationStore(root: root)
    #expect(throws: (any Error).self) { _ = try ConversationStore(root: root) }
    let id = try store.create()
    #expect(throws: (any Error).self) { _ = try store.imageURL("attachments/../../secret", conversationID: id) }
    #expect(throws: (any Error).self) { _ = try store.imageURL("/tmp/image.png", conversationID: id) }
    #expect(throws: (any Error).self) { try store.append(id, event: .init(kind: .message)) }
}

@MainActor @Test func compactionPreservesOriginalsAndControlsActiveContext() throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try ConversationStore(root: root); let id = try store.create()
    let first = ChatMessage(role: .user, text: "My project is Bluebird.")
    let reply = ChatMessage(role: .assistant, text: "Understood.")
    for m in [first, reply] { try store.append(id, event: .init(kind: .message, message: m)) }
    try store.append(id, event: .init(kind: .compactionCompleted, compaction:
        .init(summary: "Project: Bluebird", throughMessageID: reply.id, sourceMessageCount: 2, inputTokensAfter: 20)))
    try store.append(id, event: .init(kind: .message, message: .init(role: .user, text: "Next task")))
    let c = try store.conversation(id)
    #expect(c.messages.count == 3)
    #expect(c.activeMessages.map(\.text) == ["Next task"])
    #expect(c.latestCompaction?.summary == "Project: Bluebird")
    try store.delete(id)
    #expect(store.list().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("conversations/\(id.uuidString)").path))
}

@MainActor final class FakeModel: ChatModel {
    var contextSize = 512
    var displayName = "Test model"
    var unavailableReason: String?
    var failSummary = false
    var pauseReply = false
    var lastContext: ModelContext?
    func count(context: ModelContext, prompt: ChatMessage, imageURL: URL?) async throws -> Int {
        20 + context.summary.count + context.messages.reduce(0) { $0 + $1.text.count } + prompt.text.count
    }
    func respond(context: ModelContext, prompt: ChatMessage, imageURL: URL?, maximumTokens: Int,
                 update: @escaping @MainActor (String) -> Void) async throws -> String {
        lastContext = context
        update("partial")
        if pauseReply { try await Task.sleep(for: .seconds(30)) }
        return "done"
    }
    func summarize(previous: String, messages: [ChatMessage]) async throws -> String {
        if failSummary { throw ChatError.compactFailed("synthetic failure") }
        return "Project: Bluebird"
    }
}

@MainActor @Test func coordinatorCompactsAndRetainsTranscript() async throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try ConversationStore(root: root); let id = try store.create()
    for n in 0..<6 {
        let message = ChatMessage(role: n.isMultiple(of: 2) ? .user : .assistant, text: String(repeating: "x", count: 60))
        try store.append(id, event: .init(kind: .message, message: message))
    }
    let fake = FakeModel(); let chat = ChatCoordinator(store: store, model: fake)
    try chat.send(conversationID: id, text: "Continue")
    await chat.waitUntilIdle()
    #expect(!chat.isBusy)
    #expect(chat.lastError == nil)
    #expect(try store.conversation(id).messages.count == 8)
    #expect(try store.conversation(id).latestCompaction != nil)
    #expect(fake.lastContext?.summary == "Project: Bluebird")
}

@MainActor @Test func summaryFailureDoesNotDiscardHistory() async throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try ConversationStore(root: root); let id = try store.create()
    for n in 0..<6 { try store.append(id, event: .init(kind: .message,
        message: .init(role: n.isMultiple(of: 2) ? .user : .assistant, text: String(repeating: "x", count: 60)))) }
    let fake = FakeModel(); fake.failSummary = true
    let chat = ChatCoordinator(store: store, model: fake)
    try chat.send(conversationID: id, text: "Continue"); await chat.waitUntilIdle()
    #expect(chat.lastError != nil)
    #expect(try store.conversation(id).latestCompaction == nil)
    #expect(try store.conversation(id).modelMessages.count == 6)
    #expect(fake.lastContext == nil)
}

@MainActor @Test func stoppingPersistsPartialAndEndsTurn() async throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try ConversationStore(root: root); let id = try store.create()
    let fake = FakeModel(); fake.pauseReply = true
    let chat = ChatCoordinator(store: store, model: fake)
    try chat.send(conversationID: id, text: "Hello")
    for _ in 0..<100 where chat.streamingText.isEmpty { await Task.yield() }
    chat.stop(); await chat.waitUntilIdle()
    #expect(try store.conversation(id).messages.last?.text == "partial")
    #expect(try store.conversation(id).messages.last?.status == .stopped)
    #expect(try !store.conversation(id).isInterrupted)
}

@MainActor @Test func oversizedInputStaysInHistoryButDoesNotPoisonNextTurn() async throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try ConversationStore(root: root); let id = try store.create()
    let fake = FakeModel(); let chat = ChatCoordinator(store: store, model: fake)
    try chat.send(conversationID: id, text: String(repeating: "x", count: 1000))
    await chat.waitUntilIdle()
    #expect(chat.lastError != nil)
    #expect(try store.conversation(id).messages.count == 2)
    #expect(try store.conversation(id).modelMessages.isEmpty)
    try chat.send(conversationID: id, text: "Hello")
    await chat.waitUntilIdle()
    #expect(chat.lastError == nil)
    #expect(try store.conversation(id).messages.count == 4)
    #expect(fake.lastContext?.messages.isEmpty == true)
}

@MainActor @Test func cancellationBeforeOutputDoesNotLeaveUnansweredModelTurn() async throws {
    let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try ConversationStore(root: root); let id = try store.create()
    let chat = ChatCoordinator(store: store, model: FakeModel())
    try chat.send(conversationID: id, text: "Cancel before generation")
    chat.stop(); await chat.waitUntilIdle()
    #expect(try store.conversation(id).messages.count == 2)
    #expect(try store.conversation(id).messages.last?.status == .stopped)
    #expect(try store.conversation(id).modelMessages.isEmpty)
}
