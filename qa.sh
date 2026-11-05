#!/bin/zsh
# QA do Oruri: rodar depois de toda mudança, antes de mandar para revisão.
#   1. testes automáticos (texto, números, correções, silêncio, invenções da IA, uso, idiomas)
#   2. traduções completas nos 4 idiomas
#   3. build do app
#   4. o app abre e continua aberto
set -uo pipefail
cd "$(dirname "$0")"
fail=0
step() { print -P "%B▸ $1%b" }
ok() { print -P "  %F{green}✔ $1%f" }
bad() { print -P "  %F{red}✘ $1%f"; fail=1 }

step "Testes automáticos"
# Só com as Command Line Tools, o swift test às vezes não acha o plugin das macros do Swift Testing: indicamos o caminho.
plugins=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
out=$(swift test -Xswiftc -plugin-path -Xswiftc "$plugins" 2>&1)
summary=$(print -r -- "$out" | grep -E "Test run with" | tail -1)
if print -r -- "$out" | grep -q "passed after" && ! print -r -- "$out" | grep -qE "✘|error:"; then ok "$summary"
else print -r -- "$out" | grep -E "✘|error:" | head -20; bad "${summary:-testes não rodaram}"; fi

step "Traduções"
if trans=$(python3 Localization/build.py 2>&1); then ok "$(print -r -- "$trans" | head -1)"
else print -r -- "$trans"; bad "faltam traduções"; fi

step "Build do app"
if build=$(./build-app.sh 2>&1); then ok "$(defaults read "$PWD/build/Oruri.app/Contents/Info" CFBundleShortVersionString) compilado"
else print -r -- "$build" | grep -E "error" | head; bad "build falhou"; fi
for f in es pt ja; do [[ -f build/Oruri.app/Contents/Resources/$f.json ]] || bad "falta $f.json no app"; done

step "App abre"
pkill -x Oruri 2>/dev/null; sleep 1
open build/Oruri.app; sleep 4
if pgrep -x Oruri >/dev/null; then ok "Oruri rodando"; else bad "o app fechou sozinho"; fi

print
if (( fail )); then print -P "%F{red}%BQA reprovado%b%f"; exit 1; else print -P "%F{green}%BQA aprovado%b%f"; fi
