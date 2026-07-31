import SwiftUI

/// Пятно, которое гасит текст под кнопкой, лежащей поверх текстовой поверхности.
///
/// Пятно рисуется цветом той поверхности, на которой лежит, поэтому на белом
/// поле его не видно так же, как на сером. Системный материал этого не умеет:
/// он подмешивает собственный почти белый тон и на серой поверхности читается
/// как светлое пятно.
///
/// Край растворяется, поэтому у пятна нет границы, о которую обрывалась бы
/// строка.
struct TextSurfaceVeil: View {
    /// Цвет поверхности, поверх которой лежит кнопка.
    let surface: Color

    var body: some View {
        GeometryReader { proxy in
            let diameter = max(proxy.size.width, proxy.size.height)
            RadialGradient(
                stops: [
                    .init(color: surface, location: 0),
                    .init(color: surface, location: Self.solidPortion),
                    .init(color: surface.opacity(0), location: 1)
                ],
                center: .center,
                startRadius: 0,
                endRadius: diameter / 2
            )
        }
        .allowsHitTesting(false)
    }

    /// Доля радиуса, на которой пятно ещё полностью непрозрачно: под иконкой
    /// текста не должно быть видно совсем.
    private static let solidPortion: CGFloat = 0.56
}
