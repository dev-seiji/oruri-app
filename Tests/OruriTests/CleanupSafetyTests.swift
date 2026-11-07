import Testing
@testable import Oruri

/// Trava da limpeza por IA: ela pode arrumar o texto, mas não mudar o que foi dito.
/// Os casos "não pode" vieram de erros reais do llama3.2 nos testes de 23 out 2026.
@Suite struct CleanupSafetyTests {
    func safe(_ original: String, _ cleaned: String, edits: Bool = false) -> Bool {
        LLMCleanup.isSafe(original: original, cleaned: cleaned, allowEdits: edits)
    }

    // MARK: Pode

    @Test func punctuationAndCapitalsAreFine() {
        #expect(safe("manda o relatório para o paulo amanhã de manhã", "Manda o relatório para o Paulo amanhã de manhã."))
    }

    @Test func spellingFixesAreFine() {
        #expect(safe("manda o relatorio amanha", "Manda o relatório amanhã."))
    }

    @Test func listFormattingIsFine() {
        #expect(safe("comprar pão, café e leite", "- Comprar pão\n- café\n- leite"))
    }

    @Test func spokenCorrectionsAreFine() {
        #expect(safe("manda pro Pedro, errei, pro Paulo", "Manda pro Paulo.", edits: true))
        #expect(safe("a reunião é às 3, não, às 4", "A reunião é às 4.", edits: true))
    }

    // MARK: Não pode

    @Test func droppedWordsAreBlocked() {
        // Visto ao vivo em 1 nov 2026: "amanhã de manhã" virou só "amanhã".
        #expect(!safe("Manda o relatório para o Paulo amanhã de manhã.", "Manda o relatório para o Paulo amanhã.", edits: true))
    }

    @Test func answeringInsteadOfCleaningIsBlocked() {
        // Visto ao vivo: o llama3.2 respondeu a frase em vez de arrumar.
        #expect(!safe("cara, você viu o que aconteceu ontem no jogo", "Sim, eu vi, vocês perderam para o São Paulo, certo?", edits: true))
        #expect(!safe("o que quer dizer isso?", "Eu queria dizer que estou com fome, mas falei errado, quero dizer que estou com sede.", edits: true))
    }

    @Test func inventedCorrectionIsBlocked() {
        #expect(!safe("o cliente pediu um desconto de 15% no contrato de 12 meses",
                      "o cliente pediu um desconto de 15% no contrato de 12 meses, mas falei errado, o desconto é de 20%, certo.", edits: true))
    }

    @Test func correctionMustDropTheWrongPart() {
        // Visto ao vivo: a IA tirou só o "errei" e deixou os dois nomes.
        #expect(!safe("manda pro Pedro, errei, pro Paulo", "Manda pro Pedro, pro Paulo.", edits: true))
        // Visto ao vivo: ficou com a versão errada.
        #expect(!safe("manda pro Pedro, errei, pro Paulo", "Manda pro Pedro.", edits: true))
        #expect(!safe("a reunião é na quinta, quer dizer, na sexta às 10:30", "A reunião é na quinta às 10:30.", edits: true))
        #expect(safe("a reunião é na quinta, quer dizer, na sexta às 10:30", "A reunião é na sexta às 10:30.", edits: true))
    }

    @Test func invertedRepetitionIsBlocked() {
        #expect(!safe("Manda o relatório para o Paulo amanhã de manhã.", "Manda o relatório para o Paulo de manhã de manhã."))
    }

    @Test func rewordingIsBlocked() {
        #expect(!safe("Avisa a equipe que a reunião mudou para quinta-feira às 3 da tarde.",
                      "Avisa a equipe que a reunião será na quinta-feira às 3 da tarde."))
    }

    @Test func numbersCannotChange() {
        #expect(!safe("A reunião é às 3 da tarde.", "A reunião é às 4 da tarde."))
        #expect(!safe("Custa 25 reais.", "Custa reais."))
        #expect(!safe("A versão 0.2.1 saiu.", "A versão 0.2 saiu."))
    }

    @Test func namesCannotDisappear() {
        #expect(!safe("Fala com o Paulo amanhã.", "Fala com ele amanhã."))
    }

    @Test func negationCannotBeAddedOrDropped() {
        #expect(!safe("Eu vou na reunião.", "Eu não vou na reunião."))
        #expect(!safe("Eu não vou na reunião.", "Eu vou na reunião."))
    }

    @Test func wordOrderCannotChange() {
        #expect(!safe("o Pedro ligou para o Paulo ontem à noite", "O Paulo ligou para o Pedro ontem à noite."))
    }

    @Test func inventedWordsAreBlocked() {
        #expect(!safe("eu gosto de café", "eu gosto do youtube e de café"))
    }

    /// Item 24: no modo que melhora as frases, a ordem e as palavras podem mudar, os fatos não.
    @Test func improveKeepsFacts() {
        let original = "então eu acho que a reunião com o Pedro mudou para quinta às 10:30 da manhã"
        #expect(LLMCleanup.keepsFacts(original: original, improved: "A reunião com o Pedro mudou para quinta, às 10:30.", allowEdits: false))
        #expect(!LLMCleanup.keepsFacts(original: original, improved: "A reunião com o Pedro mudou para quinta, às 11:30.", allowEdits: false))
        #expect(!LLMCleanup.keepsFacts(original: original, improved: "A reunião mudou para quinta, às 10:30.", allowEdits: false))
        #expect(!LLMCleanup.keepsFacts(original: original, improved: "A reunião com o Pedro não mudou para quinta, às 10:30.", allowEdits: false))
        #expect(!LLMCleanup.keepsFacts(original: "vamos amanhã de manhã", improved: "Vamos amanhã de manhã de manhã.", allowEdits: false))
        #expect(LLMCleanup.systemPrompt(language: "Portuguese", smartFormatting: false, spokenEdits: false, improve: true).contains("rewrite confusing sentences"))
        #expect(!LLMCleanup.systemPrompt(language: "Portuguese", smartFormatting: false, spokenEdits: false).contains("rewrite confusing sentences"))
    }

    /// A Groq aposenta modelos: o Oruri escolhe um que exista, seguindo a preferência, e nunca o Whisper.
    @Test func picksAnAvailableGroqModel() {
        #expect(LLMCleanup.pickGroqModel(from: ["whisper-large-v3", "openai/gpt-oss-20b", "openai/gpt-oss-120b"]) == "openai/gpt-oss-120b")
        #expect(LLMCleanup.pickGroqModel(from: ["whisper-large-v3", "llama-guard-4-12b", "some-new-model"]) == "some-new-model")
        #expect(LLMCleanup.pickGroqModel(from: ["whisper-large-v3-turbo"]) == nil)
    }
}
