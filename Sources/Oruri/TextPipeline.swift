import Foundation
import AppKit

/// Etapas determinísticas aplicadas ao texto transcrito, nesta ordem:
/// pontuação falada → palavras de preenchimento → dicionário → números → acabamento.
enum TextPipeline {
    static func process(_ raw: String, settings: Settings, dictionary: [DictionaryEntry]) -> String {
        var text = raw
        if settings.numberFormatting != "Off" { text = NumberWords.convertDotted(text) }
        text = applySpokenPunctuation(text)
        if settings.removeFillers { text = removeFillers(text, language: settings.transcriptionLanguage) }
        if settings.spokenEdits { text = SpokenEdits.apply(text) }
        if settings.dictionaryEnabled && settings.customDictionary {
            text = applyDictionary(text, entries: dictionary, soundAlikes: settings.fixSoundAlikes,
                                   language: settings.transcriptionLanguage)
        }
        if settings.numberFormatting != "Off" {
            text = NumberWords.convert(text, preferDigits: settings.numberFormatting == "Prefer digits")
            text = applyPercent(text)
        }
        return tidy(text)
    }

    // MARK: Pontuação falada

    private static let punctuation: [(words: [String], mark: String)] = [
        (["new paragraph", "novo parágrafo", "novo paragrafo"], "\n\n"),
        (["new line", "newline", "nova linha", "próxima linha"], "\n"),
        (["question mark", "ponto de interrogação", "ponto de interrogacao"], "?"),
        (["exclamation mark", "exclamation point", "ponto de exclamação", "ponto de exclamacao"], "!"),
        (["full stop", "ponto final"], "."),
        (["semicolon", "semi colon", "ponto e vírgula", "ponto e virgula"], ";"),
        (["colon", "dois pontos"], ":"),
        (["comma", "vírgula", "virgula"], ","),
        (["period"], "."),
    ]

    /// Troca "vírgula", "period", "nova linha"… pelo sinal, quando ditos depois de uma palavra.
    /// Frases como "billing period" seriam um risco; por isso "period" só vale no fim do texto.
    static func applySpokenPunctuation(_ input: String) -> String {
        var text = input
        for (words, mark) in punctuation {
            for word in words {
                let escaped = NSRegularExpression.escapedPattern(for: word)
                let pattern: String
                if word == "period" {
                    pattern = "(?i)(?<=\\S)[ \\t]*[,.]?[ \\t]+\\bperiod\\b[ \\t]*[,.]?(?=\\s*$)"
                } else {
                    pattern = "(?i)(?<=\\S)[ \\t]*[,.]?[ \\t]+\\b\(escaped)\\b[ \\t]*[,.!?;:]?"
                }
                text = text.replacingOccurrences(of: pattern, with: mark, options: .regularExpression)
            }
        }
        // Espaço depois de pontuação (exceto quebras de linha) e maiúscula após fim de frase.
        // Espaço depois da pontuação, menos entre dígitos: "0.2.1", "1,5" e "10:30" ficam juntos.
        text = text.replacingOccurrences(of: "(?<!\\d)([,;:])(?=\\S)|([,;:])(?=[^\\s\\d])", with: "$1$2 ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?<!\\d)([.?!])(?=[^\\s.?!])|([.?!])(?=[^\\s.?!\\d])", with: "$1$2 ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n[ \\t]+", with: "\n", options: .regularExpression)
        return capitalizeSentences(text)
    }

    // MARK: Porcentagem

    /// "100 por cento" / "50 percent" → "100%" / "50%".
    static func applyPercent(_ input: String) -> String {
        input.replacingOccurrences(of: "(?i)(\\d+(?:[.,]\\d+)?)\\s*(por\\s*cento|percent|per\\s*cent)\\b",
                                   with: "$1%", options: .regularExpression)
    }

    // MARK: Preenchimento

    /// "um" é hesitação em inglês, mas é palavra de verdade em português ("um abraço"); por isso depende do idioma.
    static func fillerPattern(language: String) -> String {
        var words = ["uh+", "er+m*", "hmm+", "hã+", "ãh+", "ahn+", "é+h+"]
        if language == "English" { words += ["um+", "ah+"] }
        return "(?i)(?<![\\p{L}])(" + words.joined(separator: "|") + ")(?![\\p{L}])[,.]?"
    }

    static func removeFillers(_ input: String, language: String) -> String {
        input.replacingOccurrences(of: fillerPattern(language: language), with: "", options: .regularExpression)
    }

