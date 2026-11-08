import AppKit
import SwiftUI

/// Janela principal (0.7.0, "Canto"): barra lateral fina com Home, Histórico, Uso e Ajuda,
/// a linha do canto no centro da Home, uma barra fina no topo e Settings numa gaveta que desliza da direita.
struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @AppStorage(OnboardingKeys.completed) private var onboardingCompleted = false

    var body: some View {
        @Bindable var state = state
        ZStack {
            StageBackground()

            VStack(spacing: 0) {
                TopBar()
                HStack(spacing: 0) {
                    SideRail()
                        .zIndex(1)
                    ZStack {
                        switch state.selectedTab {
                        case .home: HomeView()
                        case .history: HistoryPage()
                        case .usage: RailPage(title: "Usage") { UsagePane() }
                        case .help: RailPage(title: "Help") { HelpPane() }
                        case .dictionary: DictionaryView()
                        }
                    }
                    .transition(.opacity)
                    .id(state.selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay {
                        // Barra presa aberta: clicar fora dela fecha.
                        if state.railPinned {
                            Color.clear.contentShape(Rectangle()).onTapGesture { state.railPinned = false }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: state.selectedTab)
            }

            if state.showPro {
                // A faixa do topo fica livre: clicar em "Pro" de novo também fecha a janelinha.
                VStack(spacing: 0) {
                    Color.clear.frame(height: 36)
                    Theme.dimOverlay
                        .contentShape(Rectangle())
                        .onTapGesture { state.showPro = false }
                }
                .transition(.opacity)
                .zIndex(0.5)
                // A janelinha cresce um pouco e aparece; ao fechar, encolhe e some.
                ProView()
                    .padding(.top, 36)
                    .transition(.scale(scale: 0.88).combined(with: .opacity).combined(with: .offset(y: 14)))
                    .zIndex(0.6)
            }

            if state.showSettings {
                Theme.dimOverlay
                    .contentShape(Rectangle())
                    .onTapGesture { state.showSettings = false }
                    .transition(.opacity)
                    .zIndex(1)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    SettingsView()
                        .frame(width: 470)
                        .shadow(color: .black.opacity(0.22), radius: 18, x: -6)
                }
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: state.showSettings)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: state.showPro)
        .overlay(alignment: .top) {
            if let toast = state.toast {
                Text(T(toast))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.toastBackground.opacity(0.96)))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    .padding(.top, 44)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: state.toast)
        .onAppear {
            if !onboardingCompleted { openWindow(id: "onboarding") }
        }
    }
}

/// Fundo da janela: um brilho verde suave atrás do microfone.
struct StageBackground: View {
    var body: some View {
        GeometryReader { geo in
            RadialGradient(colors: [Theme.stageGlow, Theme.contentBackground],
                           center: UnitPoint(x: 0.5, y: 0.38),
                           startRadius: 0,
                           endRadius: max(geo.size.width, geo.size.height) * 0.55)
        }
        .ignoresSafeArea()
    }
}

/// Barra do topo: marca à esquerda; Dictionary, Pro, tema e Settings à direita.
struct TopBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            if state.selectedTab == .dictionary {
                TopIconButton(icon: "chevron.left") { go(.home) }
                    .help(T("Back to Home"))
                    .keyboardShortcut("[", modifiers: .command)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            Text(T("Oruri"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
            if state.selectedTab != .home {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                    Text(T(state.selectedTab.rawValue))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                .transition(.opacity)
            }
            Spacer()
            // Botões da direita um pouco abaixo e longe da borda (pedido do usuário); a esquerda fica alinhada aos botões da janela.
            HStack(spacing: 8) {
            if state.selectedTab != .dictionary {
                TopPill(icon: "character.book.closed", title: "Dictionary") { go(.dictionary) }
            } else {
                TopPill(icon: "mic", title: "Home") { go(.home) }
            }
            TopPill(icon: "sparkles", title: "Pro", iconColor: Theme.highlight, isActive: state.showPro) {
                state.showPro.toggle()
            }
            ThemeButton()
            TopIconButton(icon: "gearshape") {
                state.showPro = false
                state.openSettings(state.settingsPane)
            }
                .help(T("Settings"))
            }
            .offset(y: 7)
            .padding(.trailing, 6)
        }
        .padding(.leading, 84)
        .padding(.trailing, 10)
        .padding(.top, 1)
        .frame(height: 30)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.28), value: state.selectedTab)
    }

    private func go(_ tab: MainTab) {
        withAnimation(.easeInOut(duration: 0.28)) { state.selectedTab = tab }
    }
}

