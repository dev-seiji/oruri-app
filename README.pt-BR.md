<p align="center"><img src="Icon/oruri-1024.png" width="160" alt="Ícone do Oruri: uma ōruri azul cantando num galho"></p>

<p align="center"><a href="README.md">🇺🇸 English</a> · 🇧🇷 Português</p>

# Oruri

O Oruri é um app de ditado para macOS feito em SwiftUI: segure uma tecla, fale, e o texto aparece no app em que você está digitando.
Ele também transcreve arquivos de áudio e vídeo que você arrasta para ele, um depois do outro.

**Versão atual: 0.6.4** — as notas completas ficam em Settings › Updates, dentro do app.

O nome vem da ōruri (オオルリ), um passarinho azul e cantor do Japão; o nome quer dizer "grande lápis-lazúli".

## Código aberto e app oficial

Este repositório é a parte aberta do Oruri, sob a GPL-3.0. Ele compila e funciona sozinho com os motores grátis:
transcrição no próprio Mac, Groq com a sua chave de API e um modelo local do Ollama para a limpeza por IA opcional.
Está planejado um app oficial do Oruri com recursos pagos a mais; esses recursos não fazem parte deste repositório.

O nome "Oruri" e o ícone identificam o app oficial. Se fizer um fork, use outro nome e outro ícone.

## Funcionalidades

- **Ditado em qualquer app** — segure a tecla (fn por padrão) para falar e solte para inserir o texto no app em foco.
  A tecla é escolhida pelo nome (Fn, Command, Option, Control, Shift) e, se quiser, pelo lado (esquerdo, direito ou qualquer um),
  ou você grava um atalho composto como ⌃⇧ ou ⌃⇧D (qualquer tecla, menos Esc, F1–F12, Backspace e Enter).
  Dois toques rápidos ligam o modo mãos-livres; Esc cancela.
- **Motores de transcrição**
  - No próprio Mac, com o `SpeechAnalyzer` + `SpeechTranscriber` da Apple (macOS 26+; em sistemas mais antigos usa o `SFSpeechRecognizer`) —
    texto já pontuado, sem precisar de chave e sem o áudio sair do Mac.
  - Na nuvem: Groq (Whisper large v3 / turbo), com a sua chave de API guardada no Keychain.
- **Fila de arquivos** — arraste áudios ou vídeos (WAV, MP3, M4A, MP4, MOV…) na Home, escolha pelo botão de pasta ou use *Abrir com › Oruri*;
  eles são convertidos e transcritos um depois do outro.
- **Tratamento do texto** — pontuação falada ("vírgula", "nova linha", "comma"…), remoção de palavras de preenchimento,
  números em dígitos (português e inglês, inclusive versões e decimais como 0.2.1) e um dicionário próprio com correção de palavras parecidas.
- **Correções faladas** — diga a parte errada, uma expressão de correção e a parte certa ("pro Pedro, errei, pro Paulo",
  "na quinta, quer dizer, na sexta", "…amanhã, né? Não, amanhã, depois de amanhã") e só a versão corrigida fica.
  Várias correções seguidas também funcionam; vale a última. Os casos simples são resolvidos por regras fixas, sem IA.
- **Limpeza por IA (opcional)** — a Groq (rápida, na nuvem, mesma chave da transcrição) ou um modelo local do Ollama limpa todo texto ditado. Ela só pode arrumar pontuação, maiúsculas e grafia e aplicar
  as correções faladas; se mudar um número, nome, negação ou palavra, tirar parte da frase ou reescrever, fica a transcrição original.
- **Entrega** — cola com ⌘V ou digita em qualquer app onde dá para escrever, inclusive apps feitos com Electron e Chromium
  (Claude, ChatGPT, Chrome, Slack); mantém ou restaura a área de transferência; mostra "Copied · ⌘V" na bolha de gravação
  quando não há onde colar ou falta a Acessibilidade; gravações muito longas são só copiadas e o texto vai literal em apps de IA e terminais.
- **Áudio sem fala** — gravações e arquivos sem fala são detectados pelo volume e descartados, em vez de transcritos.
- **Iniciar na barra de menus** — opcional: abre sem a janela e fica no Dock e na barra de menus.
- **Interface** — o microfone no meio da janela, com seletores de microfone e de modelo logo abaixo, as transcrições
  recentes em cartões e o histórico completo em See all; Settings numa gaveta com seções que abrem; botão de aparência
  (System, Light, Dark) na barra do topo; seção Usage com barrinhas de limite e custos; seção Help com perguntas frequentes, guia de cada tela, busca e contato; animações ao abrir e fechar.
- **Idiomas** — a interface em English, Español, Português ou 日本語 (Settings › Advanced › Language), mudando na
  hora; inglês por padrão. As traduções ficam em `Localization/translations.txt`.
- **Histórico** — mostra o que o reconhecedor ouviu ("Heard: …") quando é diferente do texto final; salvo no Mac, com busca, opção de retentar transcrições que falharam, limites de retenção e um comando de shell pós-gravação.

## Requisitos

