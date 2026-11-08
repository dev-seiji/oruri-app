<p align="center"><img src="Icon/oruri-1024.png" width="160" alt="Oruri icon: a blue ōruri singing on a branch"></p>

<h1 align="center">Oruri</h1>

<p align="center">Hold a key, talk, and the text lands in whatever Mac app you're using.</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-1E50A2" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-5.9-1E50A2" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-GPL--3.0-1E50A2" alt="GPL-3.0 license">
  <img src="https://img.shields.io/badge/built%20with-Claude%20Code-C99A1E" alt="Built with Claude Code">
</p>

<p align="center">🇺🇸 English · <a href="README.es.md">🇪🇸 Español</a> · <a href="README.pt-BR.md">🇧🇷 Português</a> · <a href="README.ja.md">🇯🇵 日本語</a></p>

Oruri is a macOS dictation app written in SwiftUI: hold a key, talk, and the text lands in whatever app you're using.
It also transcribes audio and video files you drop on it, one after another.

A personal portfolio project, vibe coded with Claude Code. It isn't distributed as a ready-made app: build it from the
source (see Get started below).

**Current version: 0.7.1** — full release notes in [CHANGELOG.md](CHANGELOG.md) and in the app under Settings › Updates.

Oruri is named after the ōruri (オオルリ), a blue songbird from Japan whose name means "great lapis lazuli".

## How it was built

