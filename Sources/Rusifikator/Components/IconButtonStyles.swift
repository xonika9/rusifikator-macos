import SwiftUI

/// Геометрия кнопки, лежащей поверх текстовой поверхности.
enum TextSurfaceAccessory {
    static let size: CGFloat = 30
    static let inset: CGFloat = 4
    /// Очистка и копирование стоят рядом на одном экране, поэтому рисуются
    /// одинаково: один кегль, один вес, обе иконки контурные.
    static let iconSize: CGFloat = 13
}

/// Общий отклик всех кнопок-иконок: под курсором проступает мягкая плашка,
/// нажатие делает её плотнее. Формы в покое нет ни у одной из них.
private struct IconButtonHighlight: View {
    let isHovering: Bool
    let isPressed: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(tint)
    }

    private var tint: Color {
        if isPressed {
            return AppTheme.pressedTint
        }
        return isHovering ? AppTheme.hoverTint : .clear
    }
}

/// Служебная кнопка-иконка без собственной поверхности.
struct QuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(
                    isHovering || configuration.isPressed
                        ? AppTheme.text
                        : AppTheme.textSoft
                )
                .background {
                    IconButtonHighlight(
                        isHovering: isHovering,
                        isPressed: configuration.isPressed
                    )
                }
                .pointerStyle(isEnabled ? .link : nil)
                .onHover { isHovering = $0 }
        }
    }
}

/// Кнопка-иконка, которая лежит поверх прокручиваемого текста.
///
/// Собственной поверхности у кнопки нет: текст под ней гасится пятном цвета
/// самой поверхности, поэтому у пятна нет ни рамки, ни границы, о которую
/// обрывалась бы строка. Отклик на наведение и нажатие — тот же, что у кнопок
/// в шапке.
struct FloatingIconButtonStyle: ButtonStyle {
    /// Цвет поверхности под кнопкой: пятно рисуется им же.
    let surface: Color

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, surface: surface)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let surface: Color

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(iconColor)
                .background {
                    IconButtonHighlight(
                        isHovering: isHovering,
                        isPressed: configuration.isPressed
                    )
                }
                .background {
                    // Пятно шире самой кнопки: край растворяется, поэтому
                    // плотная середина должна перекрывать иконку с запасом.
                    TextSurfaceVeil(surface: surface)
                        .padding(-6)
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
