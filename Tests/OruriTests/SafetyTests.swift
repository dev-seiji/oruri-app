import Foundation
import AVFoundation
import Testing
@testable import Oruri

/// Travas contra texto inventado: limpeza por IA, invenções do Whisper e silêncio.
@Suite struct SafetyTests {
    @Test func aiCannotAddWords() {
        #expect(!LLMCleanup.isSafe(original: "eu gosto de café", cleaned: "eu gosto do youtube e de café", allowEdits: false))
        #expect(LLMCleanup.isSafe(original: "eu gosto de café", cleaned: "Eu gosto de café.", allowEdits: false))
    }

    @Test func aiCannotDropTooMuch() {
        #expect(!LLMCleanup.isSafe(original: "uma frase bem longa com muitas palavras aqui", cleaned: "frase", allowEdits: false))
    }

    typealias Seg = Hallucination.Segment

    /// Valores reais medidos na Groq em 23 out 2026 (ruído gerado e fala gerada pela voz Luciana).
    @Test func whisperHallucinationsOnNoiseAreDropped() {
        #expect(Hallucination.isLikely(" E aí", segments: [Seg(noSpeech: 0.000, confidence: -0.977)]))  // zumbido 120 Hz
        #expect(Hallucination.isLikely(" E aí", segments: [Seg(noSpeech: 0.167, confidence: -0.718)]))  // chiado 2 s
        #expect(Hallucination.isLikely(" E aí", segments: [Seg(noSpeech: 0.252, confidence: -1.013)]))  // cliques de teclado
        #expect(Hallucination.isLikely(" E aí", segments: [Seg(noSpeech: 0.644, confidence: -1.138)]))  // respiração
        #expect(Hallucination.isLikely("Eaí.", segments: [Seg(noSpeech: 0.3, confidence: -0.8)]))
        #expect(Hallucination.isLikely("Obrigado.", segments: [Seg(noSpeech: 0.5, confidence: -0.8)]))
        #expect(Hallucination.isLikely("qualquer coisa", segments: [Seg(noSpeech: 0.9, confidence: -0.9)]))
        #expect(Hallucination.isLikely("   ", segments: []))
    }

    @Test func realSpeechIsKept() {
        #expect(!Hallucination.isLikely(" E aí, tudo bem?", segments: [Seg(noSpeech: 0.061, confidence: -0.197)]))
        #expect(!Hallucination.isLikely(" Manda o relatório para o Paulo amanhã de manhã.", segments: [Seg(noSpeech: 0.003, confidence: -0.039)]))
        #expect(!Hallucination.isLikely("E aí", segments: [Seg(noSpeech: 0.088, confidence: -0.407)]))  // "E aí" falado sozinho
        #expect(!Hallucination.isLikely("Obrigado.", segments: [Seg(noSpeech: 0.040, confidence: -0.314)]))  // "Obrigado" falado
        #expect(!Hallucination.isLikely("E aí", segments: []))
    }

    // MARK: Silêncio, com áudios gerados na hora

    func wav(seconds: Double, amplitude: Double, noise: Bool) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("qa-\(UUID().uuidString).wav")
        let format = AudioRecorder.targetFormat
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        if frames > 0 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            for i in 0..<Int(frames) {
                let v = noise ? Double.random(in: -1...1) * amplitude * 1.7 : sin(Double(i) * 0.12) * amplitude * 1.41
                buffer.int16ChannelData![0][i] = Int16(max(-32767, min(32767, v * 32767)))
            }
            try file.write(from: buffer)
        }
        return url
    }

    @Test func silenceAndBackgroundNoiseAreSilent() throws {
        #expect(SilenceDetector.isSilent(try wav(seconds: 1, amplitude: 0, noise: false)))
        #expect(SilenceDetector.isSilent(try wav(seconds: 0.4, amplitude: 0.016, noise: true)))
    }

    @Test func speechIsNotSilent() throws {
        #expect(!SilenceDetector.isSilent(try wav(seconds: 2, amplitude: 0.08, noise: false)))
    }

    @Test func emptyFileCountsAsSilent() throws {
        #expect(SilenceDetector.isSilent(try wav(seconds: 0, amplitude: 0, noise: false)))
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("qa-broken.wav")
        try Data([0, 1, 2, 3]).write(to: broken)
        #expect(SilenceDetector.isSilent(broken))
    }
}
