#!/bin/sh
set -e

# Corterm Worker Installer
# Downloads and installs the latest worker binary for your platform.
#
# Usage: curl -fsSL https://gateway.ct.rwecho.top/install.sh | sh

REPO="monster-echo/CortexTerminal2"
BIN_NAME="corterm"
INSTALL_DIR="${CORTERM_HOME:-${CORTEX_TERMINAL_HOME:-$HOME/.corterm}}"
DEFAULT_GATEWAY_URL="https://gateway.ct.rwecho.top"
GITHUB_PROXY="https://proxy.0x2a.top"

# ---- Color output ----
if [ -t 1 ]; then
  BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"; RED="\033[31m"; RESET="\033[0m"
else
  BOLD=""; GREEN=""; CYAN=""; RED=""; RESET=""
fi

info()  { printf "  ${CYAN}%b${RESET}\n" "$*"; }
ok()    { printf "  ${GREEN}✓${RESET} %b\n" "$*"; }
fail()  { printf "  ${RED}✗${RESET} %b\n" "$*" >&2; exit 1; }

# ---- Detect platform ----
detect_platform() {
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case "$OS" in
    linux)  OS="linux" ;;
    darwin) OS="osx" ;;
    mingw*|msys*|cygwin*) OS="win" ;;
    *) fail "Unsupported OS: $OS" ;;
  esac

  case "$ARCH" in
    x86_64|amd64)  ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) fail "Unsupported architecture: $ARCH" ;;
  esac

  RID="${OS}-${ARCH}"
  ARCHIVE_EXT="tar.gz"
  [ "$OS" = "win" ] && ARCHIVE_EXT="zip"

  echo "$RID" "$ARCHIVE_EXT"
}

# ---- Download latest release ----
download_worker() {
  RID=$1
  ARCHIVE_EXT=$2

  ASSET_NAME="corterm-${RID}.${ARCHIVE_EXT}"
  GITHUB_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
  TMP_DIR=$(mktemp -d)
  TMP_FILE="${TMP_DIR}/${ASSET_NAME}"

  info "Detected platform: ${BOLD}${RID}${RESET}"
  info "Downloading ${ASSET_NAME} ..."

  DOWNLOAD_URL="${GITHUB_PROXY}/${GITHUB_URL}"

  if command -v curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -fsSL --connect-timeout 15 -w "%{http_code}" -o "$TMP_FILE" "$DOWNLOAD_URL")
  elif command -v wget >/dev/null 2>&1; then
    wget -T 15 -q -O "$TMP_FILE" "$DOWNLOAD_URL" && HTTP_CODE="200" || HTTP_CODE="000"
  else
    fail "Neither curl nor wget found. Install one to continue."
  fi

  if [ "$HTTP_CODE" != "200" ]; then
    rm -rf "$TMP_DIR"
    fail "Failed to download worker binary (HTTP ${HTTP_CODE}). Check: ${DOWNLOAD_URL}"
  fi

  ok "Downloaded successfully"

  # Extract
  info "Extracting to ${INSTALL_DIR} ..."
  mkdir -p "$INSTALL_DIR"

  if [ "$ARCHIVE_EXT" = "zip" ]; then
    if ! command -v unzip >/dev/null 2>&1; then
      fail "unzip not found. Install it to extract the Windows worker."
    fi
    unzip -o "$TMP_FILE" -d "$INSTALL_DIR" >/dev/null
  else
    tar -xzf "$TMP_FILE" -C "$INSTALL_DIR"
  fi

  chmod +x "$INSTALL_DIR/$BIN_NAME" 2>/dev/null || true
  [ -f "$INSTALL_DIR/${BIN_NAME}.exe" ] && chmod +x "$INSTALL_DIR/${BIN_NAME}.exe" 2>/dev/null || true

  rm -rf "$TMP_DIR"
  ok "Installed to ${BOLD}${INSTALL_DIR}${RESET}"
}

