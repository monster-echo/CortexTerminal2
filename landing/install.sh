#!/bin/sh
set -e

# CortexTerminal Worker Installer
# Downloads and installs the latest worker binary for your platform.
#
# Usage: curl -fsSL https://monster-echo.github.io/CortexTerminal2/install.sh | sh
# With mirror: CORTEX_MIRROR=https://ghfast.top curl -fsSL ... | sh

REPO="monster-echo/CortexTerminal2"
BIN_NAME="cortexterminal-worker"
INSTALL_DIR="${CORTEX_TERMINAL_HOME:-$HOME/.cortexterminal}"
DEFAULT_GATEWAY_URL="https://gateway.ct.rwecho.top"
MIRROR="${CORTEX_MIRROR:-}"

# ---- Color output ----
if [ -t 1 ]; then
  BOLD="\033[1m"; GREEN="\033[32m"; CYAN="\033[36m"; RED="\033[31m"; YELLOW="\033[33m"; RESET="\033[0m"
else
  BOLD=""; GREEN=""; CYAN=""; RED=""; YELLOW=""; RESET=""
fi

info()     { printf "  ${CYAN}%s${RESET}\n" "$*"; }
ok()       { printf "  ${GREEN}✓${RESET} %s\n" "$*"; }
warn()     { printf "  ${YELLOW}!${RESET} %s\n" "$*"; }
fail()     { printf "  ${RED}✗${RESET} %s\n" "$*" >&2; exit 1; }

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

# ---- Build download URL ----
build_url() {
  ASSET_NAME="$1"
  GITHUB_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"

  if [ -n "$MIRROR" ]; then
    # User-provided mirror: replace github.com host
    echo "${GITHUB_URL}" | sed "s|https://github.com|${MIRROR}|"
  else
    echo "$GITHUB_URL"
  fi
}

# ---- Try download with fallback mirrors ----
try_download() {
  URL="$1"
  OUTPUT="$2"

  if command -v curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -fsSL --connect-timeout 10 --max-time 300 -w "%{http_code}" -o "$OUTPUT" "$URL" 2>/dev/null) || HTTP_CODE="000"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=10 -O "$OUTPUT" "$URL" && HTTP_CODE="200" || HTTP_CODE="000"
  else
    fail "Neither curl nor wget found. Install one to continue."
  fi

  echo "$HTTP_CODE"
}

# ---- Download latest release ----
download_worker() {
  RID=$1
  ARCHIVE_EXT=$2

  ASSET_NAME="cortexterminal-worker-${RID}.${ARCHIVE_EXT}"
  TMP_DIR=$(mktemp -d)
  TMP_FILE="${TMP_DIR}/${ASSET_NAME}"

  info "Detected platform: ${BOLD}${RID}${RESET}"

  # Build URL list: user mirror (or direct) -> fallback mirrors
  GITHUB_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
  MIRRORS="https://ghfast.top"

  if [ -n "$MIRROR" ]; then
    URLS="$(echo "$GITHUB_URL" | sed "s|https://github.com|${MIRROR}|")"
    URLS="$URLS $GITHUB_URL"
  else
    URLS="$GITHUB_URL"
    for M in $MIRRORS; do
      URLS="$URLS $(echo "$GITHUB_URL" | sed "s|https://github.com|${M}|")"
    done
  fi

  DOWNLOADED=false
  for URL in $URLS; do
    info "Trying ${URL} ..."
    HTTP_CODE=$(try_download "$URL" "$TMP_FILE")

    if [ "$HTTP_CODE" = "200" ]; then
      FILE_SIZE=$(wc -c < "$TMP_FILE" 2>/dev/null || echo 0)
      if [ "$FILE_SIZE" -gt 1000 ] 2>/dev/null; then
        DOWNLOADED=true
        ok "Downloaded successfully"
        break
      else
        warn "Downloaded file too small (${FILE_SIZE} bytes), trying next mirror..."
        rm -f "$TMP_FILE"
      fi
    else
      warn "Failed (HTTP ${HTTP_CODE}), trying next..."
    fi
  done

  if [ "$DOWNLOADED" != "true" ]; then
    rm -rf "$TMP_DIR"
    fail "All download attempts failed. Try setting a mirror: CORTEX_MIRROR=https://ghfast.top sh install.sh"
  fi

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

# ---- Main ----
printf "\n"
printf "  ${BOLD}CortexTerminal Worker Installer${RESET}\n"
printf "  %s\n\n" "──────────────────────────────────────────"
RID_AND_EXT=$(detect_platform)
download_worker ${RID_AND_EXT}
add_to_path

printf "\n"
printf "  ${GREEN}Done! Next steps:${RESET}\n"
printf "  %s\n" "  1. Run '${BIN_NAME} login' to authenticate this worker"
printf "  %s\n" "  2. Run '${BIN_NAME}' to start the worker"
printf "\n"
