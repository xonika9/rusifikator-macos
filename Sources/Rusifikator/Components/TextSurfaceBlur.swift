import AppKit
import SwiftUI

/// Размытие текста под кнопкой, лежащей поверх текстовой поверхности.
///
/// Режим `withinWindow` размывает не подложку окна, а то, что нарисовано в
/// самом окне ниже — то есть текст. Края растворяются радиальной маской,
/// поэтому у пятна нет границы, о которую обрывалась бы строка.
struct TextSurfaceBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = FadingVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .headerView
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private final class FadingVisualEffectView: NSVisualEffectView {
    private var maskedSize: CGSize = .zero

    override func layout() {
        super.layout()
        guard bounds.size != maskedSize, bounds.width > 0, bounds.height > 0 else {
            return
        }
        maskedSize = bounds.size
        maskImage = Self.fadeMask(size: bounds.size)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// Непрозрачная середина, растворяющийся край.
    private static func fadeMask(size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(
                colors: [
                    .black,
                    .black,
                    NSColor.black.withAlphaComponent(0)
                ],
                atLocations: [0, 0.58, 1],
                colorSpace: .sRGB
            )
            gradient?.draw(in: rect, relativeCenterPosition: .zero)
            return true
        }
    }
}
