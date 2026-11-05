import AppKit
import Foundation

/// Situação do Ollama, conferida de tempos em tempos enquanto a limpeza usa ele.
enum OllamaStatus: Equatable {
    case unknown, running, stopped, notInstalled
}

/// Confere se o Ollama está rodando e liga ele sem precisar do Terminal.
enum OllamaService {
    static let appURL = URL(fileURLWithPath: "/Applications/Ollama.app")
    static let binaries = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
    static let brews = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    static let downloadURL = URL(string: "https://ollama.com/download")!

    static var binary: String? { binaries.first(where: FileManager.default.isExecutableFile) }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: appURL.path) || binary != nil }

    /// Pergunta ao Ollama a lista de modelos (responde em milissegundos quando está ligado).
    static func isRunning(endpoint: String) async -> Bool {
        guard let url = URL(string: endpoint)?.appendingPathComponent("api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    static func check(endpoint: String) async -> OllamaStatus {
        if await isRunning(endpoint: endpoint) { return .running }
        return isInstalled ? .stopped : .notInstalled
    }

    /// Liga o Ollama: pelo app oficial, se estiver instalado; senão pelo Homebrew (que também liga com o Mac);
    /// senão roda `ollama serve` em segundo plano. Devolve false se não houver Ollama instalado.
    @discardableResult
    static func start() -> Bool {
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return true
        }
        guard let binary else { return false }
        if let brew = brews.first(where: FileManager.default.isExecutableFile), binary.hasPrefix((brew as NSString).deletingLastPathComponent) {
            run(brew, ["services", "start", "ollama"])
        } else {
            run(binary, ["serve"])
        }
        return true
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Aviso da Home: só quando a limpeza por IA está ligada e o Ollama não está respondendo.
    static func warning(cleanupOn: Bool, status: OllamaStatus) -> String? {
        guard cleanupOn else { return nil }
        switch status {
        case .stopped: return T("Ollama is off: AI cleanup is paused")
        case .notInstalled: return T("Ollama isn't installed: AI cleanup is paused")
        case .running, .unknown: return nil
        }
    }
}
