# Changelog

All notable changes to Oruri, newest first. The same notes are in the app under Settings › Updates.

## 0.7.1 — November 2026

- Security fixes: the post-record command only runs if it's the one you approved in Settings, and a file with a fake duration can no longer crash the app.

## 0.7.0 — November 2026

- New look: a side rail with Home, History, Usage and Help opens on hover and shows the names; the menu button keeps it open.
- Home shows a song line that moves with your voice (click it to record), and your dictations appear like a notebook.

## 0.6.6 — November 2026

- Settings › Usage now counts AI cleanup with Groq: its own daily allowance and the month total, and the Home warning covers it too.

## 0.6.5 — November 2026

- With Groq, "Improve sentences" lets the AI reword confusing sentences while keeping numbers, names and meaning.
- Groq cleanup works again: Oruri now picks a Groq model that is available.

## 0.6.4 — November 2026

- Long files are compressed before going to Groq, so one file can be up to about 1 h 40 min instead of 12 min.

## 0.6.3 — November 2026

- AI cleanup can now use Groq: much faster than Ollama, free with the same Groq key. Pick it in Settings › Output.

## 0.6.2 — November 2026

- When no text box is selected, the text is copied and "Copied · ⌘V" appears again, including in Chrome, Claude and other Electron apps.

## 0.6.1 — November 2026

- Settings › Help › Contact has the real support email, and the Pro window has a button to join the waitlist.

## 0.6.0 — November 2026

- Paid cloud AI with your own key (one transcription engine and one cleanup option) was removed. AI cleanup now runs only on Ollama, on this Mac; if you used the removed engine, the app switches to On-device.

## 0.5.8 — November 2026

- The buttons at the top right sit a little lower and further from the window edge.

## 0.5.7 — November 2026

- Pause media now also pauses videos playing in Chrome and resumes them afterwards. Settings › Dictation shows whether Chrome allows it, with a button that takes you to the one setting it needs.
- Security fixes: a long run of number words can no longer close the app, and Oruri is signed so other programs can't inject code into it and use its permissions.

## 0.5.6 — November 2026

- Behind-the-scenes cleanup: leftover options from older versions were removed. Nothing changes in how Oruri works, and your settings stay as they were.

## 0.5.5 — November 2026

- Settings › Usage now shows Groq's requests the way Groq counts them: a daily allowance that refills, with one request coming back about every 43 seconds.

## 0.5.4 — November 2026

- Settings › Output shows whether Ollama is running, with a Start Ollama button: no Terminal needed.
- When AI cleanup uses Ollama and it's off, a warning on Home takes you straight to that button.

## 0.5.3 — November 2026

- AI cleanup keeps what you said: if the AI changes a number, a name, a "not" or a word, or drops part of the sentence, your original text is used.
- Ollama no longer answers your dictation instead of cleaning it.

## 0.5.2 — November 2026

- Oruri Pro has a waitlist: click Pro at the top to join and hear when it's ready.
- Help › Contact has a Send email button that opens your email app.

## 0.5.0 — November 2026

- New name: Oruri, after the ōruri, a blue songbird from Japan.
- New blue look, a new app icon and a new menu bar icon.

## 0.4.2 — October 2026

- Noise, key clicks and breathing no longer turn into invented phrases.
- Ollama stays loaded while Oruri is open, so AI cleanup answers in about a second.
- Groq uses its fastest model, whisper-large-v3-turbo, by default.

## 0.4.1 — October 2026

- Recording starts right away: pausing Music or Spotify no longer holds up the bubble or the key.
- Background noise no longer counts as speech: silent recordings are dropped instead of being sent for transcription.

## 0.4.0 — October 2026

- Oruri now speaks Spanish, Portuguese and Japanese: pick the language in Settings › Advanced › Language. It always starts in English.
- Every screen switches on the spot: Home, Settings, Help, notices, the menu bar and these notes.
- The transcription language stays separate in Settings › Output, so you can use the app in one language and dictate in another.

## 0.3.5 — October 2026

- New folder button at the bottom right of Home: click it to choose audio or video files in Finder and add them to the transcription queue.

## 0.3.4 — October 2026

- With Ollama chosen for AI cleanup, every text you dictate is cleaned, not just long or complex ones.
- The safety check stays: if Ollama adds words you didn't say or drops too much, your original text is kept.
- New Help answer: how to turn Ollama on and how to use it in AI apps and terminals too.

## 0.3.3 — October 2026

- New Usage section in Settings: how much of Groq's free limits you've used, with a bar for audio per day, audio per hour and requests per day.
- A warning appears on Home when 15% or less of a limit is left, with a button that opens Usage.

## 0.3.2 — October 2026

- Help now answers common questions: paste problems, spoken corrections, numbers, Caps Lock shortcuts, engines, Ollama and where your data is stored.
- New Where to find things guide: what's on each screen and in each Settings section.
- A search field at the top of Help filters the questions and the guide as you type.

## 0.3.1 — October 2026

- A smaller, simpler recording bubble in the same color: just the icon of the app you're dictating into and the lines of your voice.
- No more cancel and stop buttons on the bubble: release the key to stop, press Esc to cancel.
- The bubble rises from the bottom center of the screen, just above the Dock.

## 0.3.0 — October 2026

- A new look: no sidebar. The microphone sits in the middle of the window, with the microphone and speech model right below it and your numbers in one line.
- Settings opens as a drawer on the right, and each section expands to show its options.
- New appearance button at the top: a sun or a moon shows the current look, and a click picks System, Light or Dark. Also in the menu bar.

## 0.2.3 — October 2026

- Combined shortcuts: in Settings › Dictation › Add another › Combined shortcut, press the keys together (⌃⇧ or ⌃⇧D) and they become your dictation shortcut. Hold to talk and double tap work the same.
- Caps Lock works as on/off: tap to start, tap again to stop. With Caps Lock, only ⌃ ⌥ ⇧ ⌘ fn can be combined.
- Simple keys are picked by name (Fn, Command, Option, Control, Shift), then the side if you want: left, right or either.

## 0.2.2 — October 2026

- Numbers with dots and commas stay together: versions like 0.2.1, decimals like 1,5 and times like 10:30 are no longer split.
- Spoken versions and decimals: "zero ponto dois ponto um" becomes 0.2.1 and "zero point two" becomes 0.2.

## 0.2.1 — October 2026

- Start in the menu bar now works: Oruri opens without its window and stays in the Dock and the menu bar. Click the Dock icon to open the window.

## 0.2.0 — October 2026

- Pastes into any app you can type in, including Claude, ChatGPT, Chrome and WhatsApp.
- Spoken corrections: say "errei", "quer dizer" or "não, …" and only the corrected version is kept, even after several corrections in a row.
- Spoken percentages become the % sign: "100 por cento" turns into 100%.

## 0.1.0 — October 2026

- Dictate anywhere: hold your key, talk and release — the text lands where you're typing.
- Transcription on this Mac with punctuation, or in the cloud with Groq using your own key.
- Spoken punctuation, filler-word removal, numbers as digits and a custom dictionary.
