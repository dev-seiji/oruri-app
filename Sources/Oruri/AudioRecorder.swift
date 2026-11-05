import AVFoundation
import CoreAudio

/// Grava o microfone em WAV mono 16 kHz (formato aceito por todos os motores de transcrição).
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case noInputDevice, cannotCreateFile(Error)
        var errorDescription: String? {
            switch self {
            case .noInputDevice: T("No audio input device")
            case .cannotCreateFile(let e): T("Couldn't create the recording file: %@", e.localizedDescription)
            }
        }
    }

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private(set) var url: URL?
    private var startedAt: Date?
    /// Protege `file`/`converter`, usados pela thread de áudio: ao parar, o arquivo só fecha depois da última escrita,
    /// e o cabeçalho WAV fica completo antes de alguém ler (antes, às vezes ficava dizendo "0 s de áudio").
    private let lock = NSLock()

    /// Chamado (fora da main thread) com o nível RMS normalizado 0…1.
    var onLevel: ((Float) -> Void)?

    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                            channels: 1, interleaved: true)!

    var isRecording: Bool { engine.isRunning }

    func start(deviceUID: String?) throws {
        if let deviceUID, let deviceID = Self.deviceID(forUID: deviceUID) {
            Self.setInputDevice(deviceID, on: engine)
        }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.noInputDevice }

        let url = Store.recordingsDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        do {
            file = try AVAudioFile(forWriting: url, settings: Self.targetFormat.settings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        } catch {
            throw RecorderError.cannotCreateFile(error)
        }
        converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat)
        self.url = url

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        startedAt = Date()
    }

    /// Para a gravação e devolve o arquivo e a duração.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard engine.isRunning || file != nil else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        file = nil // fecha o arquivo (e grava o tamanho no cabeçalho)
        converter = nil
        lock.unlock()
        defer { url = nil; startedAt = nil }
        guard let url, let startedAt else { return nil }
        return (url, Date().timeIntervalSince(startedAt))
    }

    /// Para e apaga o arquivo (Cancel / Esc).
    func cancel() {
        if let result = stop() { try? FileManager.default.removeItem(at: result.url) }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        // Nível para a forma de onda.
        if let data = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            onLevel?(min(1, rms * 12))
        }

        lock.lock()
        defer { lock.unlock() }
        guard let converter, let file else { return }
        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 { try? file.write(from: out) }
    }

    // MARK: Dispositivos de entrada

    struct InputDevice: Identifiable, Hashable {
        let uid: String
        let name: String
        var id: String { uid }
    }

    static func inputDevices() -> [InputDevice] {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
        return session.devices.map { InputDevice(uid: $0.uniqueID, name: $0.localizedName) }
    }

    static var defaultInputName: String? { AVCaptureDevice.default(for: .audio)?.localizedName }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), uidPtr, &size, &deviceID)
        }
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private static func setInputDevice(_ id: AudioDeviceID, on engine: AVAudioEngine) {
        guard let unit = engine.inputNode.audioUnit else { return }
        var device = id
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &device, UInt32(MemoryLayout<AudioDeviceID>.size))
    }
}
