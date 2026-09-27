#!/usr/bin/env bash
# Configura l'ambiente di sviluppo (Linux) per usare clangd con Unreal Engine.
#
# Prima di lanciarlo: apri il .uproject nell'Editor e fai
# Tools > Refresh Visual Studio Code Project (genera .vscode/ e compileCommands).
#
# Uso: ./Tools/install.sh
set -euo pipefail

CLANGD_VERSION="23.1.0"
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TOOLS_DIR")"
OPT_DIR="$HOME/.local/opt"
BIN_DIR="$HOME/.local/bin"
CLANGD_BIN="$OPT_DIR/clangd_${CLANGD_VERSION}/bin/clangd"
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"

mkdir -p "$OPT_DIR" "$BIN_DIR" "$HOME/.config/clangd"

# 1. clangd
if [[ ! -x "$CLANGD_BIN" ]]; then
	echo ">> Scarico clangd $CLANGD_VERSION"
	tmp="$(mktemp -d)"
	curl -fsSL -o "$tmp/clangd.zip" \
		"https://github.com/clangd/clangd/releases/download/${CLANGD_VERSION}/clangd-linux-${CLANGD_VERSION}.zip"
	unzip -q -o "$tmp/clangd.zip" -d "$OPT_DIR"
	rm -rf "$tmp"
fi
ln -sf "$CLANGD_BIN" "$BIN_DIR/clangd"
echo ">> $("$BIN_DIR/clangd" --version | head -1)"

# 2. estensione VS Code
if command -v code >/dev/null; then
	code --install-extension llvm-vs-code-extensions.vscode-clangd >/dev/null
	echo ">> Estensione vscode-clangd installata"
else
	echo "!! 'code' non trovato: installa a mano l'estensione llvm-vs-code-extensions.vscode-clangd"
fi

# 3. config globale clangd
dest="$HOME/.config/clangd/config.yaml"
if [[ -f "$dest" ]] && ! cmp -s "$TOOLS_DIR/clangd-config.yaml" "$dest"; then
	cp "$dest" "$dest.bak"
	echo ">> Backup della config clangd esistente in $dest.bak"
fi
cp "$TOOLS_DIR/clangd-config.yaml" "$dest"
echo ">> Config clangd installata in $dest"

# 4. impostazioni utente VS Code (clangd spento di default, acceso per progetto)
mkdir -p "$(dirname "$VSCODE_SETTINGS")"
[[ -f "$VSCODE_SETTINGS" ]] || echo "{}" > "$VSCODE_SETTINGS"
if grep -q '"clangd.path"' "$VSCODE_SETTINGS"; then
	echo ">> Impostazioni clangd gia' presenti in $VSCODE_SETTINGS"
else
	cp "$VSCODE_SETTINGS" "$VSCODE_SETTINGS.bak"
	python3 - "$VSCODE_SETTINGS" "$BIN_DIR/clangd" <<'EOF'
import re, sys
path, clangd = sys.argv[1], sys.argv[2]
text = open(path).read()
block = f'''// clangd: attivo solo nei progetti Unreal (via ue-clangd-setup), altrove resta cpptools
"clangd.enable": false,
"clangd.path": "{clangd}",
"clangd.arguments": [
	"--background-index",
	"-j=4",
	"--pch-storage=disk",
	"--malloc-trim",
	"--header-insertion=never",
	"--completion-style=detailed",
	"--limit-results=500"
],
'''
end = text.rstrip().rfind("}")
head = text[:end].rstrip()
# il file e' JSONC: aggiungi una virgola se l'ultima voce non ce l'ha
if not head.endswith(("{", ",")):
    head += ","
open(path, "w").write(head + "\n" + block + "}\n")
EOF
	echo ">> Impostazioni clangd aggiunte a $VSCODE_SETTINGS (backup in .bak)"
fi

# 5. script di setup per i progetti Unreal
install -m 755 "$TOOLS_DIR/ue-clangd-setup" "$BIN_DIR/ue-clangd-setup"
echo ">> ue-clangd-setup installato in $BIN_DIR"
case ":$PATH:" in
	*":$BIN_DIR:"*) ;;
	*) echo "!! $BIN_DIR non e' nel PATH: aggiungilo al tuo ~/.bashrc" ;;
esac

# 6. configura questo progetto
"$BIN_DIR/ue-clangd-setup" "$PROJECT_DIR" \
	|| echo "!! Setup del progetto saltato: genera i project file e rilancia 'ue-clangd-setup'"

# 7. controllo swap
swap_kb="$(awk '/SwapTotal/ {print $2}' /proc/meminfo)"
if (( swap_kb < 8 * 1024 * 1024 )); then
	echo
	echo "!! Swap attuale: $((swap_kb / 1024)) MB. Per UE conviene portarlo a 16 GB:"
	echo "   sudo swapoff /swapfile && sudo fallocate -l 16G /swapfile && sudo chmod 600 /swapfile"
	echo "   sudo mkswap /swapfile && sudo swapon /swapfile"
	echo "   (se /swapfile e' nuovo aggiungi a /etc/fstab: /swapfile none swap sw 0 0)"
fi

echo
echo "Fatto. In VS Code: Ctrl+Shift+P > Developer: Reload Window"
