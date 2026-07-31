import SwiftUI

/// Верхняя панель экрана: заголовок по центру, действия по краям.
///
/// Единственный источник высоты шапки — все экраны поповера собирают её
/// отсюда, поэтому при переходах панель не меняет размер.
struct ScreenHeader<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    let leading: Leading
    let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.text)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textFaint)
            }
            .lineLimit(1)

            HStack(spacing: 2) {
                leading

                Spacer(minLength: 0)

                trailing
            }
            .padding(.horizontal, 10)
        }
        .frame(height: PopoverLayout.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.text.opacity(0.08))
                .frame(height: 1)
        }
    }
}

extension ScreenHeader where Leading == EmptyView {
    init(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String,
        @ViewBuilder leading: () -> Leading
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            leading: leading,
            trailing: { EmptyView() }
        )
    }
}
