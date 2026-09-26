import Foundation
import Observation

public enum GenerationPhase: Equatable {
    case idle, preparing, compacting, generating, stopping
    public var label: String {
        switch self {
        case .idle: "就緒"
        case .preparing: "正在準備…"
        case .compacting: "正在整理對話…"
        case .generating: "正在回答…"
        case .stopping: "正在停止…"
        }
    }
}

@MainActor @Observable public final class ChatCoordinator {
    public let store: ConversationStore
    public let model: any ChatModel
    public private(set) var phase: GenerationPhase = .idle
    public private(set) var generationConversationID: UUID?
    public private(set) var streamingText = ""
    public private(set) var contextTokens: Int?
    public private(set) var lastError: String?
    public private(set) var unsavedReply: String?
    public private(set) var revision = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var didTimeOut = false
    public var isBusy: Bool { phase != .idle }
    public var outputReserve: Int { min(768, max(128, model.contextSize / 5)) }
    public init(store: ConversationStore, model: any ChatModel) { self.store = store; self.model = model }
    public func clearError() { lastError = nil }
    public func dismissUnsavedReply() { unsavedReply = nil }
    public func refresh() { revision += 1 }

    public func send(conversationID: UUID, text: String, imageData: Data? = nil) throws {
        guard !isBusy else { return }
        guard unsavedReply == nil else { throw ChatError.storage("請先複製或捨棄尚未保存的回覆。") }
        if let reason = model.unavailableReason { throw ChatError.modelUnavailable(reason) }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || imageData != nil else { return }
        var user = ChatMessage(role: .user, text: text.isEmpty ? "請描述這張圖片。" : text)
        if let imageData { user.imagePath = try store.saveImage(imageData, conversationID: conversationID) }
        let conversation = try store.conversation(conversationID)
        try store.append(conversationID, event: .init(kind: .message, message: user))
        lastError = nil; streamingText = ""; contextTokens = nil; didTimeOut = false
        generationConversationID = conversationID; phase = .preparing; revision += 1
        task = Task { [self] in await generate(conversationID: conversationID, user: user, before: conversation) }
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(90)) } catch { return }
            guard let self, self.isBusy else { return }
            self.didTimeOut = true
            self.stop()
        }
    }
    public func stop() {
        guard isBusy else { return }
        phase = .stopping
        task?.cancel()
    }
    public func waitUntilIdle() async { await task?.value }

    private func makeContext(_ conversation: Conversation) throws -> ModelContext {
        var urls: [UUID: URL] = [:]
        for message in conversation.modelMessages {
            if let path = message.imagePath {
                let url = try store.imageURL(path, conversationID: conversation.id)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ChatError.storage("對話中的圖片檔案遺失；請恢復圖片或另開對話。")
                }
                urls[message.id] = url
            }
        }
        return .init(summary: conversation.latestCompaction?.summary ?? "",
                     messages: conversation.modelMessages, imageURLs: urls)
    }
    private func generate(conversationID id: UUID, user: ChatMessage, before: Conversation) async {
        var status = MessageStatus.complete
        var compactStarted = false
        defer {
            watchdog?.cancel(); watchdog = nil
            phase = .idle; generationConversationID = nil; streamingText = ""
            task = nil; revision += 1
        }
        do {
            // The user event is already durable. Later failures must not ask the composer to resend it.
            try store.append(id, event: .init(kind: .generationStarted))
            if before.messages.isEmpty { try store.rename(id, title: String(user.text.prefix(32))) }
            var context = try makeContext(before)
            let image = try user.imagePath.map { try store.imageURL($0, conversationID: id) }
            let ceiling = model.contextSize - outputReserve - 128
            guard try await model.count(context: .init(), prompt: user, imageURL: image) <= ceiling else {
                throw ChatError.inputTooLarge
            }
            var count = try await model.count(context: context, prompt: user, imageURL: image)
            if count > ceiling {
                try Task.checkCancellation()
                phase = .compacting
                try store.append(id, event: .init(kind: .compactionStarted))
                compactStarted = true; revision += 1
                // Prefer retaining the latest complete user/assistant turn, then retry with none.
                let messages = context.messages
                guard !messages.isEmpty else { throw ChatError.inputTooLarge }
                let lastUser = messages.lastIndex { $0.role == .user } ?? messages.count
                let keepFrom = lastUser > 0 ? lastUser : messages.count
                var summarized = Array(messages.prefix(keepFrom))
                var retained = Array(messages.dropFirst(keepFrom))
                var summary = try await model.summarize(previous: context.summary, messages: summarized)
                var candidate = ModelContext(summary: summary, messages: retained, imageURLs: context.imageURLs)
                count = try await model.count(context: candidate, prompt: user, imageURL: image)
                if count > ceiling && !retained.isEmpty {
                    summary = try await model.summarize(previous: summary, messages: retained)
                    summarized = messages; retained = []
                    candidate = ModelContext(summary: summary)
                    count = try await model.count(context: candidate, prompt: user, imageURL: image)
                }
                guard count <= ceiling, let last = summarized.last else { throw ChatError.inputTooLarge }
                try Task.checkCancellation()
                let compact = Compaction(summary: summary, throughMessageID: last.id,
                    sourceMessageCount: summarized.count, inputTokensAfter: count)
                try store.append(id, event: .init(kind: .compactionCompleted, compaction: compact))
                compactStarted = false; context = candidate; revision += 1
            }
            try Task.checkCancellation()
            contextTokens = count; phase = .generating
            let result = try await model.respond(context: context, prompt: user, imageURL: image,
                maximumTokens: outputReserve) { [weak self] text in self?.streamingText = text }
            try Task.checkCancellation()
            streamingText = result
        } catch {
            status = Task.isCancelled ? .stopped : .failed
            let explanation = didTimeOut ? "模型回應逾時，已要求停止。" : error.localizedDescription
            if status == .failed || didTimeOut { lastError = explanation }
            if compactStarted {
                do { try store.append(id, event: .init(kind: .compactionFailed,
                    text: status == .stopped ? "整理已停止，原始內容保留。" : explanation)) }
                catch { lastError = error.localizedDescription }
            }
        }
        do {
            let assistant = ChatMessage(role: .assistant, text: streamingText, status: status)
            try store.append(id, event: .init(kind: .message, message: assistant))
            try store.append(id, event: .init(kind: .generationEnded, text: status.rawValue))
        } catch {
            unsavedReply = streamingText
            lastError = "回覆保存未完成，請先複製畫面上的暫存內容：\(error.localizedDescription)"
        }
    }
}
