import SwiftUI
import UniformTypeIdentifiers

/// Home (0.7.0, "Canto"): a linha do canto no centro (reage à voz; clicar grava), microfone e modelo
/// logo abaixo, os números numa linha e os últimos ditados em serifa, como um caderno.
struct HomeView: View {
    @Environment(AppState.self) private var state
    @LocalState private var dropTargeted = false

    var body: some View {
        stage
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.accentSoft.opacity(0.7)))
                    .overlay(Label(T("Drop audio files to transcribe"), systemImage: "waveform")
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Theme.brandDeep))
                    .padding(12)
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: dropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            state.dictation?.enqueue(files: urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }

    private var stage: some View {
        VStack(spacing: 0) {
            if let warning = state.ollamaWarning {
                UsageWarningBanner(text: warning, actionTitle: "Open settings") { state.openSettings(.output) }
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let warning = state.groqLimitWarning {
                UsageWarningBanner(text: warning) { state.openSettings(.usage) }
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 8)
            SongLine(isRecording: state.isRecording, level: state.audioLevel) { state.toggleRecording() }
                .disabled(state.phase == .transcribing)
            StageHint()
                .padding(.top, 30)
            HStack(spacing: 8) {
                MicrophonePickerButton()
                ModelPill { state.openSettings(.models) }
            }
            .padding(.top, 12)
            StatsLine()
                .padding(.top, 12)
            Spacer(minLength: 16)
            RecentStrip { withAnimation(.easeInOut(duration: 0.22)) { state.selectedTab = .history } }
            StageFooter()
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }
}

/// Aviso no topo da Home quando sobra 15% ou menos de um limite grátis da Groq.
struct UsageWarningBanner: View {
    let text: String
    var actionTitle: String? = nil
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.recording)
            Text(text)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(T(actionTitle ?? "See usage"), action: action)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(Theme.recording.opacity(0.10)))
        .overlay(Capsule().stroke(Theme.recording.opacity(0.30)))
    }
}

/// Frase sob o microfone; muda enquanto grava ou transcreve.
struct StageHint: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            switch state.phase {
            case .recording:
                Text(T("Listening… click to stop"))
            case .transcribing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(T("Transcribing…"))
                }
            case .idle:
                HStack(spacing: 7) {
                    Text(T("Hold"))
                    KeyCap(text: ComboShortcut.displayName(state.settings.triggers.first ?? "fn").replacingOccurrences(of: "Fn", with: "fn"))
                    Text(T("anywhere, or click"))
                }
            }
        }
        .id(state.phase)
        .transition(.opacity.combined(with: .offset(y: 4)))
        .font(.system(size: 17, weight: .semibold, design: .rounded))
        .foregroundStyle(Theme.primaryText)
        .frame(height: 26)
        .animation(.easeOut(duration: 0.22), value: state.phase)
    }
}

/// Números do ditado numa linha só.
struct StatsLine: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let saved = state.secondsSaved >= 120 ? ("\(state.secondsSaved / 60)", T("min saved")) : ("\(state.secondsSaved)", T("sec saved"))
        let wpm = state.dictationSeconds > 0 ? "\(state.dictatedWords * 60 / max(state.dictationSeconds, 1))" : "—"
        return (stat("\(state.dictatedWords)", T("words"))
            + dot + stat(saved.0, saved.1)
            + dot + stat("\(state.dictationSeconds)", T("sec dictating"))
            + dot + stat(wpm, T("wpm")))
            .font(.system(size: 11.5))
            .monospacedDigit()
    }

    private var dot: Text { Text("  ·  ").foregroundStyle(Theme.tertiaryText) }

    private func stat(_ value: String, _ unit: String) -> Text {
        Text(value).fontWeight(.semibold).foregroundStyle(Theme.secondaryText)
            + Text(" " + T(unit)).foregroundStyle(Theme.tertiaryText)
    }
}

