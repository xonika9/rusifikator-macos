import AppKit
import SwiftUI

struct AlignedTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let placeholder: String
    let isEditable: Bool

    init(
        text: Binding<String>,
        isFocused: Binding<Bool> = .constant(false),
        placeholder: String = "",
        isEditable: Bool = true
    ) {
        _text = text
        _isFocused = isFocused
        self.placeholder = placeholder
        self.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> AlignedTextContainer {
        let container = AlignedTextContainer()
        container.textView.delegate = context.coordinator
        context.coordinator.placeholderLabel = container.placeholderLabel
        configureStaticProperties(container)
        updateDynamicProperties(container)
        return container
    }

    func updateNSView(_ container: AlignedTextContainer, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused
        updateDynamicProperties(container)

        if container.textView.string != text {
            container.textView.string = text
            container.textView.undoManager?.removeAllActions()
        }
        container.placeholderLabel.isHidden = !text.isEmpty || placeholder.isEmpty

        guard isEditable, let window = container.window else {
            return
        }
        if isFocused, window.firstResponder !== container.textView {
            window.makeFirstResponder(container.textView)
        }
    }

    private func configureStaticProperties(_ container: AlignedTextContainer) {
        let textView = container.textView
        textView.isSelectable = true
        textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 10, height: 9)
        textView.textContainer?.lineFragmentPadding = 0

        container.placeholderLabel.font = .systemFont(ofSize: 13)
        container.placeholderLabel.textColor = .secondaryLabelColor
    }

    private func updateDynamicProperties(_ container: AlignedTextContainer) {
        let textView = container.textView
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        textView.setAccessibilityPlaceholderValue(placeholder)

        if container.placeholderLabel.stringValue != placeholder {
            container.placeholderLabel.stringValue = placeholder
        }
        container.placeholderLabel.isHidden = !text.isEmpty || placeholder.isEmpty
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        weak var placeholderLabel: NSTextField?

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text.wrappedValue = textView.string
            placeholderLabel?.isHidden = !textView.string.isEmpty
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused.wrappedValue = false
        }
    }
}

final class AlignedTextContainer: NSView {
    let scrollView = NSScrollView()
    let textView = NSTextView()
    let placeholderLabel = PassthroughLabel(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.maximumNumberOfLines = 1

        addSubview(scrollView)
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            placeholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -6
            ),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
