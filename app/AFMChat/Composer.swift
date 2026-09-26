import SwiftUI
import AppKit

struct Composer: NSViewRepresentable {
    @Binding var text: String
    var enabled: Bool
    var onSend: () -> Void
    var onImage: (Data) -> Void
    func makeCoordinator() -> Delegate { Delegate(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = MessageTextView()
        editor.isRichText = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 14)
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityIdentifier("messageComposer")
        editor.setAccessibilityLabel("訊息")
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = view.documentView as? MessageTextView else { return }
        if editor.string != text { editor.string = text }
        editor.isEditable = enabled
        editor.onSend = onSend; editor.onImage = onImage
    }
    final class Delegate: NSObject, NSTextViewDelegate {
        var parent: Composer
        init(_ parent: Composer) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
}

final class MessageTextView: NSTextView {
    var onSend: (() -> Void)?
    var onImage: ((Data) -> Void)?
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.png, .tiff]
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) && !hasMarkedText() {
            onSend?()
        } else { super.keyDown(with: event) }
    }
    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        if let image = NSImage(pasteboard: .general), let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            onImage?(png)
        } else { super.paste(sender) }
    }
}
