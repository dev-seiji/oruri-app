import Foundation
import Observation

/// Idiomas da interface (o idioma da transcrição é outra coisa, fica em Output).
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, es, pt, ja
    var id: String { rawValue }

    /// Nome no próprio idioma, para quem não lê inglês achar o seu.
    var nativeName: String {
        switch self {
        case .en: "English"
        case .es: "Español"
        case .pt: "Português"
        case .ja: "日本語"
        }
    }

    var locale: Locale {
        switch self {
        case .en: Locale(identifier: "en_US")
        case .es: Locale(identifier: "es_ES")
        case .pt: Locale(identifier: "pt_BR")
        case .ja: Locale(identifier: "ja_JP")
        }
    }
}

/// Tradução da interface. O texto em inglês do código é a chave; as traduções ficam em
/// `Localization/<idioma>.json` (copiados para o app pelo build-app.sh). Sem tradução, fica o inglês.
/// É observável: as telas que chamam `T(...)` se redesenham sozinhas quando o idioma muda.
@Observable
final class Localizer {
    static let shared = Localizer()

    var language: AppLanguage = .en {
        didSet { if language != oldValue { load() } }
    }
    @ObservationIgnored private var table: [String: String] = [:]

    func translate(_ english: String) -> String {
        guard language != .en else { return english }
        return table[english] ?? english
    }

    private func load() {
        guard language != .en,
              let url = Bundle.main.url(forResource: language.rawValue, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { table = [:]; return }
        table = dict
    }
}

/// Texto da interface no idioma escolhido.
func T(_ english: String) -> String {
    Localizer.shared.translate(english)
}

/// Texto com valores: a chave usa %@ / %d como em `String(format:)`.
func T(_ english: String, _ args: CVarArg...) -> String {
    String(format: Localizer.shared.translate(english), locale: Localizer.shared.language.locale, arguments: args)
}

import SwiftUI

/// Aplica o idioma escolhido às datas e números das telas (o texto vem de `T(...)`).
private struct LocalizedRoot: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.locale, Localizer.shared.language.locale)
    }
}

extension View {
    func localizedRoot() -> some View { modifier(LocalizedRoot()) }
}
