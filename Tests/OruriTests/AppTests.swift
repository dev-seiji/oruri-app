import Foundation
import AppKit
import Testing
import AVFoundation
@testable import Oruri

/// Uso da Groq, formatação e idiomas.
@Suite struct AppTests {
    @Test func groqUsageFractions() {
        var u = GroqUsage()
        u.record(seconds: 7_200, model: "whisper-large-v3-turbo", remaining: nil, limit: nil)
        #expect(abs(u.dayAudioFraction - 0.25) < 0.001)
        #expect(abs(u.hourAudioFraction - 1.0) < 0.001)
        #expect(u.tightest.name == "hour")
        #expect(abs(u.monthCost - 0.08) < 0.001)
    }

    @Test func groqUsesItsOwnRequestCountWhenRecent() {
        var u = GroqUsage()
        u.record(seconds: 5, model: "whisper-large-v3", remaining: 1_990, limit: 2_000)
        #expect(u.dayRequests.used == 10)
        #expect(u.dayRequests.limit == 2_000)
    }

    @Test func durationFormat() {
        Localizer.shared.language = .en
        #expect(UsageFormat.duration(0) == "0 min")
        #expect(UsageFormat.duration(20) == "<1 min")
        #expect(UsageFormat.duration(3_900) == "1 h 05 min")
    }

    @Test func englishIsTheDefaultLanguage() {
        #expect(Settings().interfaceLanguage == "en")
        Localizer.shared.language = .en
        #expect(T("Settings") == "Settings")
        #expect(T("Keep at most %ld recordings", 20) == "Keep at most 20 recordings")
    }

