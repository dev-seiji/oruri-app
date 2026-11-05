import SwiftUI

/// Tecla desenhada como "keycap" (ex.: o `fn` na Home).
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.pillBorder))
    }
}

/// Seção de Settings: título cinza + card branco arredondado.
struct SettingsSection<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(T(title))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
        }
    }
}

/// Linha título + descrição + controle à direita.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var info: Bool = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(T(title))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.primaryText)
                    if let badge { Badge(text: badge) }
                    if info {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
                if let subtitle {
                    Text(T(subtitle))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() })
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var info: Bool = false
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, badge: badge, info: info) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Theme.toggleTint)
        }
    }
}

struct PickerRow: View {
    let title: String
    var subtitle: String? = nil
    let options: [String]
    @Binding var selection: String
    var width: CGFloat = 130

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { Text(T($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: width)
        }
    }
}

struct Badge: View {
    let text: String
    var body: some View {
        Text(T(text))
            .font(.system(size: 8.5, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.pillBorder))
    }
}

/// Botão pequeno com borda (ex.: "Open in Finder", "Select").
struct SmallBorderedButton: View {
    let title: String
    var icon: String? = nil
    var dashed = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .medium)) }
                Text(T(title)).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.card))
            .overlay(
                Capsule().stroke(Theme.pillBorder, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : []))
            )
        }
        .buttonStyle(.plain)
    }
}

struct GrantedLabel: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
            Text(T("Granted"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.success)
        }
    }
}
