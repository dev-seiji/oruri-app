import Foundation
import Speech
import AVFoundation

/// Motores de transcrição disponíveis.
enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case apple = "Apple"
    case groq = "Groq"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: T("On-device")
        case .groq: "Groq"
        }
    }

    var subtitle: String {
        switch self {
        case .apple: T("Apple Speech · private, no key")
        case .groq: T("Cloud · very fast Whisper")
        }
    }

    var isCloud: Bool { self != .apple }

    var models: [(id: String, detail: String)] {
        switch self {
        case .apple: [("On-device", "Runs on this Mac. Uses the language picked in Output.")]
        case .groq: [("whisper-large-v3-turbo", "Fastest, multilingual"),
                     ("whisper-large-v3", "Most accurate Whisper, multilingual")]
        }
    }

    var defaultModel: String { models[0].id }

    /// Conta do Keychain onde fica a chave de API.
    var keychainAccount: String { "api-key.\(rawValue.lowercased())" }

    var keyURL: URL? {
        switch self {
        case .apple: nil
        case .groq: URL(string: "https://console.groq.com/keys")
        }
    }

    fileprivate var endpoint: URL? {
        switch self {
        case .apple: nil
        case .groq: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")
        }
    }
}

enum TranscriptionError: LocalizedError {
    case missingAPIKey(TranscriptionProvider)
    case speechNotAuthorized
    case recognizerUnavailable(String)
    case server(Int, String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p): T("Add your %@ API key in Settings › Models.", p.rawValue)
        case .speechNotAuthorized: T("Speech recognition permission was denied. Allow it in System Settings › Privacy & Security.")
        case .recognizerUnavailable(let lang): T("On-device recognition isn't available for %@.", lang)
        case .server(let code, let message): T("Transcription service error %ld: %@", code, message)
        case .emptyResult: T("No speech detected")
        }
    }
}

/// Idiomas oferecidos em Output › Transcription language.
enum Language {
    static let all: [(name: String, code: String?, locale: String)] = [
        ("Auto-detect", nil, Locale.current.identifier),
        ("Portuguese", "pt", "pt-BR"),
        ("English", "en", "en-US"),
        ("Spanish", "es", "es-ES"),
        ("French", "fr", "fr-FR"),
        ("German", "de", "de-DE"),
        ("Italian", "it", "it-IT"),
        ("Japanese", "ja", "ja-JP"),
    ]
    static var names: [String] { all.map(\.name) }
    static func code(for name: String) -> String? { all.first { $0.name == name }?.code }
    static func locale(for name: String) -> Locale { Locale(identifier: all.first { $0.name == name }?.locale ?? "en-US") }
}

struct TranscriptionRequest {
    var audioURL: URL
    var provider: TranscriptionProvider
    var model: String
    var languageName: String
    /// Termos do dicionário, usados como dica de vocabulário.
    var vocabulary: [String]
}

enum Transcriber {
    /// Avisado a cada áudio aceito pela Groq: duração, modelo e pedidos restantes/limite do dia.
    @MainActor static var onGroqUsage: ((Double, String, Int?, Int?) -> Void)?

    static func transcribe(_ request: TranscriptionRequest) async throws -> String {
        let text: String
        switch request.provider {
        case .apple: text = try await appleSpeech(request)
        case .groq: text = try await cloud(request)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.emptyResult }
        return trimmed
    }

    // MARK: Apple Speech (no Mac)

