import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: opacity))
    }

    /// Cor que muda sozinha entre o modo claro e o escuro.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    init(light: UInt32, dark: UInt32) {
        self.init(light: NSColor(hex: light), dark: NSColor(hex: dark))
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Paleta do Oruri: azul ruri (瑠璃色, o azul lápis-lazúli que dá nome à ōruri) como cor principal
/// e dourado só em detalhes, como o plano Pro. Cada token tem a versão clara (aprovada) e a escura.
enum Theme {
    // Paleta aprovada (claro) / equivalente no escuro
    static let brand = Color(light: 0x1E50A2, dark: 0x6E95E0)       // primária
    static let brandDeep = Color(light: 0x0F2350, dark: 0xBCD0F5)   // texto de destaque
    static let brandSoft = Color(light: 0xE6EDF8, dark: 0x17233D)   // fundo do item selecionado
    static let highlight = Color(light: 0xC99A1E, dark: 0xE3B94A)   // dourado: Pro e detalhes
    static let highlightSoft = Color(light: 0xFBF3DC, dark: 0x33291A)

    static let contentBackground = Color(light: 0xFFFFFF, dark: 0x0D1220)
    static let divider = Color(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.08))

    static let statsBackground = Color(light: 0xF4F6FA, dark: 0x161D2E)
    static let statsBorder = Color(light: 0xD6DEEA, dark: 0x26324A)

    static let pillBackground = Color(light: 0xF4F6FA, dark: 0x161D2E)
    static let pillBorder = Color(light: NSColor(white: 0, alpha: 0.10), dark: NSColor(white: 1, alpha: 0.12))

    static let primaryText = Color(light: 0x1A1F2B, dark: 0xE8ECF4)
    static let secondaryText = Color(light: 0x5D6573, dark: 0xA2ABBC)
    static let tertiaryText = Color(light: 0x868E9B, dark: 0x737D90)

    static let accent = brand
    static let accentSoft = brandSoft
    static let highlightBorder = Color(light: NSColor(hex: 0xC99A1E, alpha: 0.45), dark: NSColor(hex: 0xE3B94A, alpha: 0.35))

    static let recordTop = Color(light: 0x3768C4, dark: 0x8DADEA)
    static let recordBottom = brand

    static let success = brand

    /// Fundo da bolha de gravação (a mesma cor nos dois modos).
    static let indicatorBackground = Color(light: NSColor(white: 0.09, alpha: 0.94), dark: NSColor(white: 0.09, alpha: 0.94))
    static let indicatorBorder = Color(light: NSColor(white: 1, alpha: 0.12), dark: NSColor(white: 1, alpha: 0.12))

    /// Fundo dos avisos flutuantes (texto branco por cima nos dois modos).
    static let toastBackground = Color(light: 0x0F2350, dark: 0x1E3A6E)

    static let settingsBackground = Color(light: 0xF8F9FC, dark: 0x111829)
    static let card = Color(light: 0xFFFFFF, dark: 0x161D2E)

    // Layout "Palco": brilho atrás do microfone, anéis em volta dele e a gaveta de Settings
    static let stageGlow = Color(light: 0xE6EDF8, dark: 0x17233D)
    static let stageRing = Color(light: NSColor(hex: 0x1E50A2, alpha: 0.10), dark: NSColor(hex: 0x6E95E0, alpha: 0.14))
    static let stageRingOuter = Color(light: NSColor(hex: 0x1E50A2, alpha: 0.05), dark: NSColor(hex: 0x6E95E0, alpha: 0.07))
    static let dimOverlay = Color(light: NSColor(white: 0, alpha: 0.22), dark: NSColor(white: 0, alpha: 0.50))
    static let recording = Color(light: 0xD94A3D, dark: 0xE5675B)
    static let recordingTop = Color(light: 0xE8695D, dark: 0xF07F74)
    static let toggleTint = brand
    /// Texto sobre a cor primária (branco no claro, quase preto no escuro).
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0D1220)
    static let cardBorder = Color(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.10))
}

/// Aparência escolhida em Settings › Advanced.
enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var title: String {
        switch self {
        case .system: T("Match system")
        case .light: T("Light")
        case .dark: T("Dark")
        }
    }

    /// Nome curto usado no botão de tema do topo.
    var shortTitle: String { self == .system ? T("System") : title }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
