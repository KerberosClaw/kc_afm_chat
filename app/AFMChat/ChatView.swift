import SwiftUI
import UniformTypeIdentifiers
import AFMChatCore

struct ChatView: View {
    @Bindable var coordinator: ChatCoordinator
    @State private var selectedID: UUID?
    @State private var query = ""
    @State private var draft = ""
    @State private var attachment: Data?
    @State private var error: String?
    @State private var renameID: UUID?
    @State private var renameText = ""
    @State private var deletingID: UUID?
    @State private var isDropTarget = false
    @State private var showWarnings = false
    @State private var seenWarnings = 0

    private var current: Conversation? {
        _ = coordinator.revision
        return selectedID.flatMap { try? coordinator.store.conversation($0) }
    }
    private var infos: [ConversationInfo] {
        _ = coordinator.revision
        return coordinator.store.list(search: query)
    }
    private var isCurrentRunning: Bool { coordinator.generationConversationID == selectedID && coordinator.isBusy }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("對話").font(.title3.weight(.semibold))
                    Spacer()
                    Button(action: newConversation) { Image(systemName: "square.and.pencil") }
                        .buttonStyle(.plain).help("新增對話 ⌘N").accessibilityLabel("新增對話")
                }.padding()
                TextField("搜尋對話", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal).padding(.bottom, 10)
                List(selection: $selectedID) {
                    ForEach(infos) { info in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(info.title).font(.body.weight(.medium)).lineLimit(1)
                            Text(info.preview.isEmpty ? "開始一段新對話" : info.preview)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 5).tag(info.id)
                        .contextMenu {
                            Button("重新命名") { renameID = info.id; renameText = info.title }
                            Button("刪除對話", role: .destructive) { deletingID = info.id }
                                .disabled(coordinator.generationConversationID == info.id)
                        }
                    }
                }.listStyle(.sidebar)
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                    Text("對話只保存在這部 Mac")
                }.font(.caption).foregroundStyle(.secondary).padding()
            }.navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                header
                if let unsaved = coordinator.unsavedReply {
                    VStack(alignment: .leading) {
                        Text("回覆保存未完成，暫存內容仍在此處。").font(.headline)
                        Text(unsaved.isEmpty ? "（沒有可保存的文字）" : unsaved).textSelection(.enabled).lineLimit(5)
                        HStack {
                            Button("複製暫存回覆") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(unsaved, forType: .string)
                            }
                            Button("捨棄暫存內容") { coordinator.dismissUnsavedReply() }
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.12))
                }
                Divider()
                transcript
                Divider()
                composer
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay { if isDropTarget { RoundedRectangle(cornerRadius: 16).stroke(.tint, lineWidth: 3).padding(8) } }
            .onDrop(of: [UTType.fileURL.identifier, UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier],
                    isTargeted: $isDropTarget, perform: receiveDrop)
        }
        .onAppear {
            selectedID = coordinator.store.list().first?.id
            if selectedID == nil { newConversation() }
            showWarnings = !coordinator.store.warnings.isEmpty
            seenWarnings = coordinator.store.warnings.count
        }
        .onReceive(NotificationCenter.default.publisher(for: .newAFMConversation)) { _ in newConversation() }
        .onChange(of: selectedID) { _, _ in draft = ""; attachment = nil }
        .onChange(of: coordinator.lastError) { _, value in if let value { error = value } }
        .onChange(of: coordinator.revision) { _, _ in
            if coordinator.store.warnings.count > seenWarnings {
                seenWarnings = coordinator.store.warnings.count
                showWarnings = true
            }
        }
        .alert("無法完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil; coordinator.clearError() }
        } message: { Text(error ?? "") }
        .alert("重新命名", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("名稱", text: $renameText)
            Button("取消", role: .cancel) { renameID = nil }
            Button("儲存") {
                if let id = renameID { perform { try coordinator.store.rename(id, title: renameText) } }
                renameID = nil
            }
        }
        .confirmationDialog("刪除這段對話及其圖片？此操作無法復原。", isPresented:
            Binding(get: { deletingID != nil }, set: { if !$0 { deletingID = nil } })) {
                Button("刪除對話", role: .destructive) {
                    if let id = deletingID {
                        perform { try coordinator.store.delete(id) }
                        if selectedID == id { selectedID = coordinator.store.list().first?.id }
                        if selectedID == nil { newConversation() }
                    }
                    deletingID = nil
                }
            }
        .alert("資料恢復通知", isPresented: $showWarnings) {
            Button("開啟資料夾") { NSWorkspace.shared.open(coordinator.store.root) }
            Button("好", role: .cancel) {}
        } message: { Text(coordinator.store.warnings.joined(separator: "\n")) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(current?.title ?? "AFM Chat").font(.headline).lineLimit(1)
                Text(coordinator.model.displayName + " · 裝置端模型").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let reason = coordinator.model.unavailableReason {
                Label("模型尚未就緒", systemImage: "exclamationmark.circle").font(.caption).help(reason)
            } else {
                Label("本機", systemImage: "circle.fill").font(.caption).foregroundStyle(.green)
            }
        }.padding(.horizontal, 22).padding(.vertical, 15)
    }
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if current?.messages.isEmpty != false {
                        VStack(spacing: 14) {
                            Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.tint)
                            Text("聊點什麼，或放進一張圖片").font(.title2.weight(.semibold))
                            Text("在這部 Mac 上回答。接近上下文上限時，會自動整理對話。")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            if let reason = coordinator.model.unavailableReason { Text(reason).foregroundStyle(.orange) }
                        }.frame(maxWidth: .infinity).padding(.top, 70).padding(.bottom, 50)
                    }
                    ForEach(current?.events ?? []) { event in
                        if let message = event.message { messageRow(message) }
                        else if let compact = event.compaction {
                            DisclosureGroup {
                                Text(compact.summary).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            } label: {
                                Label("對話已整理 · 原始紀錄仍保留", systemImage: "text.badge.checkmark")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                        } else if event.kind == .compactionFailed {
                            Label(event.text ?? "整理未完成", systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    if current?.isInterrupted == true && !isCurrentRunning {
                        Label("上次回覆未完成。已保存的對話仍在，可以繼續提問。", systemImage: "arrow.counterclockwise")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if isCurrentRunning {
                        if coordinator.phase == .compacting {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("正在整理對話…").font(.callout.weight(.medium))
                                    Text("保留重點與近期內容，完成後會接著回答。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        } else if !coordinator.streamingText.isEmpty {
                            messageRow(ChatMessage(role: .assistant, text: coordinator.streamingText), streaming: true)
                        } else {
                            HStack { ProgressView().controlSize(.small); Text(coordinator.phase.label).foregroundStyle(.secondary) }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(24).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }
            .onChange(of: coordinator.streamingText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: coordinator.revision) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: selectedID) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
    private func messageRow(_ message: ChatMessage, streaming: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: message.role == .user ? "person.crop.circle" : "sparkles")
                Text(message.role == .user ? "你" : "AFM").fontWeight(.semibold)
                if message.status != .complete { Text(message.status == .stopped ? "已停止" : "未完成").foregroundStyle(.secondary) }
                Spacer()
                if !streaming && !message.text.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("複製訊息")
                }
            }.font(.caption).foregroundStyle(.secondary)
            if let path = message.imagePath, let id = selectedID,
               let url = try? coordinator.store.imageURL(path, conversationID: id), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if !message.text.isEmpty {
                Text(LocalizedStringKey(message.text)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).lineSpacing(4)
            }
        }.padding(15)
            .background(message.role == .user ? Color.accentColor.opacity(0.07) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12))
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if let attachment, let image = NSImage(data: attachment) {
                HStack {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 64, height: 52).clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("已附上一張圖片").font(.caption).foregroundStyle(.secondary)
                    Button { self.attachment = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 12) {
                Composer(text: $draft, enabled: true, onSend: send, onImage: acceptImage)
                    .frame(minHeight: 74, maxHeight: 120)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topLeading) {
                        if draft.isEmpty { Text("輸入訊息，或貼上圖片…").foregroundStyle(.tertiary).padding(12).allowsHitTesting(false) }
                    }
                VStack(spacing: 12) {
                    Button(action: chooseImage) { Image(systemName: "photo.badge.plus") }.help("加入圖片").accessibilityLabel("加入圖片")
                    if coordinator.isBusy {
                        Button { coordinator.stop() } label: { Image(systemName: "stop.fill") }
                            .buttonStyle(.borderedProminent).tint(.orange).help("停止生成").accessibilityLabel("停止生成")
                            .disabled(coordinator.phase == .stopping)
                    } else {
                        Button(action: send) { Image(systemName: "arrow.up") }.buttonStyle(.borderedProminent)
                            .disabled((draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachment == nil)
                                      || coordinator.model.unavailableReason != nil)
                            .help("送出 Return").accessibilityLabel("送出")
                    }
                }.padding(.bottom, 4)
            }
            HStack {
                Text(coordinator.isBusy ? coordinator.phase.label : "Return 送出 · Shift Return 換行")
                Spacer()
                if isCurrentRunning, let count = coordinator.contextTokens {
                    Text("輸入預算約 \(count) / \(coordinator.model.contextSize) tokens")
                } else { Text("上下文 \(coordinator.model.contextSize) tokens") }
            }.font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 22).padding(.vertical, 14)
    }
    private func newConversation() {
        perform { selectedID = try coordinator.store.create() }
    }
    private func send() {
        guard !coordinator.isBusy else { return }
        do {
            if selectedID == nil { selectedID = try coordinator.store.create() }
            guard let id = selectedID else { return }
            try coordinator.send(conversationID: id, text: draft, imageData: attachment)
            draft = ""; attachment = nil
        } catch { self.error = error.localizedDescription }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); coordinator.refresh() } catch { self.error = error.localizedDescription }
    }
    private func acceptImage(_ data: Data) {
        guard data.count <= 20 * 1024 * 1024, NSImage(data: data) != nil else {
            error = "請選擇 20 MB 以內的有效圖片。"; return
        }
        attachment = data
    }
    private func chooseImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { acceptImage(try Data(contentsOf: url)) } catch { self.error = error.localizedDescription }
        }
    }
    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.count == 1, let provider = providers.first else {
            error = "每次請放入一張圖片。"; return false
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    do { acceptImage(try Data(contentsOf: url)) } catch { self.error = error.localizedDescription }
                }
            }
            return true
        }
        for type in [UTType.png, .jpeg, .tiff] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                if let data { Task { @MainActor in acceptImage(data) } }
            }
            return true
        }
        return false
    }
}
