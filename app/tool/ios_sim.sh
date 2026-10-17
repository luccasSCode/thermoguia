#!/usr/bin/env bash
# Abre o simulador iOS de forma leve e roda o app nele.
#
# Uso (a partir de app/):
#   ./tool/ios_sim.sh                     # iPhone 18 Pro + flutter run
#   ./tool/ios_sim.sh "iPhone 17"         # outro aparelho
#   ./tool/ios_sim.sh "iPhone 18 Pro" --boot-only
#
# O que deixa mais rápido:
#   - desliga outros simuladores ligados (cada um consome 1–3 GB de RAM);
#   - destrava um aparelho preso em "Booting";
#   - liga pelo simctl e espera o boot terminar antes de abrir a janela;
#   - desativa animações e serviços pesados de fundo do simulador.
set -euo pipefail

DEVICE_NAME="${1:-iPhone 18 Pro}"
BOOT_ONLY="${2:-}"
API_URL="${API_URL:-http://localhost:8080}"

cd "$(dirname "$0")/.."

udid=$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
devs = json.load(sys.stdin)["devices"]
# Prefere o runtime mais novo que tiver o aparelho.
for runtime in sorted(devs, reverse=True):
    for d in devs[runtime]:
        if d["name"] == name:
            print(d["udid"]); sys.exit()
' "$DEVICE_NAME")

if [[ -z "$udid" ]]; then
  echo "Simulador \"$DEVICE_NAME\" não encontrado. Disponíveis:" >&2
  xcrun simctl list devices available | grep -E "iPhone|iPad" >&2
  exit 1
fi

state=$(xcrun simctl list devices | grep "$udid" | sed -E 's/.*\((Booted|Booting|Shutdown|Shutting Down)\).*/\1/')

# Desliga qualquer outro simulador ligado.
xcrun simctl list devices | grep -E "\((Booted|Booting)\)" | grep -v "$udid" \
  | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' | while read -r other; do
    echo "Desligando outro simulador: $other"
    xcrun simctl shutdown "$other" || true
  done

if [[ "$state" == "Booting" ]]; then
  echo "Simulador preso em Booting — reiniciando."
  xcrun simctl shutdown "$udid" || true
  state="Shutdown"
fi

if [[ "$state" != "Booted" ]]; then
  echo "Ligando $DEVICE_NAME ($udid)..."
  xcrun simctl boot "$udid"
fi

# Espera o boot completo (sem isso o flutter run fica tentando instalar e trava).
xcrun simctl bootstatus "$udid" -b >/dev/null

# Ajustes que aliviam a CPU/RAM do simulador.
xcrun simctl spawn "$udid" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true 2>/dev/null || true
xcrun simctl spawn "$udid" launchctl disable system/com.apple.photoanalysisd 2>/dev/null || true
xcrun simctl spawn "$udid" launchctl disable system/com.apple.mediaanalysisd 2>/dev/null || true

# O Xcode 27 não traz mais o Simulator.app (a tela do aparelho fica no próprio
# Xcode). Abre a janela só se o app existir — o flutter run não precisa dela.
open -a Simulator --args -CurrentDeviceUDID "$udid" 2>/dev/null || true

[[ "$BOOT_ONLY" == "--boot-only" ]] && exit 0

exec flutter run -d "$udid" --dart-define=API_URL="$API_URL"