    /// Desde a 0.5.0 o app se chama Oruri: o nome antigo não pode voltar ao código.
    @Test func oldNameIsGone() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Oruri")
        var leftovers: [String] = []
        for file in try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
            for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            where line.lowercased().contains("platy" + "pus") {
                leftovers.append("\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(leftovers.isEmpty, "\(leftovers)")
    }

    /// "Copied · ⌘V" quando não há caixa de escrever em foco: página, lista do Finder ou botão não contam como campo.
    @Test func pasteTargetNeedsATextField() {
        #expect(Delivery.isTextInput(role: "AXTextField", valueSettable: true))
        #expect(Delivery.isTextInput(role: "AXTextArea", valueSettable: false))
        #expect(Delivery.isTextInput(role: "AXComboBox", valueSettable: false))
        #expect(!Delivery.isTextInput(role: "AXWebArea", valueSettable: false))
        #expect(!Delivery.isTextInput(role: "AXWebArea", valueSettable: true))
        #expect(!Delivery.isTextInput(role: "AXOutline", valueSettable: false))
        #expect(!Delivery.isTextInput(role: "AXButton", valueSettable: false))
        #expect(!Delivery.isTextInput(role: "AXToolbar", valueSettable: false)) // fora da caixa do Claude (5 nov)
        #expect(!Delivery.isTextInput(role: nil, valueSettable: false))
        #expect(Delivery.isTextInput(role: "AXGroup", valueSettable: true))
    }

    /// Item 21: com a Groq na limpeza, o Ollama não é carregado nem gera aviso; o padrão continua Ollama.
    @Test func cleanupEngineChoice() {
        var s = Settings()
        #expect(s.cleanupEngine == "Ollama" && !s.usesOllama)
        s.llmCleanup = true
        #expect(s.usesOllama)
        s.cleanupEngine = "Groq"
        #expect(!s.usesOllama)
        #expect(OllamaService.warning(cleanupOn: s.usesOllama, status: .stopped) == nil)
    }

    /// Item 23: áudio grande vira AAC menor antes de ir para a Groq, com a mesma duração.
    @Test func largeAudioIsCompressedForGroq() throws {
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        let format = AudioRecorder.targetFormat
        do {
            let file = try AVAudioFile(forWriting: wav, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate * 30)))
            buffer.frameLength = buffer.frameCapacity
            for i in 0..<Int(buffer.frameLength) { buffer.int16ChannelData?[0][i] = Int16(sin(Double(i) / 8) * 8000) }
            try file.write(from: buffer)
        }
        #expect(try Transcriber.compressedIfLarge(wav) == wav) // pequeno: vai como está
        let m4a = try Transcriber.compressedIfLarge(wav, limit: 1)
        defer { try? FileManager.default.removeItem(at: m4a) }
        #expect(m4a.pathExtension == "m4a")
        let wavSize = try #require(try wav.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let m4aSize = try #require(try m4a.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(m4aSize * 4 < wavSize)
        let out = try AVAudioFile(forReading: m4a)
        #expect(abs(Double(out.length) / out.processingFormat.sampleRate - 30) < 0.2)
    }

    /// A parte aberta não tem chave própria da OpenAI nem do Claude (só nomes de apps onde o texto é colado).
    @Test func noOpenAIOrClaudeKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Oruri")
        var files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        files.append(root.appendingPathComponent("Localization/translations.txt"))
        let allowed = ["com.anthropic.claudefordesktop", "com.openai.chat", "api.groq.com/openai/"]
        var leftovers: [String] = []
        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines) {
                var l = line.lowercased()
                for a in allowed { l = l.replacingOccurrences(of: a, with: "") }
                if l.contains("openai") || l.contains("anthropic") {
                    leftovers.append("\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(leftovers.isEmpty, "\(leftovers)")
    }

    /// Desde a 0.5.1 o comando pós-gravação recebe as variáveis ORURI_*.
    @Test func postHookVariables() {
        let recording = Recording(date: Date(), text: "olá", duration: 2.5)
        let env = SystemIntegration.hookVariables(recording: recording, timestamp: "2026-11-01T10:00:00Z")
        #expect(env["ORURI_TEXT"] == "olá")
        #expect(env["ORURI_TIMESTAMP"] == "2026-11-01T10:00:00Z")
        #expect(env["ORURI_DURATION"] == "2.5")
    }

    @Test func comboShortcutRoundTrip() {
        let combo = ComboShortcut(modifiers: [.control, .shift], keyCode: 2, label: "⌃⇧D")
        #expect(ComboShortcut(encoded: combo.encoded) == combo)
    }
}

/// Saldo de pedidos da Groq (item 12): valores reais de 1 nov 2026, um pedido volta a cada 43,2 s.
@Suite struct GroqAllowanceTests {
    @Test func headerBalanceRefillsOverTime() {
        var u = GroqUsage()
        u.record(seconds: 2, model: "whisper-large-v3-turbo", remaining: 1_997, limit: 2_000)
        let start = u.headersDate!
        #expect(u.requestsUsed(at: start).used == 3)
        #expect(u.requestsUsed(at: start.addingTimeInterval(43.3)).used == 2)
        #expect(u.requestsUsed(at: start.addingTimeInterval(130)).used == 0)
    }

    @Test func manyRequestsThisMonthCanStillLeaveTheBalanceFull() {
        // O caso que confundiu: 34 pedidos no mês, mas a barrinha quase vazia.
        var u = GroqUsage()
        let longAgo = Date.now.addingTimeInterval(-6 * 3_600)
        u.entries = (0..<34).map { GroqUsage.Entry(date: longAgo.addingTimeInterval(Double($0)), seconds: 3, model: "whisper-large-v3") }
        #expect(u.thisMonth.count == 34 || Calendar.current.component(.month, from: longAgo) != Calendar.current.component(.month, from: .now))
        #expect(u.requestsUsed().used == 0)
    }

    @Test func withoutHeadersTheLocalCountRefillsTheSameWay() {
        var u = GroqUsage()
        let now = Date.now
        u.entries = (0..<5).map { GroqUsage.Entry(date: now.addingTimeInterval(Double($0) - 5), seconds: 1, model: "whisper-large-v3-turbo") }
        #expect(u.requestsUsed(at: now).used == 5)
        #expect(u.requestsUsed(at: now.addingTimeInterval(86_400)).used == 0)
    }
}

/// Limpeza do código (item 14): nada que funcionava pode quebrar.
@Suite struct CleanupOfCodeTests {
    @Test func correctionListsStayTogether() {
        #expect(SpokenEdits.strongCues.allSatisfy(LLMCleanup.correctionCues.contains))
        #expect(LLMCleanup.weakCorrectionCues == SpokenEdits.weakCues)
    }

    @Test func oldSavedSettingsStillLoad() throws {
        // Configuração salva por versões antigas, ainda com campos que saíram do app.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as! [String: Any]
        json["liveTranscription"] = true
        json["indicatorPosition"] = "Bottom"
        json["appLanguage"] = "System"
        json["hideMenuBarIcon"] = false
        json["debugMode"] = false
        json["engine"] = "Groq"
        let settings = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(settings.engine == "Groq")
    }
}