/// Barra lateral: fina, só ícones; ao passar o mouse abre por cima do conteúdo e mostra os nomes.
/// O botão de menu (três linhas) deixa ela aberta até clicar nele de novo ou fora dela.
struct SideRail: View {
    @Environment(AppState.self) private var state
    @LocalState private var hovering = false

    static let collapsedWidth: CGFloat = 56
    private var open: Bool { hovering || state.railPinned }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            item(icon: "line.3.horizontal", title: "Menu", selected: state.railPinned) {
                state.railPinned.toggle()
            }
            .padding(.bottom, 4)
            ForEach([MainTab.home, .history, .usage, .help]) { tab in
                item(icon: tab.icon, title: tab.rawValue, selected: state.selectedTab == tab) {
                    withAnimation(.easeInOut(duration: 0.22)) { state.selectedTab = tab }
                }
            }
            Spacer()
        }
        .padding(.top, 10)
        .padding(.horizontal, 10)
        .frame(width: open ? 190 : Self.collapsedWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(open ? Theme.settingsBackground : Color.clear)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.divider).frame(width: 1) }
        .shadow(color: .black.opacity(open ? 0.18 : 0), radius: 12, x: 4)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: open)
        .frame(width: Self.collapsedWidth, alignment: .leading) // aberta, passa por cima do conteúdo sem empurrar
    }

    private func item(icon: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 36, height: 36)
                if open {
                    Text(T(title))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.accentSoft : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(T(title))
        .accessibilityLabel(T(title))
    }
}

/// Página da barra lateral com título e rolagem (Uso e Ajuda, que antes ficavam na gaveta de Settings).
struct RailPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(T(title))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                content
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }
}

struct TopPill: View {
    let icon: String
    let title: String
    var iconColor: Color = Theme.secondaryText
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(iconColor)
                Text(T(title)).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isActive ? Theme.primaryText : Theme.secondaryText)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(isActive ? Theme.highlightSoft : Theme.card))
            .overlay(Capsule().stroke(isActive ? Theme.highlightBorder : Theme.pillBorder))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct TopIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.card))
                .overlay(Circle().stroke(Theme.pillBorder))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Botão de tema: sol quando o app está claro, lua quando está escuro (em "System", segue o Mac).
/// O clique abre um balão com System, Light e Dark.
struct ThemeButton: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @LocalState private var showing = false

    var body: some View {
        TopIconButton(icon: colorScheme == .dark ? "moon.fill" : "sun.max.fill") { showing.toggle() }
            .help(T("Appearance"))
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("Appearance"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        row(mode)
                    }
                }
                .padding(10)
                .frame(width: 200)
            }
    }

    private func row(_ mode: AppearanceMode) -> some View {
        let selected = state.settings.appearance == mode.rawValue
        return Button {
            state.settings.appearance = mode.rawValue
            showing = false
        } label: {
            HStack(spacing: 9) {
                Image(systemName: mode.icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                Text(mode.shortTitle).font(.system(size: 13)).foregroundStyle(Theme.primaryText)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accentSoft : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Janelinha do Oruri Pro, aberta sobre a Home: convite para a lista de espera (o plano ainda não existe).
/// Fecha pelo X, pelo Esc, clicando fora ou clicando em "Pro" de novo.
struct ProView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.highlight)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.highlightSoft))
                    .overlay(Circle().stroke(Theme.highlightBorder))
                    .offset(x: 4, y: 2)
            }
            Text(T("Oruri Pro"))
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
            Text(T("Oruri Pro is coming: cloud transcription that works right after you install, with no API key to set up. Join the waitlist to hear when it's ready."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let url = AppInfo.waitlistURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text(T("Join the waitlist"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(Capsule().fill(Theme.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(T("Opens in your browser"))
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 30)
        .padding(.bottom, 28)
        .frame(width: 380)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.settingsBackground))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardBorder))
        .overlay(alignment: .topTrailing) {
            Button { state.showPro = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.cardBorder))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(T("Close"))
            .padding(12)
        }
        .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
    }
}