    // MARK: Dicionário

    /// 1. Troca exata de "como é ouvido" → grafia correta (palavra inteira, sem diferenciar maiúsculas).
    /// 2. Opcional: corrige palavras parecidas com uma grafia do dicionário, desde que
    ///    a palavra tenha 5+ letras e não seja uma palavra real do idioma (o verificador ortográfico decide).
    static func applyDictionary(_ input: String, entries: [DictionaryEntry], soundAlikes: Bool, language: String) -> String {
        var text = input
        for entry in entries where !entry.spelling.isEmpty {
            for heard in entry.heardAs.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !heard.isEmpty {
                let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: heard))\\b"
                text = text.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: entry.spelling),
                                                 options: .regularExpression)
            }
        }
        guard soundAlikes else { return text }

        let targets = entries.map(\.spelling).filter { $0.count >= 5 && !$0.contains(" ") }
        guard !targets.isEmpty else { return text }
        let checker = NSSpellChecker.shared
        var result = ""
        var lastEnd = text.startIndex
        let wordRegex = try! NSRegularExpression(pattern: "\\p{L}[\\p{L}'-]{3,}")
        for match in wordRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let word = String(text[range])
            var replacement = word
            if !targets.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }),
               isMisspelled(word, checker: checker, languages: spellLanguages(for: language)),
               let best = targets.min(by: { similarity($0, word) > similarity($1, word) }),
               similarity(best, word) >= 0.8 {
                replacement = best
            }
            result += text[lastEnd..<range.lowerBound] + replacement
            lastEnd = range.upperBound
        }
        result += text[lastEnd...]
        return result
    }

    /// Idiomas usados para decidir se uma palavra "existe": inglês sempre, mais o idioma da transcrição.
    static func spellLanguages(for language: String) -> [String] {
        let map = ["Portuguese": "pt_BR", "Spanish": "es", "French": "fr", "German": "de", "Italian": "it"]
        return ["en"] + (map[language].map { [$0] } ?? [])
    }

    private static func isMisspelled(_ word: String, checker: NSSpellChecker, languages: [String]) -> Bool {
        languages.allSatisfy { lang in
            checker.checkSpelling(of: word, startingAt: 0, language: lang, wrap: false,
                                  inSpellDocumentWithTag: 0, wordCount: nil).location != NSNotFound
        }
    }

    /// Similaridade 0…1 baseada na distância de Levenshtein (sem diferenciar maiúsculas).
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a.lowercased()), y = Array(b.lowercased())
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    // MARK: Acabamento

    static func tidy(_ input: String) -> String {
        var text = input
        text = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n[ \\t]+", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "[ \\t]+([,.?!;:])", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "([,.?!;:])\\1+", with: "$1", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespaces)
        return capitalizeSentences(text)
    }

    static func capitalizeSentences(_ input: String) -> String {
        var out = ""
        var capitalizeNext = true
        for ch in input {
            if capitalizeNext, ch.isLetter {
                out += String(ch).uppercased()
                capitalizeNext = false
            } else {
                out.append(ch)
                if ".?!\n".contains(ch) { capitalizeNext = true }
                else if !ch.isWhitespace { capitalizeNext = false }
            }
        }
        return out
    }
}

// MARK: - Números por extenso → dígitos (inglês e português)

