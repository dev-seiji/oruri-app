import Testing
@testable import Oruri

/// Aviso do Ollama desligado.
@Suite struct OllamaStatusTests {
    @Test func warnsOnlyWhenCleanupUsesOllama() {
        Localizer.shared.language = .en
        #expect(OllamaService.warning(cleanupOn: true, status: .stopped) == "Ollama is off: AI cleanup is paused")
        #expect(OllamaService.warning(cleanupOn: true, status: .notInstalled) != nil)
        #expect(OllamaService.warning(cleanupOn: true, status: .running) == nil)
        #expect(OllamaService.warning(cleanupOn: true, status: .unknown) == nil)
        #expect(OllamaService.warning(cleanupOn: false, status: .stopped) == nil)
    }

    @Test func nothingListeningMeansNotRunning() async {
        // Porta sem nada escutando: precisa voltar "desligado" rápido, sem travar.
        #expect(await OllamaService.isRunning(endpoint: "http://127.0.0.1:1") == false)
    }
}
