import Foundation
import Testing
@testable import Oruri

/// Teste ao vivo com o Ollama (não roda no QA normal): manda frases reais com as mesmas instruções do app
/// e mostra o que a IA devolveu e se a trava aceitou. Rodar com:
///   ORURI_LIVE_OLLAMA=1 swift test --filter LiveOllamaTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ORURI_LIVE_OLLAMA"] == "1"))
struct LiveOllamaTests {
    static let phrases = [
        "manda o relatório para o Paulo amanhã de manhã, e avisa a equipe que a reunião mudou para quinta-feira às 3 da tarde",
        "cara, você viu o que aconteceu ontem no jogo",
        "eu não vou conseguir ir na reunião hoje porque tô com febre",
        "a versão 0.2.1 já está no ar e corrige o bug do áudio",
        "manda pro Pedro, errei, pro Paulo",
        "a reunião é na quinta, quer dizer, na sexta às 10:30",
        "oi Ana, tudo bem? queria saber se você consegue me mandar a planilha até sexta, abraço",
        "precisamos comprar pão, café, leite e manteiga",
        "o cliente pediu um desconto de 15% no contrato de 12 meses",
        "lembra de ligar pro dentista e remarcar a consulta",
        "eu acho que o problema é no servidor e não no aplicativo",
        "o que quer dizer isso?",
    ]

    func ask(_ text: String) async throws -> String {
        var request = URLRequest(url: URL(string: "http://localhost:11434/api/chat")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "llama3.2", "stream": false,
            "messages": [["role": "system", "content": LLMCleanup.systemPrompt(language: "Portuguese", smartFormatting: true, spokenEdits: true)],
                         ["role": "user", "content": LLMCleanup.userMessage(text)]],
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return LLMCleanup.unwrap((json?["message"] as? [String: Any])?["content"] as? String ?? "")
    }

    @Test func realPhrases() async throws {
        var report = ""
        for phrase in Self.phrases {
            for run in 1...3 {
                let out = try await ask(phrase)
                let ok = LLMCleanup.isSafe(original: phrase, cleaned: out, allowEdits: true)
                report += "\(ok ? "ACEITO " : "BARRADO") [\(run)] \(phrase)\n        → \(out.replacingOccurrences(of: "\n", with: " ⏎ "))\n"
            }
        }
        let path = ProcessInfo.processInfo.environment["ORURI_LIVE_REPORT"] ?? "/tmp/oruri-live-ollama.txt"
        try report.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// Liga o Ollama pelo mesmo código do botão "Start Ollama" e espera ele responder. Rodar com:
///   ORURI_LIVE_OLLAMA_START=1 swift test --filter LiveOllamaStartTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ORURI_LIVE_OLLAMA_START"] == "1"))
struct LiveOllamaStartTests {
    @Test func startButtonBringsOllamaBack() async throws {
        #expect(OllamaService.start())
        var running = false
        for _ in 0..<20 where !running {
            try await Task.sleep(for: .seconds(1))
            running = await OllamaService.isRunning(endpoint: "http://localhost:11434")
        }
        #expect(running)
    }
}