enum NumberWords {
    private static let en: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    private static let pt: [String: Int] = [
        "zero": 0, "um": 1, "uma": 1, "dois": 2, "duas": 2, "três": 3, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
        "sete": 7, "oito": 8, "nove": 9, "dez": 10, "onze": 11, "doze": 12, "treze": 13, "catorze": 14, "quatorze": 14,
        "quinze": 15, "dezesseis": 16, "dezessete": 17, "dezoito": 18, "dezenove": 19, "vinte": 20, "trinta": 30,
        "quarenta": 40, "cinquenta": 50, "sessenta": 60, "setenta": 70, "oitenta": 80, "noventa": 90,
        "cem": 100, "cento": 100, "duzentos": 200, "duzentas": 200, "trezentos": 300, "quatrocentos": 400,
        "quinhentos": 500, "seiscentos": 600, "setecentos": 700, "oitocentos": 800, "novecentos": 900,
    ]
    private static let scales: [String: Int] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000, "mil": 1_000, "milhão": 1_000_000, "milhões": 1_000_000,
    ]
    private static let connectors: Set<String> = ["and", "e"]
    /// Expressões que devem continuar por extenso.
    private static let idioms = ["thanks a million", "one of", "one day", "no one", "someone", "anyone", "everyone",
                                 "um dia", "uma vez", "um pouco", "uma pessoa", "um ou outro"]

    /// "zero ponto dois ponto um" → "0.2.1"; "zero point two" → "0.2". Só junta números de uma palavra
    /// (ou já em dígitos) separados por "ponto", "point" ou "dot": versões, decimais e endereços.
    static func convertDotted(_ text: String) -> String {
        let separators: Set<String> = ["ponto", "point", "dot"]
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        func value(_ token: String) -> String? {
            let core = token.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if !core.isEmpty, core.allSatisfy(\.isNumber) { return core }
            if let v = en[core] ?? pt[core], v < 100 { return String(v) }
            return nil
        }
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            if let first = value(tokens[i]), i + 2 < tokens.count,
               separators.contains(tokens[i + 1].lowercased()), value(tokens[i + 2]) != nil {
                var parts = [first]
                var j = i + 1
                var last = tokens[i]
                while j + 1 < tokens.count, separators.contains(tokens[j].lowercased()), let next = value(tokens[j + 1]) {
                    parts.append(next)
                    last = tokens[j + 1]
                    j += 2
                }
                // Mantém a pontuação que estava colada no último número ("um." → "0.2.1.").
                let trailing = String(last.reversed().prefix { $0.isPunctuation }.reversed())
                out.append(parts.joined(separator: ".") + trailing)
                i = j
            } else {
                out.append(tokens[i])
                i += 1
            }
        }
        return out.joined(separator: " ")
    }

    /// Smart: converte números com valor ≥ 10 ou compostos. Prefer digits: converte todos.
    static func convert(_ text: String, preferDigits: Bool) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            if let (value, used, trailing) = parse(tokens, from: i),
               !isIdiom(tokens, at: i),
               preferDigits || value >= 10 || used > 1 {
                out.append("\(value)\(trailing)")
                i += used
            } else {
                out.append(tokens[i])
                i += 1
            }
        }
        return out.joined(separator: " ")
    }

    /// A palavra na posição `i` faz parte de alguma expressão fixa ("thanks a million", "um dia")?
    private static func isIdiom(_ tokens: [String], at i: Int) -> Bool {
        let words = tokens.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        for idiom in idioms {
            let parts = idiom.split(separator: " ").map(String.init)
            for offset in 0..<parts.count {
                let start = i - offset
                guard start >= 0, start + parts.count <= words.count else { continue }
                if Array(words[start..<start + parts.count]) == parts { return true }
            }
        }
        return false
    }

    /// Lê a maior sequência de palavras numéricas a partir de `start`.
    private static func parse(_ tokens: [String], from start: Int) -> (Int, Int, String)? {
        var total = 0, current = 0, used = 0, consumedNumber = false
        var trailing = ""
        var j = start
        while j < tokens.count {
            let raw = tokens[j]
            let core = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let parts = core.split(separator: "-").map(String.init) // "twenty-one"
            var handled = true
            for part in parts {
                // "cento" só é número dentro de "cento e …" ("cento e vinte"); em "por cento" não é.
                let nextIsE = j + 1 < tokens.count && tokens[j + 1].lowercased() == "e"
                if part == "cento" && !nextIsE { handled = false; break }
                // Contas que avisam quando estouram: "hundred hundred…" repetido derrubava o app (Claude Security, F1).
                // Se estourar, desiste e deixa as palavras como estão.
                if let v = en[part] ?? pt[part] {
                    let (sum, over) = current.addingReportingOverflow(v)
                    if over { return nil }
                    current = sum; consumedNumber = true
                } else if part == "hundred" {
                    let (product, over) = max(current, 1).multipliedReportingOverflow(by: 100)
                    if over { return nil }
                    current = product
                } else if let s = scales[part], s >= 1_000 {
                    let (product, over1) = max(current, 1).multipliedReportingOverflow(by: s)
                    let (sum, over2) = total.addingReportingOverflow(product)
                    if over1 || over2 { return nil }
                    total = sum; current = 0; consumedNumber = true
                }
                else if connectors.contains(part) && consumedNumber && j + 1 < tokens.count { }
                else { handled = false }
            }
            guard handled else { break }
            used = j - start + 1
            j += 1
            // Pontuação colada na última palavra ("five," → "5,").
            if let last = raw.last, last.isPunctuation { trailing = String(last); break }
        }
        // Não termina num conector solto ("five and" → só "five").
        while used > 0, connectors.contains(tokens[start + used - 1].lowercased()) { used -= 1 }
        guard consumedNumber, used > 0 else { return nil }
        let (value, over) = total.addingReportingOverflow(current)
        return over ? nil : (value, used, trailing)
    }
}

