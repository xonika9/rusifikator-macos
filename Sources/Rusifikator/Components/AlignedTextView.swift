import AppKit
import SwiftUI

/// Кнопка SwiftUI, которая лежит в правом верхнем углу текстового поля.
///
/// Само поле её не рисует, но обязано знать её место: под кнопкой находится
/// `NSTextView`, и без этого он ставит там каретку вместо указателя.
struct TextAccessoryButton: Equatable {
    let size: CGSize
    let inset: CGFloat
    let isEnabled: Bool
}

struct AlignedTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let placeholder: String
    let isEditable: Bool
    let trailingAccessoryButton: TextAccessoryButton?

    init(
        text: Binding<String>,
        isFocused: Binding<Bool> = .constant(false),
        placeholder: String = "",
        isEditable: Bool = true,
        trailingAccessoryButton: TextAccessoryButton? = nil
    ) {
        _text = text
        _isFocused = isFocused
        self.placeholder = placeholder
        self.isEditable = isEditable
        self.trailingAccessoryButton = trailingAccessoryButton
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> AlignedTextContainer {
        let container = AlignedTextContainer()
        container.textView.delegate = context.coordinator
        context.coordinator.placeholderLabel = container.placeholderLabel
        context.coordinator.container = container
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
            container.layOutWholeText()
        }

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
        container.trailingAccessoryButton = trailingAccessoryButton
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
        weak var container: AlignedTextContainer?

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

            // Вставка большого текста приходит сюда, а не через обновление
            // связанного значения: ползунок должен сразу знать полный объём.
            container?.layOutWholeText()
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
    let textView = AccessoryAwareTextView()
    let placeholderLabel = PassthroughLabel(labelWithString: "")
    private let accessoryCursorView = AccessoryCursorView()

    var trailingAccessoryButton: TextAccessoryButton? {
        didSet {
            guard trailingAccessoryButton != oldValue else {
                return
            }
            updateScrollerInsets()
            needsLayout = true
        }
    }

    /// Место кнопки в координатах поля, если она есть.
    var accessoryButtonFrame: NSRect? {
        guard let button = trailingAccessoryButton,
              button.size.width > 0,
              button.size.height > 0 else {
            return nil
        }
        return NSRect(
            x: bounds.maxX - button.inset - button.size.width,
            y: bounds.maxY - button.inset - button.size.height,
            width: button.size.width,
            height: button.size.height
        )
    }

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
        textView.accessoryHost = self

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.maximumNumberOfLines = 1

        addSubview(scrollView)
        addSubview(placeholderLabel)

        // Область указателя лежит выше текста: из перекрывающихся областей
        // курсора система берёт ту, что принадлежит верхнему представлению.
        accessoryCursorView.isHidden = true
        addSubview(accessoryCursorView)

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: accessoryCursorView)
    }

    private var laidOutWidth: CGFloat = -1

    override func layout() {
        super.layout()
        updateAccessoryCursorArea()

        // Ширина задаёт переносы строк, поэтому после её изменения весь текст
        // раскладывается заново. Повторные проходы при той же ширине не нужны
        // и только зациклили бы раскладку.
        if bounds.width != laidOutWidth {
            laidOutWidth = bounds.width
            layOutWholeText()
        }
    }

    /// Полоса прокрутки начинается ниже кнопки: под кнопку она уходить не
    /// должна, иначе ползунок и иконка налезают друг на друга.
    private func updateScrollerInsets() {
        guard let button = trailingAccessoryButton else {
            scrollView.scrollerInsets = NSEdgeInsets()
            return
        }
        scrollView.scrollerInsets = NSEdgeInsets(
            top: button.inset * 2 + button.size.height,
            left: 0,
            bottom: 0,
            right: 0
        )
    }

    private func updateAccessoryCursorArea() {
        guard let frame = accessoryButtonFrame else {
            accessoryCursorView.isHidden = true
            return
        }
        accessoryCursorView.isHidden = false
        accessoryCursorView.frame = frame
        accessoryCursorView.cursor =
            trailingAccessoryButton?.isEnabled == true ? .pointingHand : .arrow
        window?.invalidateCursorRects(for: accessoryCursorView)
    }

    /// Раскладывает весь текст, а не только видимую часть.
    ///
    /// По умолчанию раскладка ленивая: высота документа растёт по мере
    /// прокрутки, поэтому ползунок сначала выглядит длиннее, чем должен, и
    /// уменьшается на ходу. После полной раскладки он сразу показывает
    /// настоящий объём текста.
    func layOutWholeText() {
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
            return
        }
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
    }
}

/// Прозрачная площадка под кнопкой, которая владеет только курсором.
///
/// Кнопку рисует и обрабатывает SwiftUI выше, поэтому нажатия сюда не
/// заходят: `hitTest` пропускает их дальше.
final class AccessoryCursorView: NSView {
    var cursor: NSCursor = .pointingHand {
        didSet {
            guard cursor !== oldValue else {
                return
            }
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Текстовое поле, которое уступает угол с кнопкой.
///
/// Каретку над текстом `NSTextView` ставит и по областям курсора, и на каждом
/// движении мыши. Второй путь перебивает любые чужие области, поэтому поле
/// должно уступать угол с кнопкой само.
final class AccessoryAwareTextView: NSTextView {
    weak var accessoryHost: AlignedTextContainer?

    override func mouseMoved(with event: NSEvent) {
        guard applyAccessoryCursor(for: event) else {
            super.mouseMoved(with: event)
            return
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        guard applyAccessoryCursor(for: event) else {
            super.cursorUpdate(with: event)
            return
        }
    }

    private func applyAccessoryCursor(for event: NSEvent) -> Bool {
        guard let host = accessoryHost,
              let frame = host.accessoryButtonFrame else {
            return false
        }
        let point = host.convert(event.locationInWindow, from: nil)
        guard frame.contains(point) else {
            return false
        }
        if host.trailingAccessoryButton?.isEnabled == true {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
        return true
    }
}

final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