Oruri is a personal portfolio project, vibe coded with Claude ([Claude Code](https://claude.com/claude-code)) to learn how AI
tools behave inside a real app. I described what I wanted in plain language, tested every version on my own Mac and
approved each change; Claude wrote the code. Along the way:

- a roadmap of 29 items, taken one at a time from idea to release (versions 0.1.0 to 0.7.1, see [CHANGELOG.md](CHANGELOG.md));
- every change goes through `./qa.sh`: 59 automated tests (number words, spoken corrections, AI safety checks, silence
  detection…), a translation check for the 4 interface languages, the build and a launch check;
- two Claude Security scans, with every confirmed finding fixed (in 0.5.7 and 0.7.1);
- decisions backed by real measurements, such as Groq's rate-limit headers and Ollama's speed on an 8 GB Mac.

It's open source under the GPL-3.0 and runs with free engines: on-device transcription, Groq with your own API key, and
Groq or a local Ollama model for the optional AI cleanup. There is no signed download and no paid version: build it from
source (see Get started).

## Features

- **Dictation anywhere** — hold your key (fn by default) to talk, release to insert the text in the focused app.
  Pick the key by name (Fn, Command, Option, Control, Shift) and, if you want, the side (left, right or either),
  or record a combined shortcut such as ⌃⇧ or ⌃⇧D (any key except Esc, F1–F12, Backspace and Enter).
  Double-tap for hands-free mode; Esc cancels.
- **Transcription engines**
  - On-device with Apple's `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26+, falls back to `SFSpeechRecognizer` on older systems) —
    punctuated text, no key needed, audio never leaves the Mac.
  - Cloud: Groq (Whisper large v3 / turbo) with your own API key, stored in the Keychain.
- **File queue** — drop audio or video files (WAV, MP3, M4A, MP4, MOV…) on Home, pick them with the folder button, or use *Open With › Oruri*;
  they're converted and transcribed one after another.
- **Text pipeline** — spoken punctuation ("comma", "vírgula", "new line"…), filler-word removal, numbers as digits
  (English and Portuguese, including versions and decimals such as 0.2.1), a custom dictionary with sound-alike correction.
- **Spoken corrections** — say the wrong part, a correction phrase and the right part ("pro Pedro, errei, pro Paulo",
  "na quinta, quer dizer, na sexta", "…amanhã, né? Não, amanhã, depois de amanhã") and only the corrected version is kept.
  Several corrections in a row work too; the last one wins. Simple cases are handled by fixed rules, with no AI.
- **AI cleanup (optional)** — Groq (fast, in the cloud, same key as transcription) or a local Ollama model cleans every dictated text. It may only fix punctuation, capitals and spelling and apply spoken
  corrections; if it changes a number, name, negation or word, drops part of the sentence or rewrites it, the transcript is kept.
- **Delivery** — paste with ⌘V or type into any app you can write in, including Electron and Chromium apps
  (Claude, ChatGPT, Chrome, Slack); keep or restore the clipboard; a "Copied · ⌘V" notice in the recording bubble
  when there's nowhere to paste or Accessibility is off; very long recordings are only copied; verbatim mode in AI and terminal apps.
- **Blank audio** — recordings and files with no speech are detected by their volume and dropped instead of transcribed.
- **Start in the menu bar** — optional: open without the window, staying in the Dock and the menu bar.
- **Interface** — a side rail with Home, History, Usage and Help (opens on hover with names; the menu button keeps it open);
  on Home, a song line that moves with your voice (click it to record), microphone and model pickers, and the latest
  dictations in serif like a notebook; Settings in a drawer with expandable sections; Dictionary, Pro, appearance (System,
  Light, Dark) and Settings in the top bar; Usage with limit bars and costs; Help with FAQ, a guide to each screen, search and contact.
- **Languages** — the interface in English, Español, Português or 日本語 (Settings › Advanced › Language), switching
  on the spot; English by default. Translations live in `Localization/translations.txt`.
- **History** — shows what the recognizer heard ("Heard: …") when it differs from the final text; saved locally, searchable, retry failed transcriptions, retention limits, post-record shell hook.

## Privacy

- With the on-device engine and Ollama, nothing leaves your Mac.
- With Groq, the recorded audio (and, for AI cleanup, the text) is sent to Groq with your own API key.
- API keys live in the macOS Keychain, never in files or in the code. History and recordings stay in
  `~/Library/Application Support/Oruri`, with retention limits and a delete-all button.

## Get started

### Requirements

- macOS 14 or later, Apple silicon recommended
- Swift 5.9+ (Xcode or the Command Line Tools)

### Build and run

1. Clone the repository and build the app:

   ```bash
   git clone https://github.com/dev-seiji/oruri-app.git
   cd oruri-app
   ./build-app.sh && open build/Oruri.app
   ```

2. Follow the onboarding: allow Microphone, Accessibility (so Oruri can paste) and Speech Recognition, then pick your dictation key.
3. Optional: add a free [Groq API key](https://console.groq.com/keys) in Settings › Models for fast cloud transcription and AI cleanup,
   or install [Ollama](https://ollama.com) for AI cleanup that stays on your Mac.
4. Hold fn and talk.

To check everything after a change, run `./qa.sh`: tests, the translation check, the build and a launch check.

macOS ties Microphone, Speech Recognition and Accessibility permissions to the app's signature. `build-app.sh` signs
with the first local code-signing certificate whose name ends in **Local Signing** (for example *Oruri Local Signing*) when one exists in your keychain, so permissions survive rebuilds;
otherwise it falls back to ad-hoc signing and macOS will ask again after every build.

During development you can also use `swift run`.

> Without a full Xcode install, SwiftUI's `@State` macro can't be expanded, so the project uses `@LocalState`
> (`Sources/Oruri/LocalState.swift`), a drop-in replacement built on `StateObject`.

## Project layout

| Path | What it is |
|---|---|
| `Sources/Oruri/OruriApp.swift` | App entry point, windows and menu bar |
| `Sources/Oruri/AppState.swift` | Observable app state and `Settings` |
| `Sources/Oruri/Store.swift` | Settings, history and dictionary persistence; Keychain for API keys |
| `Sources/Oruri/AudioRecorder.swift` | Microphone capture to 16 kHz mono WAV, input device selection |
| `Sources/Oruri/Usage.swift` | Groq usage counted on this Mac, free-plan limits and prices |
| `Sources/Oruri/Transcription.swift` | On-device and cloud transcription, audio/video file conversion |
| `Sources/Oruri/TextPipeline.swift` | Spoken punctuation, fillers, dictionary, number words |
| `Sources/Oruri/LLMCleanup.swift` | Optional Groq or Ollama cleanup with a safety check |
| `Sources/Oruri/Delivery.swift` | Paste/type into the focused app, media keys, launch at login, post-record hook |
| `Sources/Oruri/HotkeyMonitor.swift` | Global hold-to-talk / double-tap trigger keys |
| `Sources/Oruri/DictationController.swift` | Orchestrates record → transcribe → clean → deliver → history |
| `Sources/Oruri/ContentView.swift` | Main window, top bar, appearance button, Pro window |
| `Sources/Oruri/HomeView.swift` | Home: microphone, stats, recent cards, full history |
| `Sources/Oruri/DictionaryView.swift` | Custom dictionary |
| `Sources/Oruri/SettingsView.swift` | Settings drawer, its sections and Help |
| `Sources/Oruri/OnboardingView.swift` | First-run onboarding |
| `Sources/Oruri/RecordingIndicator.swift` | Recording bubble: app icon and voice lines, above the Dock |
| `Sources/Oruri/OllamaService.swift` | Checks whether Ollama is running and starts it without the Terminal |
| `Sources/Oruri/Theme.swift` | Color palette |
| `Sources/Oruri/Localization.swift` | Interface languages: `T("…")` looks up the translation, English is the key |
| `Tests/OruriTests/` | Automated tests (Swift Testing), run by `./qa.sh` |
| `qa.sh` | QA after every change: tests, translations, build, launch |
| `Localization/` | `translations.txt` (all texts in es, pt, ja), `build.py` to generate and check the JSON files |
| `Icon/` | App icon sources (`oruri.svg`, `oruri-small.svg` for 16–32 px), the menu bar silhouette and the generated `AppIcon.icns` |

## Palette

Based on ruri-iro (瑠璃色), the traditional Japanese lapis lazuli blue the ōruri is named after. Light / dark values.

| Role | Token | Hex |
|---|---|---|
| Primary (ruri blue) | `brand` | `#1E50A2` / `#6E95E0` |
| Navy, highlighted text | `brandDeep` | `#0F2350` / `#BCD0F5` |
| Soft blue, selected item | `brandSoft` | `#E6EDF8` / `#17233D` |
| Gold, Pro and details | `highlight` | `#C99A1E` / `#E3B94A` |
| Background | `contentBackground` | `#FFFFFF` / `#0D1220` |
| Surface | `statsBackground` | `#F4F6FA` / `#161D2E` |
| Primary text | `primaryText` | `#1A1F2B` / `#E8ECF4` |
| Secondary text | `secondaryText` | `#5D6573` / `#A2ABBC` |
| Recording | `recording` | `#D94A3D` / `#E5675B` |

## Acknowledgments

- Apple's Speech framework (`SpeechAnalyzer` and `SFSpeechRecognizer`) for on-device transcription
- [Groq](https://groq.com) for fast Whisper transcription and text models
- [Ollama](https://ollama.com) for running AI cleanup locally
- [Claude Code](https://claude.com/claude-code), the AI pair programmer this app was vibe coded with

## Contributing

Bug reports and suggestions are welcome as issues; code pull requests aren't accepted for now. See [CONTRIBUTING.md](CONTRIBUTING.md).
Security issues: see [SECURITY.md](SECURITY.md).

## License

[GPL-3.0](LICENSE).
