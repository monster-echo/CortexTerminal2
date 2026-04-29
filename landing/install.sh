#!/bin/sh
set -e

# CortexTerminal Worker Installer
# Downloads and installs the latest worker binary for your platform.
#
# Usage: curl -fsSL https://monster-echo.github.io/CortexTerminal2/install.sh | sh

REPO="monster-echo/CortexTerminal2"
BIN_NAME="cortex"
INSTALL_DIR="${CORTEX_TERMINAL_HOME:-$HOME/.cortexterminal}"
DEFAULT_GATEWAY_URL="https://gateway.ct.rwecho.top"

# ---- Color output ----
if [ -t 1 ]; then
  BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"; RED="\033[31m"; RESET="\033[0m"
else
  BOLD=""; GREEN=""; CYAN=""; RED=""; RESET=""
fi

info()  { printf "  ${CYAN}%s${RESET}\n" "$*"; }
ok()    { printf "  ${GREEN}✓${RESET} %s\n" "$*"; }
fail()  { printf "  ${RED}✗${RESET} %s\n" "$*" >&2; exit 1; }

# ---- Detect platform ----
detect_platform() {
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case "$OS" in
    linux)  OS="linux" ;;
    darwin) OS="osx" ;;
    mingw*|msys*|cygwin*) OS="windows" ;;
    *) fail "Unsupported OS: $OS" ;;
  esac

  case "$ARCH" in
    x86_64|amd64)  ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) fail "Unsupported architecture: $ARCH" ;;
  esac

  RID="${OS}-${ARCH}"
  ARCHIVE_EXT="tar.gz"
  [ "$OS" = "windows" ] && ARCHIVE_EXT="zip"

  echo "$RID" "$ARCHIVE_EXT"
}

# ---- Download latest release ----
download_worker() {
  RID=$1
  ARCHIVE_EXT=$2

  ASSET_NAME="cortex-${RID}.${ARCHIVE_EXT}"
  DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
  TMP_DIR=$(mktemp -d)
  TMP_FILE="${TMP_DIR}/${ASSET_NAME}"

  info "Detected platform: ${BOLD}${RID}${RESET}"
  info "Downloading ${ASSET_NAME} ..."

  if command -v curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -fsSL -w "%{http_code}" -o "$TMP_FILE" "$DOWNLOAD_URL")
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$TMP_FILE" "$DOWNLOAD_URL" && HTTP_CODE="200" || HTTP_CODE="404"
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
    printf '\n# CortexTerminal Worker\nexport PATH="$PATH:%s"\n' "$INSTALL_DIR" >> "$RC_FILE"
    ok "Added to PATH. Restart your shell or run: source ${RC_FILE}"
  else
    info "${INSTALL_DIR} is already in PATH."
  fi
}

# ---- Install as service ----
install_service() {
  PLATFORM_OS=$(echo "$RID_AND_EXT" | cut -d' ' -f1 | cut -d'-' -f1)

  if [ "$PLATFORM_OS" = "linux" ] && command -v systemctl >/dev/null 2>&1; then
    SERVICE_TEMPLATE="${INSTALL_DIR}/cortexterm-worker.service"
    [ ! -f "$SERVICE_TEMPLATE" ] && return 0

    info "Installing systemd user service ..."
    SERVICE_FILE=$(mktemp)
    sed -e "s|{{INSTALL_DIR}}|${INSTALL_DIR}|g" -e "s|{{HOME}}|${HOME}|g" \
      "$SERVICE_TEMPLATE" > "$SERVICE_FILE"

    USER_UNIT_DIR="$HOME/.config/systemd/user"
    mkdir -p "$USER_UNIT_DIR"
    cp "$SERVICE_FILE" "$USER_UNIT_DIR/cortexterm-worker.service"
    systemctl --user daemon-reload
    systemctl --user enable cortexterm-worker
    loginctl enable-linger "$(whoami)" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    ok "systemd user service installed. Run: systemctl --user start cortexterm-worker"

  elif [ "$PLATFORM_OS" = "osx" ]; then
    PLIST_TEMPLATE="${INSTALL_DIR}/com.cortexterm.worker.plist"
    [ ! -f "$PLIST_TEMPLATE" ] && return 0

    info "Installing LaunchAgent ..."
    PLIST_DIR="$HOME/Library/LaunchAgents"
    mkdir -p "$PLIST_DIR"
    PLIST_FILE=$(mktemp)
    sed -e "s|{{INSTALL_DIR}}|${INSTALL_DIR}|g" -e "s|{{HOME}}|${HOME}|g" \
      "$PLIST_TEMPLATE" > "$PLIST_FILE"
    cp "$PLIST_FILE" "$PLIST_DIR/com.cortexterm.worker.plist"
    rm -f "$PLIST_FILE"
    launchctl load "$PLIST_DIR/com.cortexterm.worker.plist" 2>/dev/null || true
    ok "LaunchAgent installed and loaded (auto-start on login)"
  fi
}

# ---- Main ----
printf "\n"
printf "  ${BOLD}CortexTerminal Worker Installer${RESET}\n"
printf "  %s\n\n" "──────────────────────────────────────────"
RID_AND_EXT=$(detect_platform)
download_worker ${RID_AND_EXT}
install_service
add_to_path

printf "\n"
printf "  ${GREEN}Done! Next steps:${RESET}\n"
printf "  %s\n" "  1. Run '${BIN_NAME} login' to authenticate this worker"
printf "  %s\n" "  2. Run '${BIN_NAME}' to start the worker"
printf "\n"