- macOS 14 ou mais novo, de preferência com Apple silicon
- Swift 5.9+ (Xcode ou as Command Line Tools)

## Como compilar

```bash
./build-app.sh && open build/Oruri.app
```

O macOS amarra as permissões de Microfone, Reconhecimento de Fala e Acessibilidade à assinatura do app. O `build-app.sh` assina
com o primeiro certificado local de assinatura de código cujo nome termine em **Local Signing** (por exemplo *Oruri Local Signing*) quando existir um no seu Keychain, então as permissões continuam valendo
entre um build e outro; sem ele, usa assinatura ad-hoc e o macOS pede as permissões de novo a cada build.

Durante o desenvolvimento, também dá para usar `swift run`.

> Sem o Xcode completo, a macro `@State` do SwiftUI não pode ser expandida, por isso o projeto usa `@LocalState`
> (`Sources/Oruri/LocalState.swift`), um substituto equivalente feito com `StateObject`.

## Estrutura do projeto

| Caminho | O que é |
|---|---|
| `Sources/Oruri/OruriApp.swift` | Início do app, janelas e menu bar |
| `Sources/Oruri/AppState.swift` | Estado observável do app e as `Settings` |
| `Sources/Oruri/Store.swift` | Configurações, histórico e dicionário salvos; chaves de API no Keychain |
| `Sources/Oruri/AudioRecorder.swift` | Gravação do microfone em WAV mono 16 kHz, escolha do microfone |
| `Sources/Oruri/Usage.swift` | Uso da Groq contado no Mac, limites do plano grátis e preços |
| `Sources/Oruri/Transcription.swift` | Transcrição no Mac e na nuvem, conversão de arquivos de áudio e vídeo |
| `Sources/Oruri/TextPipeline.swift` | Pontuação falada, palavras de preenchimento, dicionário, números |
| `Sources/Oruri/LLMCleanup.swift` | Limpeza opcional com Groq ou Ollama, com trava de segurança |
| `Sources/Oruri/Delivery.swift` | Colar/digitar no app em foco, teclas de mídia, abrir ao iniciar sessão, comando pós-gravação |
| `Sources/Oruri/HotkeyMonitor.swift` | Teclas de ditado globais (segurar para falar / dois toques) |
| `Sources/Oruri/DictationController.swift` | Coordena gravar → transcrever → limpar → entregar → histórico |
| `Sources/Oruri/ContentView.swift` | Janela principal, barra do topo, botão de aparência, janela Pro |
| `Sources/Oruri/HomeView.swift` | Home: microfone, números, cartões recentes, histórico completo |
| `Sources/Oruri/DictionaryView.swift` | Dicionário próprio |
| `Sources/Oruri/SettingsView.swift` | Gaveta de configurações, suas seções e a Help |
| `Sources/Oruri/OnboardingView.swift` | Primeiro uso |
| `Sources/Oruri/RecordingIndicator.swift` | Bolha de gravação: ícone do app e linhas da voz, acima do Dock |
| `Sources/Oruri/OllamaService.swift` | Confere se o Ollama está rodando e liga ele sem o Terminal |
| `Sources/Oruri/Theme.swift` | Paleta de cores |
| `Sources/Oruri/Localization.swift` | Idiomas da interface: `T("…")` busca a tradução, o inglês é a chave |
| `Tests/OruriTests/` | Testes automáticos (Swift Testing), rodados pelo `./qa.sh` |
| `qa.sh` | QA depois de toda mudança: testes, traduções, build e abertura |
| `Localization/` | `translations.txt` (todos os textos em es, pt, ja) e `build.py`, que gera e confere os JSON |
| `Icon/` | Fontes do ícone (`oruri.svg` e `oruri-small.svg` para 16–32 px), a silhueta da barra de menus e o `AppIcon.icns` gerado |

## Paleta

Baseada no ruri-iro (瑠璃色), o azul lápis-lazúli tradicional japonês que dá nome à ōruri. Valores do modo claro / escuro.

| Papel | Token | Hex |
|---|---|---|
| Primária (azul ruri) | `brand` | `#1E50A2` / `#6E95E0` |
| Azul-marinho, texto de destaque | `brandDeep` | `#0F2350` / `#BCD0F5` |
| Azul suave, item selecionado | `brandSoft` | `#E6EDF8` / `#17233D` |
| Dourado, Pro e detalhes | `highlight` | `#C99A1E` / `#E3B94A` |
| Fundo | `contentBackground` | `#FFFFFF` / `#0D1220` |
| Superfície | `statsBackground` | `#F4F6FA` / `#161D2E` |
| Texto principal | `primaryText` | `#1A1F2B` / `#E8ECF4` |
| Texto secundário | `secondaryText` | `#5D6573` / `#A2ABBC` |
| Gravando | `recording` | `#D94A3D` / `#E5675B` |

## Como contribuir

Relatos de bug e sugestões são bem-vindos como issues; pull requests de código não são aceitos por enquanto. Veja o [CONTRIBUTING.md](CONTRIBUTING.md).
Falhas de segurança: veja o [SECURITY.md](SECURITY.md).

## Licença

[GPL-3.0](LICENSE).
