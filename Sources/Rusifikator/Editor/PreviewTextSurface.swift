import AppKit
import SwiftUI

/// Reading and scrolling are available while selection and copy stay reserved
/// for the confirmed final surface.
struct PreviewTextSurface: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = PreviewTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 13)
        view.textColor = NSColor(AppTheme.text)
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? PreviewTextView, view.string != text else { return }
        view.string = text
    }
}

final class PreviewTextView: NSTextView {
    override var acceptsFirstResponder: Bool { false }
    override func becomeFirstResponder() -> Bool { false }
    override func copy(_ sender: Any?) {}
    override func selectAll(_ sender: Any?) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}