// MARK: - Correções faladas (sem IA)

/// Trata correções no formato "X <expressão> Y", em que Y substitui o fim de X:
/// "manda pro Pedro, errei, pro Paulo" → "manda pro Paulo";
/// "chego às 3 horas ou melhor às 4 horas" → "chego às 4 horas".
/// Y começa pela mesma palavra do trecho errado ("pro", "às", "na"); essa palavra é procurada em X.
/// Quando não dá para alinhar com segurança, o texto fica como está (a limpeza por IA pode tratar depois).
enum SpokenEdits {
    /// Expressões que só servem para corrigir. "na verdade" e "não" sozinhos ficam de fora: são comuns em frases normais.
    static let strongCues = [
        "não, mentira, falei errado", "mentira, falei errado", "não, falei errado", "falei errado", "não, mentira",
        "não, quer dizer", "não, i mean", "ou melhor", "melhor dizendo", "corrigindo", "errei",
        "no wait", "or rather", "scratch that",
    ]
    /// Expressões que também aparecem em frases normais ("o que quer dizer isso?"): só contam depois de vírgula.
    static let weakCues = ["quer dizer", "i mean", "aliás"]
    /// O trecho errado não costuma passar disso.
    private static let maxReplacedWords = 6

    static func apply(_ input: String) -> String {
        var text = input
        var guardCount = 0
        while guardCount < 5, let edited = applyOnce(text), edited != text {
            text = edited
            guardCount += 1
        }
        return applyNoSentences(text)
    }

    /// Correção numa frase nova que começa com "Não", logo depois da frase errada:
    /// - "…marcado amanhã, né? Não, amanhã depois de amanhã." → troca "amanhã" por "depois de amanhã";
    /// - "…pra quarta-feira. Não é quarta-feira, é segunda-feira." → troca "quarta-feira" por "segunda-feira".
    /// Só age quando a palavra repetida aparece mesmo na frase anterior e não é uma palavra genérica,
    /// para não mexer em respostas como "Não, obrigado" ou "Não, eu prefiro café".
    static func applyNoSentences(_ input: String) -> String {
        let sentenceRegex = try! NSRegularExpression(pattern: "[^.!?\\n]+[.!?]*\\s*")
        let ranges = sentenceRegex.matches(in: input, range: NSRange(input.startIndex..., in: input))
            .compactMap { Range($0.range, in: input) }
        var sentences = ranges.map { String(input[$0]) }
        guard sentences.count >= 2 else { return input }

        var i = 1
        while i < sentences.count {
            let current = sentences[i].trimmingCharacters(in: .whitespaces)
            if let fixed = correct(previous: sentences[i - 1], with: current) {
                sentences[i - 1] = fixed
                sentences.remove(at: i)
            } else {
                i += 1
            }
        }
        return sentences.joined().trimmingCharacters(in: .whitespaces)
    }

