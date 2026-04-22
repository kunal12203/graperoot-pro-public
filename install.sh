#!/usr/bin/env bash
# GrapeRoot Pro — one-time setup (macOS / Linux)
# Usage:  curl -fsSL https://graperoot.dev/pro/install.sh | bash -s -- GRP-XXXX-XXXX-XXXX

set -euo pipefail

INSTALL_DIR="$HOME/.graperoot-pro"
VENV="$INSTALL_DIR/venv"
FREE_DIR="$HOME/.dual-graph"
R2="${GRAPEROOT_PRO_R2:-https://pub-pro-r2.graperoot.dev}"
API="${GRAPEROOT_PRO_API:-https://api.graperoot.dev}"
BASE_URL="${GRAPEROOT_PRO_GH:-https://raw.githubusercontent.com/kunal12203/graperoot-pro-public/main}"

LICENSE_KEY="${1:-${GRAPEROOT_LICENSE_KEY:-}}"

# ══════════════════════════════════════════════════════════════════════════════
# BRANDING
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           GrapeRoot Pro — Installer  ·  v1.0                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [[ -z "$LICENSE_KEY" ]]; then
  echo "[error] License key required."
  echo ""
  echo "  Usage:  curl -fsSL https://graperoot.dev/pro/install.sh | bash -s -- GRP-XXXX-XXXX-XXXX"
  echo ""
  echo "  No license? Purchase at https://graperoot.dev/pro or email sales@graperoot.dev"
  exit 1
fi

confirm() {
  # Three modes:
  #   1. Interactive TTY → prompt Y/n, read user answer
  #   2. No TTY (CI, curl|bash piped, SSH -T) → default YES (user invoked the installer)
  #   3. Opt-out via env: GRAPEROOT_SKIP_OPTIONAL=1 → default NO
  local answer=""
  if [ -r /dev/tty ] 2>/dev/null; then
    printf "%s [Y/n] " "$1"
    read -r answer </dev/tty || answer=""
  else
    if [ "${GRAPEROOT_SKIP_OPTIONAL:-0}" = "1" ]; then
      echo "$1 [skipped — GRAPEROOT_SKIP_OPTIONAL=1]"
      return 1
    fi
    echo "$1 [Y/n] (auto-Y, no tty)"
    answer="Y"
  fi
  case "$answer" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

# ══════════════════════════════════════════════════════════════════════════════
# PREREQUISITES — match free installer's approach (Python 3.10+, Node, Claude)
# ══════════════════════════════════════════════════════════════════════════════
OS_TYPE="$(uname -s)"
PYTHON=""
for py in python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$py" >/dev/null 2>&1; then
    if "$py" -c "import sys; exit(0 if sys.version_info >= (3,10) else 1)" 2>/dev/null; then
      PYTHON="$py"; break
    fi
  fi
done

if [[ -z "$PYTHON" ]]; then
  echo "[check] Python 3.10+ is NOT installed."
  case "$OS_TYPE" in
    Darwin*)
      if command -v brew >/dev/null 2>&1 && confirm "[check] Install Python 3.11 via Homebrew?"; then
        brew install python@3.11 && PYTHON="python3.11"
      else
        echo "  Install manually:  brew install python@3.11   (or download from https://python.org)"
        exit 1
      fi
      ;;
    Linux*)
      if command -v apt-get >/dev/null 2>&1 && confirm "[check] Install Python via apt? (sudo)"; then
        sudo apt-get update && sudo apt-get install -y python3.11 python3.11-venv && PYTHON="python3.11"
      elif command -v dnf >/dev/null 2>&1 && confirm "[check] Install Python via dnf? (sudo)"; then
        sudo dnf install -y python3.11 && PYTHON="python3.11"
      else
        echo "  Install Python 3.10+ manually, then re-run the installer."
        exit 1
      fi
      ;;
    *)
      echo "  Unsupported OS: $OS_TYPE"
      exit 1
      ;;
  esac
fi
echo "[check] Python:       $($PYTHON --version)"

if ! command -v rg >/dev/null 2>&1; then
  echo "[check] ripgrep:      NOT FOUND"
  case "$OS_TYPE" in
    Darwin*)
      if command -v brew >/dev/null 2>&1 && confirm "[check] Install ripgrep via Homebrew?"; then
        brew install ripgrep
      else
        echo "[warn] Install later:  brew install ripgrep   (needed for fallback_rg / graph_grep_all)"
      fi
      ;;
    Linux*)
      if command -v apt-get >/dev/null 2>&1 && confirm "[check] Install ripgrep via apt? (sudo)"; then
        sudo apt-get install -y ripgrep
      elif command -v dnf >/dev/null 2>&1 && confirm "[check] Install ripgrep via dnf? (sudo)"; then
        sudo dnf install -y ripgrep
      elif command -v pacman >/dev/null 2>&1 && confirm "[check] Install ripgrep via pacman? (sudo)"; then
        sudo pacman -S --noconfirm ripgrep
      else
        echo "[warn] Install ripgrep from your package manager (needed for fallback_rg / graph_grep_all)"
      fi
      ;;
  esac
