import Foundation

public enum MessageRole: String, Codable, Sendable { case user, assistant }
public enum MessageStatus: String, Codable, Sendable { case complete, stopped, failed }

public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var role: MessageRole
    public var text: String
    public var imagePath: String?
    public var status: MessageStatus
    public var createdAt: Date

    public init(id: UUID = UUID(), role: MessageRole, text: String,
                imagePath: String? = nil, status: MessageStatus = .complete,
                createdAt: Date = Date()) {
        self.id = id; self.role = role; self.text = text
        self.imagePath = imagePath; self.status = status; self.createdAt = createdAt
    }
}

public struct Compaction: Codable, Equatable, Sendable {
    public var summary: String
    public var throughMessageID: UUID
    public var sourceMessageCount: Int
    public var inputTokensAfter: Int
    public init(summary: String, throughMessageID: UUID, sourceMessageCount: Int, inputTokensAfter: Int) {
        self.summary = summary; self.throughMessageID = throughMessageID
        self.sourceMessageCount = sourceMessageCount; self.inputTokensAfter = inputTokensAfter
    }
}

public enum EventKind: String, Codable, Sendable {
    case created, renamed, message, generationStarted, generationEnded
    case compactionStarted, compactionCompleted, compactionFailed
}

public struct ChatEvent: Codable, Identifiable, Equatable, Sendable {
    public var version: Int = 1
    public var id = UUID()
    public var sequence: Int
    public var timestamp = Date()
    public var kind: EventKind
    public var text: String?
    public var message: ChatMessage?
    public var compaction: Compaction?
    public init(sequence: Int = 0, kind: EventKind, text: String? = nil,
                message: ChatMessage? = nil, compaction: Compaction? = nil) {
        self.sequence = sequence; self.kind = kind; self.text = text
        self.message = message; self.compaction = compaction
    }
}

public struct Conversation: Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var events: [ChatEvent]
    public var messages: [ChatMessage] { events.compactMap(\.message) }
    public var latestCompaction: Compaction? { events.compactMap(\.compaction).last }
    public var updatedAt: Date { events.last?.timestamp ?? .distantPast }
    public var isInterrupted: Bool {
        events.last(where: { $0.kind == .generationStarted || $0.kind == .generationEnded })?.kind == .generationStarted
    }
    public var activeMessages: [ChatMessage] {
        let context: [ChatMessage]
        guard let compact = latestCompaction,
              let index = messages.firstIndex(where: { $0.id == compact.throughMessageID }) else { return messages }
        context = Array(messages.dropFirst(index + 1))
        return context
    }
    public var modelMessages: [ChatMessage] {
        let active = activeMessages
        var result: [ChatMessage] = []
        for message in active {
            if message.role == .assistant && (message.status == .failed
                || (message.status == .stopped && message.text.isEmpty)) {
                if result.last?.role == .user { result.removeLast() }
                continue
            }
            result.append(message)
        }
        return result
    }
}

public struct ConversationInfo: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var preview: String
}

public enum ChatError: LocalizedError {
    case storage(String), invalidLog(String), alreadyOpen, inputTooLarge, compactFailed(String), modelUnavailable(String)
    public var errorDescription: String? {
        switch self {
        case .storage(let reason): "無法保存對話：\(reason)"
        case .invalidLog(let reason): "對話紀錄需要修復：\(reason)"
        case .alreadyOpen: "另一個 AFM Chat 正在使用這個資料目錄。請先關閉另一個視窗或 App。"
        case .inputTooLarge: "這則訊息或圖片超過模型可容納的範圍，請縮短文字或換一張較小的圖片。"
        case .compactFailed(let reason): "無法整理對話，原始紀錄已保留。\(reason)"
        case .modelUnavailable(let reason): reason
        }
    }
}