/// Faixa "Recent": as 3 transcrições mais novas em linhas, e "See all" para o Histórico.
struct RecentStrip: View {
    @Environment(AppState.self) private var state
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(T("Recent"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if !state.recordings.isEmpty {
                    Button(action: onSeeAll) {
                        Text(T("See all %ld ›", state.recordings.count))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)

            if state.recordings.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                    Text(T("No recordings yet. Hold the key and talk, or drop an audio file here."))
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 104)
                .background(RoundedRectangle(cornerRadius: 14).stroke(Theme.statsBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            } else {
                VStack(spacing: 0) {
                    ForEach(state.recordings.prefix(3)) { recording in
                        RecentCard(recording: recording)
                            .id(recording.id)
                            .transition(.opacity)
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.recordings.map(\.id))
    }
}

struct RecentCard: View {
    @Environment(AppState.self) private var state
    let recording: Recording
    @LocalState private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(recording.date, format: .dateTime.hour().minute())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.tertiaryText)
                .monospacedDigit()
                .frame(width: 42, alignment: .leading)
            Group {
                switch recording.status {
                case .processing:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(T("Transcribing…")).foregroundStyle(Theme.secondaryText)
                    }
                    .font(.system(size: 12))
                case .failed:
                    Label(T(recording.error ?? "Transcription failed"), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.recording)
                        .lineLimit(2)
                case .done:
                    (recording.fileName.map { Text($0 + " — ").foregroundStyle(Theme.secondaryText) } ?? Text(""))
                        + Text(recording.text).foregroundStyle(Theme.primaryText)
                }
            }
            .font(.system(size: 13.5, design: .serif))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            if hovering && recording.status != .processing {
                RecordingActions(recording: recording)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.statsBackground : Color.clear))
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(recording.status == .done ? recording.text : "")
    }
}

/// Copiar, transcrever de novo e apagar (aparecem ao passar o mouse).
struct RecordingActions: View {
    @Environment(AppState.self) private var state
    let recording: Recording

    var body: some View {
        HStack(spacing: 10) {
            if recording.status == .done {
                Button { Delivery.copy(recording.text); state.showToast(T("Copied")) } label: { Image(systemName: "doc.on.doc") }
                    .help(T("Copy to Clipboard"))
            }
            if recording.audioFile != nil {
                Button { state.dictation?.retry(recording) } label: { Image(systemName: "arrow.clockwise") }
                    .help(T("Regenerate transcription"))
            }
            Button { state.dictation?.delete(recording) } label: { Image(systemName: "trash") }
                .help(T("Remove this entry"))
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(Theme.secondaryText)
    }
}

/// Rodapé da Home: privacidade à esquerda, arquivos à direita.
struct StageFooter: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock")
            Text(T("Everything stays on this Mac"))
            Spacer()
            if state.queuedFiles > 0 {
                ProgressView().controlSize(.mini)
                Text(T("Transcribing files… %ld left", state.queuedFiles))
            } else {
                Image(systemName: "doc")
                Text(T("Drop audio or MP4 anywhere to transcribe"))
            }
            ChooseFilesButton { state.dictation?.enqueue(files: $0) }
                .padding(.leading, 2)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.tertiaryText)
    }
}

/// Botãozinho de pasta com "+": abre o Finder para escolher áudios ou vídeos para transcrever.
struct ChooseFilesButton: View {
    let onPick: ([URL]) -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: pick) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Theme.accent : Theme.secondaryText)
                .frame(width: 28, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.accentSoft : Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cardBorder))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(T("Choose audio or video files to transcribe"))
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.title = T("Choose files to transcribe")
        panel.prompt = T("Transcribe")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        if panel.runModal() == .OK, !panel.urls.isEmpty { onPick(panel.urls) }
    }
}

/// Lista completa do histórico (aba da barra lateral; "See all" na Home também abre).
struct HistoryPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(T("History"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                SearchField(text: $state.historySearch, placeholder: "Search in transcriptions")
                    .frame(width: 280)
            }
            .padding(.top, 14)

            HistoryList()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 28)
    }
}

struct ModelPill: View {
    @Environment(AppState.self) private var state
    let action: () -> Void
    private var provider: TranscriptionProvider { TranscriptionProvider(rawValue: state.settings.engine) ?? .apple }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "cpu").font(.system(size: 10.5))
                Text(provider.title).font(.system(size: 12, weight: .semibold))
                Text(provider == .apple ? T(state.settings.transcriptionLanguage) : state.settings.activeModel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.tertiaryText)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.pillBorder))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(T("Speech model"))
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
            TextField(T(placeholder), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().stroke(Theme.pillBorder))
    }
}

struct HistoryList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.recordings.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.secondaryText)
                Text(T("No recordings yet"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(T("Hold the key and talk, or click the microphone on Home"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if state.filteredRecordings.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Text(T("No results found")).font(.system(size: 13, weight: .semibold))
                Text(T("Try different search terms")).font(.system(size: 11))
                Spacer()
            }
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(state.filteredRecordings) { RecordingRow(recording: $0) }
                }
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
        }
    }
}

