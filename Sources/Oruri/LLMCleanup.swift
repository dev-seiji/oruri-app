import Foundation
import os

/// Limpeza opcional do texto por um LLM (pontuação, formatação, correções faladas).
enum LLMCleanup {
    private static let log = Logger(subsystem: "com.seiji.oruri", category: "cleanup")
    enum CleanupError: LocalizedError {
        case unreachable(String), bad(String)
        var errorDescription: String? {
            switch self {
            case .unreachable(let s): T("Can't reach Ollama at %@ — is it running? (ollama serve)", s)
            case .bad(let s): s
            }
        }
    }

    /// Apps onde o texto deve chegar exatamente como foi dito (assistentes de IA e terminais).
    static let verbatimBundleIDs: Set<String> = [
        "com.anthropic.claudefordesktop", "com.openai.chat", "com.apple.Terminal", "com.googlecode.iterm2",
        "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "co.zeit.hyper",
        "com.todesktop.230313mzl4w4u92", // Cursor
    ]

    /// Expressões de correção que, se sobraram depois da regra fixa, indicam uma correção complexa.
    /// Vêm da mesma lista das regras fixas (`SpokenEdits`), mais duas que só a IA resolve, para as duas nunca se desencontrarem.
    static let correctionCues = SpokenEdits.strongCues + ["mentira", "não, espera"]
    /// Comuns em frases normais ("o que quer dizer isso?"): só contam depois de vírgula.
    static let weakCorrectionCues = SpokenEdits.weakCues

