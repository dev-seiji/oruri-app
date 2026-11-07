#!/bin/zsh
# Compila o Oruri e empacota em build/Oruri.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Oruri"

APP="build/Oruri.app"
rm -rf "${APP:?}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Oruri"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Localization/*.json "$APP/Contents/Resources/" 2>/dev/null || true
cp Icon/menubar/MenuBarIcon.png Icon/menubar/MenuBarIcon@2x.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Oruri</string>
    <key>CFBundleIdentifier</key><string>com.seiji.oruri</string>
    <key>CFBundleName</key><string>Oruri</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDisplayName</key><string>Oruri</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.6.6</string>
    <key>CFBundleVersion</key><string>30</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Audio and video</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.audio</string><string>public.movie</string></array>
        </dict>
    </array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSMicrophoneUsageDescription</key><string>Oruri needs the microphone to hear your dictation.</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>Oruri uses on-device speech recognition to turn your voice into text.</string>
    <key>NSAppleEventsUsageDescription</key><string>Oruri pauses Spotify, Music or videos in Chrome while you dictate and resumes them afterwards.</string>
    <key>NSAccessibilityUsageDescription</key><string>Oruri needs Accessibility to paste your dictated text into other apps.</string>
</dict>
</plist>
PLIST

# Assinatura estável para o macOS lembrar as permissões entre builds: usa o primeiro certificado local
# de assinatura de código cujo nome termina em "Local Signing" (ex.: "Oruri Local Signing").
# Sem ele, cai para a assinatura ad-hoc e o macOS pede as permissões de novo a cada build.
# Hardened runtime: bloqueia injeção de código no app, que usaria as permissões de Microfone e Acessibilidade
# dele (Claude Security, F2). As autorizações de microfone e Apple Events ficam em Oruri.entitlements.
IDENTITY="$(security find-identity -p codesigning 2>/dev/null | sed -n 's/.*"\(.* Local Signing\)".*/\1/p' | head -1)"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --options runtime --entitlements Oruri.entitlements --sign "$IDENTITY" "$APP" >/dev/null
else
    echo "Aviso: nenhum certificado \"… Local Signing\" encontrado; usando assinatura ad-hoc."
    codesign --force --options runtime --entitlements Oruri.entitlements --sign - "$APP" >/dev/null
fi
echo "OK: $(pwd)/$APP"