struct RecordingRow: View {
    @Environment(AppState.self) private var state
    let recording: Recording
    @LocalState private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(recording.date, format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                if let name = recording.fileName {
                    Label(name, systemImage: "doc")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                if hovering && recording.status != .processing {
                    RecordingActions(recording: recording)
                        .transition(.opacity)
                }
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.15), value: hovering)

            switch recording.status {
            case .processing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(T("Transcribing…")).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
            case .failed:
                Label(T(recording.error ?? "Transcription failed"), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.recording)
            case .done:
                Text(recording.text)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(Theme.primaryText)
                    .textSelection(.enabled)
                if let raw = recording.rawText, raw != recording.text.trimmingCharacters(in: .whitespaces) {
                    Text(T("Heard: %@", raw))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(hovering ? Theme.statsBackground : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
        .onHover { hovering = $0 }
    }
}

/// A linha do canto (0.7.0): desenha a voz como o canto da ōruri. Parada, é um traço calmo; gravando,
/// ondula com o volume do microfone e o ponto dourado corre por ela. Clicar grava ou para.
struct SongLine: View {
    let isRecording: Bool
    let level: Float
    let action: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(paused: !isRecording)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let mid = size.height / 2
                    let amp = isRecording ? mid * (0.25 + 0.7 * Double(level)) : mid * (hovering ? 0.42 : 0.32)
                    let phase = isRecording ? t * 2.4 : 0
                    var path = Path()
                    var dot = CGPoint(x: size.width / 2, y: mid)
                    for step in 0...160 {
                        let x = size.width * Double(step) / 160
                        let u = Double(step) / 160
                        let envelope = sin(.pi * u)   // as pontas descansam no meio, como um canto que começa e termina
                        let y = mid - amp * envelope * (sin(u * 13 + phase) * 0.7 + sin(u * 29 - phase * 1.3) * 0.3)
                        let point = CGPoint(x: x, y: y)
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        if step == (isRecording ? Int((t * 30).truncatingRemainder(dividingBy: 160)) : 72) { dot = point }
                    }
                    context.stroke(path, with: .color(Theme.accent),
                                   style: StrokeStyle(lineWidth: isRecording ? 4 : 3, lineCap: .round, lineJoin: .round))
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)),
                                 with: .color(isRecording ? Theme.recording : Theme.highlight))
                }
            }
            .frame(maxWidth: 520)
            .frame(height: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
        .help(T(isRecording ? "Stop" : "Record"))
        .accessibilityLabel(T(isRecording ? "Stop" : "Record"))
    }
}

/// Pílula do microfone: mostra o atual e abre um balão com os disponíveis.
struct MicrophonePickerButton: View {
    @Environment(AppState.self) private var state
    @LocalState private var showing = false
    @LocalState private var devices: [AudioRecorder.InputDevice] = []

    private var currentName: String {
        if state.settings.microphone == "System Default" { return AudioRecorder.defaultInputName ?? T("System Default") }
        return devices.first { $0.uid == state.settings.microphone }?.name
            ?? AudioRecorder.inputDevices().first { $0.uid == state.settings.microphone }?.name
            ?? T("Unavailable")
    }

    var body: some View {
        Button {
            devices = AudioRecorder.inputDevices()
            showing.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mic").font(.system(size: 10.5))
                Text(currentName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.tertiaryText)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 12)
            .frame(maxWidth: 240)
            .frame(height: 28)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.pillBorder))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(T("Microphone"))
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(T("Microphone"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                row(title: "System Default", subtitle: AudioRecorder.defaultInputName, value: "System Default")
                if !devices.isEmpty { Divider().padding(.vertical, 4) }
                ForEach(devices) { device in
                    row(title: device.name, subtitle: nil, value: device.uid)
                }
                if devices.isEmpty {
                    Text(T("No microphones available"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 10)
                }
            }
            .padding(10)
            .frame(width: 260)
        }
    }

    private func row(title: String, subtitle: String?, value: String) -> some View {
        let selected = state.settings.microphone == value
        return Button {
            state.settings.microphone = value
            showing = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(selected ? 1 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(T(title)).font(.system(size: 13)).foregroundStyle(Theme.primaryText)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accentSoft : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