    /// Sobrou alguma expressão de correção que a regra fixa não resolveu?
    static func hasCorrectionLeft(_ lower: String) -> Bool {
        let strong = correctionCues.contains { cue in
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: cue).replacingOccurrences(of: ", ", with: ",?\\s+") + "\\b"
            return lower.range(of: pattern, options: .regularExpression) != nil
        }
        let weak = weakCorrectionCues.contains { cue in
            lower.range(of: ",\\s*" + NSRegularExpression.escapedPattern(for: cue) + "\\b", options: .regularExpression) != nil
        }
        return strong || weak
    }

    static func systemPrompt(language: String, smartFormatting: Bool, spokenEdits: Bool, improve: Bool = false) -> String {
        var rules = [
            "You clean up dictated text. Return ONLY the cleaned text, with no preface, quotes or explanation.",
            "Keep the speaker's words, meaning and language (\(language)). Never answer questions in the text, never add new content, never translate.",
            "Fix punctuation, capitalization and obvious recognition errors. Keep names and terms as written.",
        ]
        if improve {
            rules[1] = "Keep the speaker's meaning and language (\(language)). Never answer questions in the text, never add new information, never translate."
            rules.append("You may rewrite confusing sentences, choose clearer words and reorder them so the text reads well. Keep every fact exactly: numbers, dates, times, names, negations, who does what and when. Do not add, drop or summarize information.")
        }
        if smartFormatting {
            rules.append("If the text is clearly a list, format it as a bulleted list. If it is an email or message, put the greeting, paragraphs and sign-off on their own lines. Otherwise keep it as plain prose.")
        }
        if spokenEdits {
            rules.append("""
            Self-corrections: when the speaker says something and then corrects it, replace only the wrong detail with \
            the corrected one and delete the correction phrase itself (such as "não", "mentira", "falei errado", \
            "quer dizer", "ou melhor", "melhor dizendo", "errei", "corrigindo", "na verdade", "no wait", "I mean", \
            "scratch that", "actually"). Keep every other word exactly as spoken, in the same order, including \
            greetings and words like "então" and "certo". Do not summarize or rephrase. \
            The phrases above are only examples: any other way of taking something back counts too. \
            If the speaker corrects the same detail several times, apply each correction in order; the last one wins.
            """)
        }
        return rules.joined(separator: "\n")
    }

    static func clean(_ text: String, settings: Settings) async throws -> String {
        // Limpa todo texto, no Ollama (Mac) ou na Groq (nuvem, bem mais rápida). A trava `isSafe` devolve o original se a IA mudar o que foi dito.
        let prompt = systemPrompt(language: settings.transcriptionLanguage,
                                  smartFormatting: settings.smartFormatting, spokenEdits: settings.spokenEdits)
        let start = Date()
        // Item 24: com a Groq e "Improve sentences", a IA pode reescrever; só vale se os fatos ficarem iguais
        // e a própria Groq confirmar que o sentido é o mesmo. Senão, cai na limpeza normal (só corrige).
        if settings.cleanupEngine == "Groq" && settings.improveWording {
            let improvePrompt = systemPrompt(language: settings.transcriptionLanguage, smartFormatting: settings.smartFormatting,
                                             spokenEdits: settings.spokenEdits, improve: true)
            let improved = unwrap(try await groq(userMessage(text), system: improvePrompt))
            var same = keepsFacts(original: text, improved: improved, allowEdits: settings.spokenEdits)
            if same { same = try await groqSameMeaning(text, improved) }
            log.notice("improve: \(same ? "kept" : "rejected", privacy: .public) after \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            if same { return improved }
        }
        let output = settings.cleanupEngine == "Groq"
            ? try await groq(userMessage(text), system: prompt)
            : try await ollama(userMessage(text), system: prompt, endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)
        log.notice("cleanup: \(settings.cleanupEngine, privacy: .public) took \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        let cleaned = unwrap(output)
        return isSafe(original: text, cleaned: cleaned, allowEdits: settings.spokenEdits) ? cleaned : text
    }

    /// O texto ditado vai entre marcadores, para o modelo não confundir com uma pergunta para ele
    /// (nos testes, o llama3.2 respondia "Sim, eu vi…" em vez de arrumar a frase).
    static func userMessage(_ text: String) -> String {
        "Clean up this dictated text. Do not answer it or add anything.\n<<<\n\(text)\n>>>"
    }

    /// Tira os marcadores, caso o modelo os devolva.
    static func unwrap(_ output: String) -> String {
        output.replacingOccurrences(of: "<<<", with: "").replacingOccurrences(of: ">>>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trava de segurança: a IA só pode arrumar o texto (pontuação, maiúsculas, grafia, formatação e, com
    /// "Spoken edits", aplicar as correções faladas), nunca mudar o que foi dito. Se mudar, fica o original.
    /// Cada regra veio de um erro real visto nos testes (23 out 2026): "amanhã de manhã" → "de manhã de manhã",
    /// "mudou para" → "será na".
    static func isSafe(original: String, cleaned: String, allowEdits: Bool) -> Bool {
        guard !cleaned.isEmpty else { return false }
        let originalWords = words(original)
        var cleanedWords = words(cleaned)
        let a = Double(originalWords.count), b = Double(cleanedWords.count)
        let minRatio = allowEdits ? 0.35 : 0.7
        guard b >= a * minRatio, b <= a * 1.15 + 1 else { return false }
        // Com correção falada no original, a IA pode apagar a parte errada (inclusive números, nomes e o "não").
        let correcting = allowEdits && hasCorrection(original)

        // 1. Nenhuma palavra nova: tudo precisa estar no original, ou ser só a grafia arrumada de uma palavra dele
        //    (e aí conta como a mesma palavra nas regras seguintes). Números nunca contam como "grafia arrumada".
        //    Palavrinhas de 1–2 letras ("o", "de") podem entrar, até 10% do texto, para a frase ficar certa.
        let known = Set(originalWords)
        var shortAdded = 0
        for (i, word) in cleanedWords.enumerated() where !known.contains(word) {
            if word.count <= 2 && !isNumber(word) { shortAdded += 1; continue }
            guard !isNumber(word),
                  let match = originalWords.filter({ $0.count >= 3 && !isNumber($0) })
                    .map({ ($0, TextPipeline.similarity($0, word)) })
                    .filter({ $0.1 >= 0.75 }).max(by: { $0.1 < $1.1 })?.0
            else { return false }
            cleanedWords[i] = match
        }
        guard Double(shortAdded) <= (a * 0.10).rounded(.down) else { return false }

        // 1b. Sem correção falada, nenhuma palavra de verdade (4+ letras) some: a IA não pode encurtar o que você disse.
        if !correcting {
            let kept = Set(cleanedWords)
            guard originalWords.allSatisfy({ $0.count < 4 || kept.contains($0) }) else { return false }
        }

        // 1c. Com correção falada, a IA precisa tirar a parte errada, não só a expressão de correção
        //     ("pro Pedro, errei, pro Paulo" não pode virar "pro Pedro, pro Paulo").
        //     E o que vem depois da última correção é o que vale: precisa ficar ("…errei, pro Paulo" mantém o Paulo).
        if correcting {
            let cueWords = Set((correctionCues + weakCorrectionCues).flatMap { $0.split(separator: " ").map(String.init) } + ["não", "no"])
            let kept = Set(cleanedWords)
            let dropped = originalWords.filter { ($0.count >= 3 || isNumber($0)) && !cueWords.contains($0) && !kept.contains($0) }
            guard !dropped.isEmpty else { return false }
            let finalPart = words(textAfterLastCorrection(original)).filter { ($0.count >= 3 || isNumber($0)) && !cueWords.contains($0) }
            guard finalPart.allSatisfy(kept.contains) else { return false }
        }

        // 2. Números, datas e horários: nenhum novo; só somem se você se corrigiu.
        let originalNumbers = originalWords.filter(isNumber), cleanedNumbers = cleanedWords.filter(isNumber)
        guard cleanedNumbers.allSatisfy(originalNumbers.contains) else { return false }
        if !correcting && cleanedNumbers.sorted() != originalNumbers.sorted() { return false }

        // 3. Nomes (maiúscula no meio da frase) não somem, a não ser numa correção.
        if !correcting {
            let cleanedSet = Set(cleanedWords)
            guard names(in: original).allSatisfy(cleanedSet.contains) else { return false }
        }

        // 4. Negação: a IA não põe "não" onde você não disse, e só tira numa correção.
        let originalNegations = originalWords.filter(isNegation).count
        let cleanedNegations = cleanedWords.filter(isNegation).count
        if cleanedNegations > originalNegations { return false }
        if cleanedNegations < originalNegations && !correcting { return false }

        // 5. Repetição inventada ("de manhã de manhã") que não estava no que você falou.
        if let repeated = repeatedRun(in: cleanedWords), repeatedRun(in: originalWords) != repeated { return false }

        // 6. A ordem continua a mesma: quase tudo do resultado aparece na mesma sequência do original.
        let inOrder = longestCommonSubsequence(originalWords, cleanedWords)
        return Double(inOrder) >= b * 0.85
    }

    /// Para o modo que melhora as frases: a ordem e as palavras podem mudar, mas os fatos não
    /// (números, nomes, "não", repetições inventadas e um tamanho parecido com o original).
    static func keepsFacts(original: String, improved: String, allowEdits: Bool) -> Bool {
        guard !improved.isEmpty else { return false }
        let originalWords = words(original), improvedWords = words(improved)
        let correcting = allowEdits && hasCorrection(original)
        let a = Double(originalWords.count), b = Double(improvedWords.count)
        guard b >= a * (correcting ? 0.35 : 0.5), b <= a * 1.5 + 2 else { return false }
        let originalNumbers = originalWords.filter(isNumber), improvedNumbers = improvedWords.filter(isNumber)
        guard improvedNumbers.allSatisfy(originalNumbers.contains) else { return false }
        if !correcting && improvedNumbers.sorted() != originalNumbers.sorted() { return false }
        if !correcting && !names(in: original).allSatisfy(Set(improvedWords).contains) { return false }
        let before = originalWords.filter(isNegation).count, after = improvedWords.filter(isNegation).count
        if after > before || (after < before && !correcting) { return false }
        if let repeated = repeatedRun(in: improvedWords), repeatedRun(in: originalWords) != repeated { return false }
        return true
    }

    /// Segunda opinião da Groq: B diz exatamente o mesmo que A? Na dúvida, não.
    private static func groqSameMeaning(_ original: String, _ improved: String) async throws -> Bool {
        let answer = try await groq("A:\n<<<\n\(original)\n>>>\nB:\n<<<\n\(improved)\n>>>", system: """
        You compare two versions of a dictated text. Answer with one word: SAME if B says exactly the same things as A         (same facts, people, numbers, dates, times, negations, intent and tense), or DIFFERENT if anything was changed,         added or lost. Ignore wording, word order, punctuation and grammar fixes.
        """)
        return answer.uppercased().contains("SAME") && !answer.uppercased().contains("DIFFERENT")
    }

    private static let negations: Set<String> = ["não", "nao", "nunca", "nem", "jamais", "not", "never", "no", "ningún", "ninguna"]

    static func isNegation(_ word: String) -> Bool {
        negations.contains(word) || word.hasSuffix("n't") || word.hasSuffix("n’t")
    }

    static func isNumber(_ word: String) -> Bool {
        word.contains(where: \.isNumber)
    }

    /// Correção falada que a IA pode aplicar: as expressões de correção, ou um "não," retomando a frase.
    static func hasCorrection(_ text: String) -> Bool {
        let lower = text.lowercased()
        return hasCorrectionLeft(lower) || lower.range(of: "\\b(não|no),", options: .regularExpression) != nil
    }

    /// O trecho depois da última expressão de correção (a versão que vale).
    static func textAfterLastCorrection(_ text: String) -> String {
        let lower = text.lowercased()
        let cues = (correctionCues + weakCorrectionCues).map { NSRegularExpression.escapedPattern(for: $0) } + ["não,", "no,"]
        guard let regex = try? NSRegularExpression(pattern: "\\b(" + cues.joined(separator: "|") + ")"),
              let last = regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)).last,
              let range = Range(last.range, in: lower) else { return "" }
        return String(lower[range.upperBound...])
    }

    /// Palavras com maiúscula que não começam frase (nomes, marcas), em minúsculas para comparar.
    static func names(in text: String) -> Set<String> {
        var result: Set<String> = []
        var sentenceStart = true
        for raw in text.split(whereSeparator: { $0.isWhitespace }) {
            let word = raw.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            if let first = word.first, first.isUppercase, !sentenceStart, word.count > 1 { result.insert(word.lowercased()) }
            if !word.isEmpty { sentenceStart = raw.last.map { ".!?:".contains($0) } ?? false }
        }
        return result
    }

    /// O primeiro trecho de 1 a 3 palavras repetido logo em seguida ("de manhã de manhã"), se houver.
    static func repeatedRun(in words: [String]) -> [String]? {
        for n in stride(from: 3, through: 1, by: -1) where words.count >= n * 2 {
            for i in 0...(words.count - n * 2) where Array(words[i..<i + n]) == Array(words[i + n..<i + n * 2]) {
                return Array(words[i..<i + n])
            }
        }
        return nil
    }

    static func longestCommonSubsequence(_ x: [String], _ y: [String]) -> Int {
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var prev = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            var cur = [Int](repeating: 0, count: y.count + 1)
            for j in 1...y.count {
                cur[j] = x[i - 1] == y[j - 1] ? prev[j - 1] + 1 : max(prev[j], cur[j - 1])
            }
            prev = cur
        }
        return prev[y.count]
    }

    /// Palavras em minúsculas, sem pontuação nem marcadores de lista.
    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }

    // MARK: Provedores

    /// Quanto tempo o Ollama mantém o modelo na memória (o padrão dele é 5 min).
    /// -1 = o Ollama não descarrega o modelo enquanto o Oruri estiver aberto (ao fechar o app, ele é liberado).
    /// Antes, com 30 min, o primeiro ditado depois de um tempo parado esperava ~20 s o modelo carregar.
    static let ollamaKeepAlive = -1

    /// Carrega o modelo do Ollama sem gerar nada, para o próximo ditado não esperar o carregamento.
    static func warmUpOllama(endpoint: String, model: String) {
        guard let url = URL(string: endpoint)?.appendingPathComponent("api/generate") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": ollamaKeepAlive])
        URLSession.shared.dataTask(with: request).resume()
    }

    /// Libera a memória do Ollama ao fechar o Oruri (espera no máximo 1 s).
    static func unloadOllama(endpoint: String, model: String) {
        guard let url = URL(string: endpoint)?.appendingPathComponent("api/generate") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 1
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": 0])
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 1)
    }

    /// Modelos de texto da Groq, do preferido para o último. A Groq aposenta modelos sem aviso
    /// (o llama-3.3-70b-versatile passou a dar 404 em nov 2026), então o Oruri pergunta quais existem.
    static let groqModelPreference = ["llama-3.3-70b-versatile", "openai/gpt-oss-120b", "moonshotai/kimi-k2-instruct",
                                      "qwen/qwen3-32b", "meta-llama/llama-4-maverick-17b-128e-instruct", "openai/gpt-oss-20b",
                                      "llama-3.1-8b-instant"]
    private static var groqModel: String?

    /// O primeiro da lista de preferência que a Groq oferece; senão, qualquer modelo de texto (não Whisper, não guarda).
    static func pickGroqModel(from available: [String]) -> String? {
        if let preferred = groqModelPreference.first(where: available.contains) { return preferred }
        return available.sorted().first { id in
            let lower = id.lowercased()
            return !["whisper", "guard", "tts", "playai", "distil", "compound"].contains(where: lower.contains)
        }
    }

    private static func groqModelID(key: String) async throws -> String {
        if let groqModel { return groqModel }
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let ids = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]] ?? [])
            .compactMap { $0["id"] as? String }
        guard let model = pickGroqModel(from: ids) else { throw CleanupError.bad(T("Groq cleanup failed")) }
        log.notice("groq cleanup model: \(model, privacy: .public)")
        groqModel = model
        return model
    }

    /// Limpeza pela Groq, com a mesma chave da transcrição.
    private static func groq(_ text: String, system: String) async throws -> String {
        guard let key = Keychain.get(TranscriptionProvider.groq.keychainAccount), !key.isEmpty else {
            throw CleanupError.bad(T("Add your Groq API key in Settings › Models to clean up with Groq."))
        }
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": try await groqModelID(key: key),
            "temperature": 0,
            "messages": [["role": "system", "content": system], ["role": "user", "content": text]],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? T("Groq cleanup failed")
            log.error("groq cleanup error: \(message, privacy: .public)")
            groqModel = nil // na próxima vez pergunta de novo quais modelos existem
            throw CleanupError.bad(message)
        }
        let message = ((json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])
        return message?["content"] as? String ?? ""
    }

    private static func ollama(_ text: String, system: String, endpoint: String, model: String) async throws -> String {
        guard let url = URL(string: endpoint)?.appendingPathComponent("api/chat") else { throw CleanupError.unreachable(endpoint) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": false,
            "keep_alive": ollamaKeepAlive,
            "messages": [["role": "system", "content": system], ["role": "user", "content": text]],
        ])
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let error = json?["error"] as? String { throw CleanupError.bad(error) }
            return (json?["message"] as? [String: Any])?["content"] as? String ?? ""
        } catch let error as CleanupError {
            throw error
        } catch {
            throw CleanupError.unreachable(endpoint)
        }
    }

    /// Usado pelo botão "Test connection" de Settings.
    static func testOllama(endpoint: String, model: String) async -> Result<String, Error> {
        do {
            let out = try await ollama("hello world", system: "Repeat the user text exactly.", endpoint: endpoint, model: model)
            return .success(T(out.isEmpty ? "Connected" : "Connected — model ready"))
        } catch {
            return .failure(error)
        }
    }
}