    private static func correct(previous: String, with sentence: String) -> String? {
        let body = sentence.trimmingCharacters(in: CharacterSet(charactersIn: ".!? "))
        // "Não é A, é B"
        if let m = body.range(of: "^(?i)não\\s+é\\s+(.+?),?\\s+(?:é|e)\\s+(.+)$", options: .regularExpression) {
            let parts = String(body[m]).replacingOccurrences(of: "^(?i)não\\s+é\\s+", with: "", options: .regularExpression)
            if let split = parts.range(of: ",?\\s+(?:é|e)\\s+", options: .regularExpression) {
                let wrong = String(parts[..<split.lowerBound]).trimmingCharacters(in: .whitespaces)
                let right = String(parts[split.upperBound...]).trimmingCharacters(in: .whitespaces)
                if let replaced = replaceLast(wrong, with: right, in: previous) { return replaced }
            }
        }
        // "Não, W R": W aparece na frase anterior, R é a versão certa.
        guard body.range(of: "^(?i)não\\b,?\\s+", options: .regularExpression) != nil else { return nil }
        let rest = body.replacingOccurrences(of: "^(?i)não\\b,?\\s+", with: "", options: .regularExpression)
        let words = rest.split(separator: " ").map(String.init)
        for length in stride(from: min(3, words.count - 1), through: 1, by: -1) {
            let wrong = words[..<length].joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
            let right = words[length...].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ", "))
            guard !right.isEmpty, wrong.count >= 3, !genericWords.contains(wrong.lowercased()) else { continue }
            if let replaced = replaceLast(wrong, with: right, in: previous) { return replaced }
        }
        return nil
    }

    /// Troca a última ocorrência (palavra inteira, sem diferenciar maiúsculas) de `wrong` por `right`.
    private static func replaceLast(_ wrong: String, with right: String, in text: String) -> String? {
        guard !wrong.isEmpty, !right.isEmpty else { return nil }
        let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: wrong) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let last = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(last.range, in: text) else { return nil }
        return text.replacingCharacters(in: range, with: right)
    }

    /// Palavras que, sozinhas depois de "Não,", não indicam a palavra errada.
    private static let genericWords: Set<String> = [
        "eu", "você", "voce", "ele", "ela", "nós", "a gente", "isso", "isto", "aquilo", "obrigado", "obrigada",
        "sim", "tudo", "nada", "the", "you", "and", "that", "this", "thanks", "não", "mas", "que", "com", "para", "pra",
    ]

    private static func applyOnce(_ text: String) -> String? {
        func alternation(_ list: [String]) -> String {
            list.map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: ", ", with: ",?\\s+") }
                .joined(separator: "|")
        }
        let pattern = "(?i)(?:[,;]?\\s+(?<strong>" + alternation(strongCues) + ")|,\\s*(?:" + alternation(weakCues) + "))[,.]?\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let cueRange = Range(match.range, in: text) else { return nil }
        let isStrong = match.range(withName: "strong").location != NSNotFound

        // X: o que vem antes, dentro da mesma frase. Y: o que vem depois, até o fim da frase.
        let before = String(text[..<cueRange.lowerBound])
        let afterAll = String(text[cueRange.upperBound...])
        let sentenceStart = before.lastIndex(where: { ".!?\n".contains($0) }).map { before.index(after: $0) } ?? before.startIndex
        let x = String(before[sentenceStart...])
        let yEnd = afterAll.firstIndex(where: { ".!?\n".contains($0) }) ?? afterAll.endIndex
        let y = String(afterAll[..<yEnd]).trimmingCharacters(in: .whitespaces)
        let rest = String(afterAll[yEnd...])

        let xWords = x.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !xWords.isEmpty else { return nil }
        let yWords = y.split(separator: " ").map(String.init)
        guard let anchor = yWords.first.map(normalize), !anchor.isEmpty else { return nil }

        // Onde começa o trecho errado em X (o que vem depois da correção sempre vence):
        // 1. a mesma palavra com que a correção começa ("pro Pedro, errei, pro Paulo");
        // 2. se a correção começa com número, o último número dito ("50 reais, quer dizer, 60 reais");
        // 3. senão, a oração inteira antes da correção ("usa o modelo antigo, não, mentira, usa o novo").
        let isArticleLike = articleLike.contains(anchor)
        var index: Int?
        if !(isArticleLike && yWords.count >= 4),
           let i = xWords.lastIndex(where: { normalize($0) == anchor }), xWords.count - i <= maxReplacedWords {
            index = i
        } else if anchor.first?.isNumber == true,
                  let i = xWords.lastIndex(where: { normalize($0).first?.isNumber == true }), xWords.count - i <= maxReplacedWords {
            index = i
        } else if isStrong {
            // Início da oração: depois da última vírgula, ponto e vírgula ou dois-pontos de X.
            index = xWords.lastIndex(where: { $0.hasSuffix(",") || $0.hasSuffix(";") || $0.hasSuffix(":") }).map { $0 + 1 } ?? 0
        }
        guard let index else { return nil }

        var kept = xWords[..<index].joined(separator: " ")
        if kept.hasSuffix(",") || kept.hasSuffix(";") { kept.removeLast() }
        if !kept.isEmpty && (kept.hasSuffix(":")) { kept += "" }
        let prefix = String(before[..<sentenceStart])
        let joined = (kept.isEmpty ? "" : kept + " ") + y
        return prefix + (prefix.isEmpty || prefix.hasSuffix(" ") || prefix.hasSuffix("\n") ? "" : " ") + joined + rest
    }

    /// Palavras curtas e genéricas: como âncora só valem quando a correção também é curta.
    private static let articleLike: Set<String> = ["o", "a", "os", "as", "um", "uma", "the", "an", "de", "do", "da", "e"]

    private static func normalize(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}