    static func requestSpeechAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    private static func appleSpeech(_ request: TranscriptionRequest) async throws -> String {
        let locale = Language.locale(for: request.languageName)
        if #available(macOS 26.0, *) {
            return try await speechAnalyzer(url: request.audioURL, locale: locale)
        }
        return try await legacySpeech(request, locale: locale)
    }

    /// macOS 26+: SpeechAnalyzer + SpeechTranscriber, 100% no Mac e bom com áudios longos.
    /// Nos testes pontuou melhor que o DictationTranscriber e mantém "um/uh" para o pipeline remover.
    /// O modelo do idioma é baixado pelo sistema na primeira vez.
    @available(macOS 26.0, *)
    private static func speechAnalyzer(url: URL, locale: Locale) async throws -> String {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.recognizerUnavailable(locale.identifier)
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collect = Task { () -> String in
            var text = ""
            for try await result in transcriber.results { text += String(result.text.characters) }
            return text
        }
        let file = try AVAudioFile(forReading: url)
        if let end = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collect.value
    }

    /// macOS 14–15: SFSpeechRecognizer (pode encerrar cedo em áudios com pausas).
    private static func legacySpeech(_ request: TranscriptionRequest, locale: Locale) async throws -> String {
        guard await requestSpeechAuthorization() else { throw TranscriptionError.speechNotAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable(locale.identifier)
        }
        let speech = SFSpeechURLRecognitionRequest(url: request.audioURL)
        speech.shouldReportPartialResults = false
        speech.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { speech.requiresOnDeviceRecognition = true }
        speech.contextualStrings = Array(request.vocabulary.prefix(100))

        speech.taskHint = .dictation
        return try await withCheckedThrowingContinuation { cont in
            let collector = SpeechCollector(continuation: cont)
            collector.task = recognizer.recognitionTask(with: speech, delegate: collector)
        }
    }

    // MARK: Nuvem (Groq)

    private static func cloud(_ request: TranscriptionRequest) async throws -> String {
        let provider = request.provider
        guard let key = Keychain.get(provider.keychainAccount), !key.isEmpty else {
            throw TranscriptionError.missingAPIKey(provider)
        }
        guard let endpoint = provider.endpoint else { return "" }

        var form = MultipartForm()
        form.add("model", request.model)
        // A Groq devolve, por trecho, a chance de não haver fala (no_speech_prob); usamos para descartar invenções.
        form.add("response_format", "verbose_json")
        if let code = Language.code(for: request.languageName) { form.add("language", code) }
        if !request.vocabulary.isEmpty {
            // O "prompt" ajuda o modelo a grafar nomes e jargões do dicionário.
            form.add("prompt", request.vocabulary.prefix(60).joined(separator: ", "))
        }
        let upload = try compressedIfLarge(request.audioURL)
        defer { if upload != request.audioURL { try? FileManager.default.removeItem(at: upload) } }
        let audio = try Data(contentsOf: upload)
        form.addFile("file", filename: upload.lastPathComponent,
                     mimeType: mimeType(for: upload), data: audio)

        var http = URLRequest(url: endpoint)
        http.httpMethod = "POST"
        http.timeoutInterval = 120
        http.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        http.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        http.httpBody = form.finalize()

        let (data, response) = try await URLSession.shared.data(for: http)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? String(data: data, encoding: .utf8) ?? ""
            throw TranscriptionError.server(status, message)
        }
        if provider == .groq {
            let headers = response as? HTTPURLResponse
            let remaining = headers?.value(forHTTPHeaderField: "x-ratelimit-remaining-requests").flatMap { Int($0) }
            let limit = headers?.value(forHTTPHeaderField: "x-ratelimit-limit-requests").flatMap { Int($0) }
            let seconds = audioSeconds(request.audioURL)
            let model = request.model
            await MainActor.run { onGroqUsage?(seconds, model, remaining, limit) }
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = json?["text"] as? String ?? ""
        let segments = (json?["segments"] as? [[String: Any]] ?? []).map {
            Hallucination.Segment(noSpeech: ($0["no_speech_prob"] as? NSNumber)?.doubleValue ?? 0,
                                  confidence: ($0["avg_logprob"] as? NSNumber)?.doubleValue ?? 0)
        }
        return Hallucination.isLikely(text, segments: segments) ? "" : text
    }

    /// A Groq recusa arquivos acima de 25 MB (WAV ≈ 12 min). Acima disso, manda em AAC mono de 32 kbps (≈ 100 min em 24 MB).
    // shortcut: acima de ~100 min ainda passa do limite; dividir em partes quando alguém precisar.
    static func compressedIfLarge(_ url: URL, limit: Int = 24_000_000) throws -> URL {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > limit else { return url }
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        do {
            let output = try AVAudioFile(forWriting: dest, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 32_000,
            ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else { return url }
            while input.framePosition < input.length {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
            }
        } // o arquivo AAC é fechado aqui, antes de ser lido para o envio
        return dest
    }

    private static func audioSeconds(_ url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": "audio/wav"
        case "m4a": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "mp4": "video/mp4"
        case "ogg": "audio/ogg"
        case "flac": "audio/flac"
        case "webm": "audio/webm"
        default: "application/octet-stream"
        }
    }

    // MARK: Arquivos arrastados

    /// Converte qualquer áudio/vídeo (MP4, MOV, M4A, MP3…) para WAV 16 kHz mono, pronto para transcrever.
    static func prepareAudio(from source: URL) async throws -> (url: URL, duration: TimeInterval) {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "Oruri", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file has no audio track."])
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        reader.startReading()

        let dest = Store.recordingsDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: dest, settings: AudioRecorder.targetFormat.settings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        var totalFrames = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
            totalFrames += Int(frames)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: AudioRecorder.targetFormat, frameCapacity: frames) else { continue }
            buffer.frameLength = frames
            let length = CMBlockBufferGetDataLength(block)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                       destination: buffer.int16ChannelData![0])
            try file.write(from: buffer)
        }
        if reader.status == .failed { throw reader.error ?? NSError(domain: "Oruri", code: 2) }
        // A duração vem do áudio que de fato saiu, não do cabeçalho do arquivo (que pode mentir: NaN ou gigante).
        return (dest, Double(totalFrames) / 16_000)
    }
}

