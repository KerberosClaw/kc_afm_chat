import SwiftUI
import AFMChatCore

@main struct AFMChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var coordinator: ChatCoordinator?
    private let startupError: String?

    init() {
        do {
            let custom = ProcessInfo.processInfo.environment["AFM_CHAT_DATA_DIR"]
            let root = custom.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? ConversationStore.defaultRoot
            let store = try ConversationStore(root: root)
            _coordinator = State(initialValue: ChatCoordinator(store: store, model: AppleModel()))
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
    var body: some Scene {
        Window("AFM Chat", id: "chat") {
            if let coordinator {
                ChatView(coordinator: coordinator)
                    .onAppear { delegate.coordinator = coordinator }
                    .frame(minWidth: 760, minHeight: 540)
            } else {
                ContentUnavailableView("無法開啟對話資料", systemImage: "exclamationmark.triangle",
                    description: Text(startupError ?? "未知錯誤")).frame(width: 540, height: 300)
            }
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新增對話") { NotificationCenter.default.post(name: .newAFMConversation, object: nil) }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .appInfo) {
                Button("開啟對話資料夾") {
                    if let root = coordinator?.store.root { NSWorkspace.shared.open(root) }
                }
            }
        }
    }
}

extension Notification.Name { static let newAFMConversation = Notification.Name("newAFMConversation") }

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: ChatCoordinator?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator, coordinator.isBusy else { return .terminateNow }
        coordinator.stop()
        Task { await coordinator.waitUntilIdle(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