else
  echo "[check] ripgrep:      $(rg --version 2>/dev/null | head -1)"
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "[check] Claude Code:  NOT FOUND"
  if command -v npm >/dev/null 2>&1 && confirm "[check] Install Claude Code via npm?"; then
    npm install -g @anthropic-ai/claude-code 2>/dev/null || sudo npm install -g @anthropic-ai/claude-code 2>/dev/null || true
    command -v claude >/dev/null 2>&1 && echo "[check] Claude Code:  installed" || echo "[warn] Claude Code install failed; install manually later: npm i -g @anthropic-ai/claude-code"
  else
    echo "[warn] Install later:  npm install -g @anthropic-ai/claude-code"
  fi
else
  echo "[check] Claude Code:  $(claude --version 2>/dev/null | head -1 || echo 'installed')"
fi

# ══════════════════════════════════════════════════════════════════════════════
# COEXISTENCE — detect free install, install Pro alongside (never touch it)
# ══════════════════════════════════════════════════════════════════════════════
if [[ -d "$FREE_DIR" ]]; then
  echo "[check] GrapeRoot Free detected at $FREE_DIR — Pro will install alongside (free install untouched)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# LICENSE VERIFY — fail fast if key is bad, before downloading anything
# ══════════════════════════════════════════════════════════════════════════════
echo "[verify] Validating license…"
VERIFY_JSON=$(
  curl -fsSL -X POST "$API/v1/license/verify" \
    -H "Content-Type: application/json" \
    -d "{\"license_key\":\"$LICENSE_KEY\",\"host\":\"$(hostname 2>/dev/null || echo unknown)\",\"os\":\"$OS_TYPE\"}" \
    --max-time 15 2>/dev/null
) || { echo "[error] License server unreachable. Check internet, then retry. Support: support@graperoot.dev"; exit 1; }

_is_valid=$("$PYTHON" -c "import json,sys;print('1' if json.loads('''$VERIFY_JSON''').get('valid') else '0')" 2>/dev/null || echo 0)
if [[ "$_is_valid" != "1" ]]; then
  REASON=$("$PYTHON" -c "import json;print(json.loads('''$VERIFY_JSON''').get('reason','invalid'))" 2>/dev/null || echo invalid)
  echo "[error] License rejected: $REASON"
  echo "        Support: support@graperoot.dev"
  exit 1
fi
CUSTOMER=$("$PYTHON" -c "import json;print(json.loads('''$VERIFY_JSON''').get('customer','—'))" 2>/dev/null)
EXPIRES=$("$PYTHON"  -c "import json;print(json.loads('''$VERIFY_JSON''').get('expires','perpetual'))" 2>/dev/null)
DL_URL=$("$PYTHON"   -c "import json;print(json.loads('''$VERIFY_JSON''')['download_url'])" 2>/dev/null)
echo "[verify] Valid  ·  $CUSTOMER  ·  expires: $EXPIRES"

# ══════════════════════════════════════════════════════════════════════════════
# INSTALL
# ══════════════════════════════════════════════════════════════════════════════
mkdir -p "$INSTALL_DIR/bin"

# Download bundled package (server, graph_builder, requirements, VERSION)
echo "[install] Downloading GrapeRoot Pro package…"
TMP_TGZ="$(mktemp -t graperoot-pro.XXXXXX.tgz)"
trap 'rm -f "$TMP_TGZ"' EXIT
curl -fsSL "$DL_URL" -o "$TMP_TGZ" --max-time 120
tar -xzf "$TMP_TGZ" -C "$INSTALL_DIR" --strip-components=1
chmod 700 "$INSTALL_DIR"

# Download launcher + shim from R2 (with GitHub fallback)
echo "[install] Downloading launcher…"
for f in launch_pro.sh dgc-pro version.txt changelog.txt; do
  curl -fsSL "$R2/bin/$f" -o "$INSTALL_DIR/bin/$f" 2>/dev/null \
    || curl -fsSL "$BASE_URL/bin/$f" -o "$INSTALL_DIR/bin/$f"
done
chmod +x "$INSTALL_DIR/bin/launch_pro.sh" "$INSTALL_DIR/bin/dgc-pro"

# Python venv + dependencies
echo "[install] Creating isolated Python venv…"
"$PYTHON" -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip --quiet
"$VENV/bin/pip" install --quiet -r "$INSTALL_DIR/requirements.txt"

# Persist license (owner-only)
echo -n "$LICENSE_KEY" > "$INSTALL_DIR/license.key"
chmod 600 "$INSTALL_DIR/license.key"

# PATH — match free's shell-rc logic (zsh/bash, linux/mac)
SHELL_RC="$HOME/.zshrc"
if [[ "${SHELL:-}" == */bash ]]; then
  [[ "$OS_TYPE" == "Darwin" ]] && SHELL_RC="$HOME/.bash_profile" || SHELL_RC="$HOME/.bashrc"
fi
if ! grep -q ".graperoot-pro/bin" "$SHELL_RC" 2>/dev/null; then
  {
    echo ""
    echo "# GrapeRoot Pro"
    echo "export PATH=\"\$PATH:\$HOME/.graperoot-pro/bin\""
  } >> "$SHELL_RC"
  echo "[install] Added $INSTALL_DIR/bin to PATH in $SHELL_RC"
fi

VER=$(cat "$INSTALL_DIR/bin/version.txt" 2>/dev/null || echo "1.0.5")
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Install complete.  GrapeRoot Pro v$VER                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Run once:       source $SHELL_RC"
echo "  Then per project:"
echo "    dgc-pro /path/to/your/project"
echo ""
echo "  Docs:    https://graperoot.dev/pro/docs"
echo "  Support: support@graperoot.dev"
echo ""