/// Junta os trechos finais que o reconhecedor entrega (um por pausa) e termina quando o arquivo acaba.
private final class SpeechCollector: NSObject, SFSpeechRecognitionTaskDelegate {
    private var continuation: CheckedContinuation<String, Error>?
    private var segments: [String] = []
    var task: SFSpeechRecognitionTask?

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
        super.init()
        // O delegate é referência fraca no SFSpeechRecognitionTask; mantém-se vivo até terminar.
        SpeechCollector.alive.insert(self)
    }

    private static var alive = Set<SpeechCollector>()

    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { segments.append(text) }
    }

    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        defer { continuation = nil; SpeechCollector.alive.remove(self) }
        let text = segments.joined(separator: " ")
        if !text.isEmpty {
            continuation?.resume(returning: text)
        } else if let error = task.error as NSError?, error.code != 1110 { // 1110 = no speech
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(throwing: TranscriptionError.emptyResult)
        }
    }
}

/// Detecta áudio sem fala: nenhum trecho de 0,25 s passa de um nível mínimo de energia.
/// O Whisper "ouve" frases prontas no silêncio ou no ruído ("E aí", "Obrigado.", "Legendas pela comunidade Amara.org"…).
/// Medido em 23 out 2026 com a Groq (whisper-large-v3): chiado, cliques de teclado, zumbido e respiração viraram todos
/// "E aí". A chance de "não haver fala" (no_speech_prob) não separa (o zumbido veio com 0,000), mas a confiança média
/// do texto (avg_logprob) separa bem: ruído ficou entre −0,72 e −1,15; fala de verdade entre −0,04 e −0,41.
enum Hallucination {
    struct Segment {
        var noSpeech: Double
        /// avg_logprob do Whisper: perto de 0 é confiante; bem negativo é chute.
        var confidence: Double
    }

    static let phrases: Set<String> = [
        "eai", "obrigado", "obrigada", "tchau", "valeu", "legendaspelacomunidadeamara.org",
        "thankyou", "thanksforwatching", "you", "bye", "gracias", "ご視聴ありがとうございました",
    ]

    /// Minúsculas, sem acento, sem pontuação nas pontas e sem espaços ("Eaí." e "E aí!" viram "eai").
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: " ", with: "")
    }

    /// `segments`: um por trecho (vazio quando o motor não informa, e aí só texto vazio é descartado).
    static func isLikely(_ text: String, segments: [Segment]) -> Bool {
        let cleaned = normalized(text)
        if cleaned.isEmpty { return true }
        guard !segments.isEmpty else { return false }
        let noSpeech = segments.map(\.noSpeech).reduce(0, +) / Double(segments.count)
        let confidence = segments.map(\.confidence).reduce(0, +) / Double(segments.count)
        // Frase pronta dita sem confiança: é ruído. O corte fica entre o "E aí" falado de verdade (−0,41)
        // e o ruído mais "confiante" medido (−0,72).
        if phrases.contains(cleaned) && confidence < -0.55 { return true }
        // Regra clássica do Whisper: provável silêncio e texto sem confiança.
        if noSpeech > 0.6 && confidence < -0.5 { return true }
        // Texto muito sem confiança, com algum sinal de silêncio.
        return confidence < -1.0 && noSpeech > 0.3
    }
}

enum SilenceDetector {
    /// Silencioso quando nenhum trecho de 0,25 s passa do ruído de fundo. Medido em 17 out 2026: fala chega a
    /// 0,03–0,12; ruído de gravações "vazias" fica em 0,015–0,017. Abaixo de 0,02 é sempre silêncio; entre
    /// 0,02 e 0,03 só conta como fala se o trecho mais alto for bem acima do mais baixo (o ruído de fundo).
    static func isSilent(_ url: URL) -> Bool {
        // Arquivo vazio ou ilegível é tratado como silêncio: mandar isso para a nuvem só gera texto inventado.
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0] else { return true }
        let total = Int(buffer.frameLength)
        let window = max(1, Int(file.processingFormat.sampleRate * 0.25))
        var levels: [Float] = []
        var start = 0
        while start < total {
            let end = min(total, start + window)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            levels.append(sqrt(sum / Float(end - start)))
            start = end
        }
        guard let loudest = levels.max(), let quietest = levels.min() else { return true }
        if loudest < 0.02 { return true }
        if loudest >= 0.03 { return false }
        return loudest < quietest * 1.8
    }
}

/// Corpo multipart/form-data mínimo para upload de arquivos.
private struct MultipartForm {
    private let boundary = "oruri-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func add(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    func finalize() -> Data {
        var data = body
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }
}

