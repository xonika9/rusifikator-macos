import SwiftUI

/// Геометрия кнопки, лежащей поверх текстовой поверхности.
enum TextSurfaceAccessory {
    static let size: CGFloat = 30
    static let inset: CGFloat = 4
}

/// Служебная кнопка-иконка без собственной поверхности.
struct QuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(
                    configuration.isPressed ? AppTheme.text : AppTheme.textSoft
                )
                .background(
                    configuration.isPressed ? AppTheme.surface : .clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .pointerStyle(isEnabled ? .link : nil)
        }
    }
}

/// Кнопка-иконка, которая лежит поверх прокручиваемого текста.
///
/// Подложки у кнопки нет: текст под ней размывается, поэтому у пятна нет ни
/// рамки, ни границы, о которую обрывалась бы строка. Наведение и нажатие
/// меняют только цвет иконки.
struct FloatingIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(iconColor)
                .background {
                    // Пятно шире самой кнопки: край растворяется, поэтому
                    // плотная середина должна перекрывать иконку с запасом.
                    TextSurfaceBlur()
                        .padding(-5)
                        .allowsHitTesting(false)
                }
                .pointerStyle(isEnabled ? .link : nil)
                .onHover { isHovering = $0 }
        }

        private var iconColor: Color {
            guard isEnabled else {
                return AppTheme.textFaint
            }
            if configuration.isPressed {
                return AppTheme.accent
            }
            return isHovering ? AppTheme.text : AppTheme.textSoft
        }
    }
}
