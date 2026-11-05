import Testing
@testable import Oruri

/// Tratamento do texto: pontuação falada, números, correções faladas e preenchimento.
/// Cada caso aqui já foi um bug corrigido; o teste impede que ele volte.
@Suite struct TextPipelineTests {
    func run(_ raw: String, _ change: (inout Settings) -> Void = { _ in }) -> String {
        var s = Settings()
        s.transcriptionLanguage = "Portuguese"
        change(&s)
        return TextPipeline.process(raw, settings: s, dictionary: [])
    }

    @Test func spokenVersionStaysTogether() {
        #expect(run("a versão zero ponto dois ponto um").contains("0.2.1"))
    }

    @Test func digitsWithDotsAreNotSplit() {
        #expect(run("a versão 0.2.1 saiu").contains("0.2.1"))
        #expect(!run("a versão 0.2.1 saiu").contains("0. 2"))
    }

    @Test func percentages() {
        #expect(run("cem por cento").contains("100%"))
        #expect(run("100 por cento").contains("100%"))
    }

    @Test func centoOnlyCountsInsideCentoE() {
        #expect(!run("cem por cem").contains("100 por 100%"))
    }

    @Test func compoundNumbers() {
        #expect(run("vinte e cinco reais").contains("25"))
    }

    @Test func spokenCorrectionKeepsOnlyTheRightVersion() {
        let out = run("manda pro Pedro, errei, pro Paulo") { $0.spokenEdits = true }
        #expect(out.contains("Paulo"))
        #expect(!out.contains("Pedro"))
        #expect(!out.lowercased().contains("errei"))
    }

    @Test func questionWithQuerDizerIsNotACorrection() {
        let out = run("o que quer dizer isso?") { $0.spokenEdits = true }
        #expect(out.lowercased().contains("quer dizer"))
    }

    @Test func portugueseUmIsNotAFiller() {
        let out = run("comprei um carro") { $0.removeFillers = true }
        #expect(out.contains("um carro"))
    }

    @Test func englishFillersAreRemoved() {
        let out = run("so um I think uh this works") {
            $0.removeFillers = true
            $0.transcriptionLanguage = "English"
        }
        #expect(!out.contains(" uh "))
    }

    @Test func dictionaryFixesSpelling() {
        var s = Settings()
        s.transcriptionLanguage = "Portuguese"
        let out = TextPipeline.process("eu uso o cubernetes", settings: s,
                                       dictionary: [DictionaryEntry(spelling: "Kubernetes", heardAs: "cubernetes")])
        #expect(out.contains("Kubernetes"))
    }
}

/// Achado F1 do Claude Security (4 nov 2026): "hundred" repetido estourava o Int e o app fechava.
@Suite struct NumberOverflowTests {
    @Test func repeatedHundredDoesNotCrash() {
        let text = Array(repeating: "hundred", count: 12).joined(separator: " ")
        // Antes, isto derrubava o app; agora as palavras ficam como estão.
        #expect(!NumberWords.convert(text, preferDigits: false).isEmpty)
    }

    @Test func hugeScalesDoNotCrash() {
        let text = "nine hundred billion billion billion billion"
        #expect(!NumberWords.convert(text, preferDigits: false).isEmpty)
    }

    @Test func normalNumbersStillConvert() {
        #expect(NumberWords.convert("three hundred", preferDigits: false).contains("300"))
        #expect(NumberWords.convert("two thousand five hundred", preferDigits: false).contains("2500"))
    }
}
