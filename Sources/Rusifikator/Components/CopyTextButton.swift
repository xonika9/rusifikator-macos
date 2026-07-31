import SwiftUI

/// Кнопка «скопировать», которая лежит в углу текстовой поверхности.
///
/// Отметку об удавшемся копировании держит вызывающий экран: у редактора она
/// живёт в модели, у истории — рядом с открытой записью.
struct CopyTextButton: View {
    let isConfirming: Bool
    /// Цвет поверхности, на которой лежит кнопка.
    let surface: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isConfirming ? "checkmark" : "doc.on.doc")
                .font(.system(size: TextSurfaceAccessory.iconSize))
                .frame(
                    width: TextSurfaceAccessory.size,
                    height: TextSurfaceAccessory.size
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(FloatingIconButtonStyle(surface: surface))
        .help(title)
        .accessibilityLabel(title)
    }

    private var title: String {
        isConfirming ? "Скопировано" : "Скопировать готовый текст"
    }
}