# ---- PATH check ----
add_to_path() {
  case "$(basename "$SHELL" 2>/dev/null)" in
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    fish) RC_FILE="$HOME/.config/fish/config.fish" ;;
    *)    RC_FILE="$HOME/.profile" ;;
  esac

  if ! echo "$PATH" | tr ':' '\n' | grep -qxF "$INSTALL_DIR"; then
    info "Adding ${INSTALL_DIR} to PATH in ${RC_FILE} ..."
    printf '\n# Corterm Worker\nexport PATH="$PATH:%s"\n' "$INSTALL_DIR" >> "$RC_FILE"
    ok "Added to PATH. Restart your shell or run: source ${RC_FILE}"
  else
    info "${INSTALL_DIR} is already in PATH."
  fi
}

# ---- Install as service ----
install_service() {
  PLATFORM_OS=$(echo "$RID_AND_EXT" | cut -d' ' -f1 | cut -d'-' -f1)

  if [ "$PLATFORM_OS" = "linux" ] && command -v systemctl >/dev/null 2>&1; then
    SERVICE_TEMPLATE="${INSTALL_DIR}/corterm-worker.service"
    [ ! -f "$SERVICE_TEMPLATE" ] && return 0

    info "Installing systemd user service ..."
    SERVICE_FILE=$(mktemp)
    sed -e "s|{{INSTALL_DIR}}|${INSTALL_DIR}|g" -e "s|{{HOME}}|${HOME}|g" \
      "$SERVICE_TEMPLATE" > "$SERVICE_FILE"

    USER_UNIT_DIR="$HOME/.config/systemd/user"
    mkdir -p "$USER_UNIT_DIR"
    cp "$SERVICE_FILE" "$USER_UNIT_DIR/corterm-worker.service"
    systemctl --user daemon-reload
    systemctl --user enable corterm-worker
    loginctl enable-linger "$(whoami)" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    ok "systemd user service installed. Run: systemctl --user start corterm-worker"

  elif [ "$PLATFORM_OS" = "osx" ]; then
    PLIST_TEMPLATE="${INSTALL_DIR}/com.corterm.worker.plist"
    [ ! -f "$PLIST_TEMPLATE" ] && return 0

    info "Installing LaunchAgent ..."
    PLIST_DIR="$HOME/Library/LaunchAgents"
    mkdir -p "$PLIST_DIR"
    PLIST_FILE=$(mktemp)
    sed -e "s|{{INSTALL_DIR}}|${INSTALL_DIR}|g" -e "s|{{HOME}}|${HOME}|g" \
      "$PLIST_TEMPLATE" > "$PLIST_FILE"
    cp "$PLIST_FILE" "$PLIST_DIR/com.corterm.worker.plist"
    rm -f "$PLIST_FILE"
    launchctl load "$PLIST_DIR/com.corterm.worker.plist" 2>/dev/null || true
    ok "LaunchAgent installed and loaded (auto-start on login)"
  fi
}

# ---- Start/restart service if already authenticated ----
start_if_authenticated() {
  [ ! -f "${INSTALL_DIR}/.auth" ] && return 1

  PLATFORM_OS=$(echo "$RID_AND_EXT" | cut -d' ' -f1 | cut -d'-' -f1)

  if [ "$PLATFORM_OS" = "linux" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user restart corterm-worker 2>/dev/null && ok "Worker service restarted" && return 0
  elif [ "$PLATFORM_OS" = "osx" ]; then
    PLIST_DIR="$HOME/Library/LaunchAgents"
    launchctl unload "$PLIST_DIR/com.corterm.worker.plist" 2>/dev/null || true
    launchctl load "$PLIST_DIR/com.corterm.worker.plist" 2>/dev/null && ok "Worker service restarted" && return 0
  fi

  return 1
}

# ---- Main ----
printf "\n"
printf "  ${BOLD}Corterm Worker Installer${RESET}\n"
printf "  %s\n\n" "──────────────────────────────────────────"
RID_AND_EXT=$(detect_platform)
download_worker ${RID_AND_EXT}
install_service
add_to_path

printf "\n"
if start_if_authenticated; then
  printf "  ${GREEN}Updated and running!${RESET}\n"
else
  printf "  ${CYAN}Worker not yet authenticated.${RESET}\n"
  printf "  Running '${BIN_NAME} login' ...\n\n"
  "$INSTALL_DIR/$BIN_NAME" login
  start_if_authenticated
fi
printf "\n"
