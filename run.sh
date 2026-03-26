#!/usr/bin/env bash
# run.sh — Development and build script for FlyFishingGame
# Requires: curl, unzip (for setup), Podman (for export)

set -euo pipefail

GODOT_VERSION="4.3"
GODOT_SQLITE_VERSION="4.3"    # Update when upgrading the plugin (must be compatible with GODOT_VERSION)
EXPORT_IMAGE="barichello/godot-ci:${GODOT_VERSION}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/builds"
PLUGIN_DIR="${PROJECT_DIR}/addons/godot-sqlite"
PLUGIN_BASE="https://github.com/2shady4u/godot-sqlite/releases/download/v${GODOT_SQLITE_VERSION}"
# bin.zip = native libraries; demo.zip = plugin.cfg + gdsqlite.gdextension + godot-sqlite.gd
PLUGIN_BIN_URL="${PLUGIN_BASE}/bin.zip"
PLUGIN_DEMO_URL="${PLUGIN_BASE}/demo.zip"
# Godot download base — binary name varies by platform (resolved at runtime)
GODOT_RELEASE_BASE="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
GODOT_INSTALL_DIR="${HOME}/.local/bin"

# --- Colour output ---
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[run]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
error() { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# --- Detect Godot binary ---
_godot_bin() {
    for candidate in godot4 godot Godot godot-4; do
        if command -v "$candidate" &>/dev/null; then
            echo "$candidate"
            return
        fi
    done
    error "Godot binary not found. Run: ./run.sh setup"
}

_godot_installed() {
    for candidate in godot4 godot Godot godot-4; do
        command -v "$candidate" &>/dev/null && return 0
    done
    return 1
}

# --- Commands ---

cmd_setup() {
    local force="${1:-}"
    command -v curl  &>/dev/null || error "curl is required for setup."
    command -v unzip &>/dev/null || error "unzip is required for setup."

    _install_godot   "$force"
    _install_plugin  "$force"
}

# ---------------------------------------------------------------------------
# Godot installation
# ---------------------------------------------------------------------------

_install_godot() {
    local force="${1:-}"

    if _godot_installed && [[ "$force" != "--force" ]]; then
        local bin; bin="$(_godot_bin)"
        info "Godot already on PATH: $(command -v "$bin")"
        return 0
    fi

    local os; os="$(uname -s)"
    case "$os" in
        Linux)  _install_godot_linux  ;;
        Darwin) _install_godot_macos  ;;
        *)
            warn "Unsupported OS '${os}' — install Godot ${GODOT_VERSION} manually."
            warn "Download: https://godotengine.org/download/"
            ;;
    esac
}

_install_godot_linux() {
    local arch; arch="$(uname -m)"
    # Godot only ships x86_64 and arm64 binaries
    case "$arch" in
        x86_64)         local suffix="linux.x86_64"  ;;
        aarch64|arm64)  local suffix="linux.arm64"   ;;
        *)  error "Unsupported architecture '${arch}' for automatic Godot install." ;;
    esac

    local bin_name="Godot_v${GODOT_VERSION}-stable_${suffix}"
    local zip_name="${bin_name}.zip"
    local url="${GODOT_RELEASE_BASE}/${zip_name}"
    local install_path="${GODOT_INSTALL_DIR}/godot4"

    info "Installing Godot ${GODOT_VERSION} (${suffix})..."
    local tmp; tmp="$(mktemp -d)"

    curl -fsSL --progress-bar -o "${tmp}/${zip_name}" "${url}" \
        || { rm -rf "$tmp"; error "Failed to download Godot ${GODOT_VERSION}."; }

    unzip -q "${tmp}/${zip_name}" -d "${tmp}/out"

    mkdir -p "$GODOT_INSTALL_DIR"
    cp "${tmp}/out/${bin_name}" "$install_path"
    chmod +x "$install_path"
    rm -rf "$tmp"

    info "Godot installed → ${install_path}"
    _warn_path "$GODOT_INSTALL_DIR"
}

_install_godot_macos() {
    local app_dir="${HOME}/Applications"
    local zip_name="Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
    local url="${GODOT_RELEASE_BASE}/${zip_name}"
    local symlink="${GODOT_INSTALL_DIR}/godot4"

    info "Installing Godot ${GODOT_VERSION} (macOS universal)..."
    local tmp; tmp="$(mktemp -d)"

    curl -fsSL --progress-bar -o "${tmp}/${zip_name}" "${url}" \
        || { rm -rf "$tmp"; error "Failed to download Godot ${GODOT_VERSION}."; }

    unzip -q "${tmp}/${zip_name}" -d "${tmp}/out"

    mkdir -p "$app_dir" "$GODOT_INSTALL_DIR"
    rm -rf "${app_dir}/Godot.app"
    cp -r "${tmp}/out/Godot.app" "${app_dir}/"
    ln -sf "${app_dir}/Godot.app/Contents/MacOS/Godot" "$symlink"
    rm -rf "$tmp"

    info "Godot installed → ${app_dir}/Godot.app"
    info "Symlink → ${symlink}"
    _warn_path "$GODOT_INSTALL_DIR"
}

_warn_path() {
    local dir="$1"
    if [[ ":${PATH}:" != *":${dir}:"* ]]; then
        warn "${dir} is not in your PATH."
        warn "Add to your shell profile:  export PATH=\"${dir}:\${PATH}\""
    fi
}

# ---------------------------------------------------------------------------
# godot-sqlite plugin installation
# ---------------------------------------------------------------------------

_install_plugin() {
    local force="${1:-}"
    info "Setting up godot-sqlite plugin v${GODOT_SQLITE_VERSION}..."

    if [[ -f "${PLUGIN_DIR}/gdsqlite.gdextension" ]]; then
        info "Plugin already installed at ${PLUGIN_DIR}."
        [[ "$force" == "--force" ]] || return 0
    fi

    local tmp; tmp="$(mktemp -d)"

    # bin.zip = native libraries (flat layout, no addons/ prefix)
    info "Downloading binaries..."
    curl -fsSL --progress-bar -o "${tmp}/bin.zip" "${PLUGIN_BIN_URL}" \
        || { rm -rf "$tmp"; error "Failed to download plugin binaries. Check GODOT_SQLITE_VERSION in run.sh."; }

    # demo.zip = plugin.cfg + gdsqlite.gdextension + godot-sqlite.gd (under demo/addons/godot-sqlite/)
    info "Downloading plugin config..."
    curl -fsSL --progress-bar -o "${tmp}/demo.zip" "${PLUGIN_DEMO_URL}" \
        || { rm -rf "$tmp"; error "Failed to download plugin demo archive. Check GODOT_SQLITE_VERSION in run.sh."; }

    # Extract binaries
    unzip -q "${tmp}/bin.zip" -d "${tmp}/bin_extracted"

    # Extract config files
    unzip -j "${tmp}/demo.zip" \
        "demo/addons/godot-sqlite/plugin.cfg" \
        "demo/addons/godot-sqlite/gdsqlite.gdextension" \
        "demo/addons/godot-sqlite/godot-sqlite.gd" \
        -d "${tmp}/cfg" 2>/dev/null \
        || { rm -rf "$tmp"; error "Failed to extract plugin config files. The demo.zip layout may have changed."; }

    # Install: binaries first (detect flat vs nested layout), then config files
    rm -rf "$PLUGIN_DIR"
    mkdir -p "$PLUGIN_DIR"

    local bin_src
    if [[ -d "${tmp}/bin_extracted/addons/godot-sqlite" ]]; then
        bin_src="${tmp}/bin_extracted/addons/godot-sqlite"
    else
        bin_src="${tmp}/bin_extracted"
    fi
    cp -r "${bin_src}/." "$PLUGIN_DIR/"
    cp "${tmp}/cfg/plugin.cfg"            "$PLUGIN_DIR/"
    cp "${tmp}/cfg/gdsqlite.gdextension"  "$PLUGIN_DIR/"
    cp "${tmp}/cfg/godot-sqlite.gd"       "$PLUGIN_DIR/"

    rm -rf "$tmp"

    info "Plugin installed → ${PLUGIN_DIR}"
    info "Enable in Godot: Project → Project Settings → Plugins → Godot SQLite → Enable"
}

# ---------------------------------------------------------------------------
# Run / Editor / Export
# ---------------------------------------------------------------------------

cmd_run() {
    _check_plugin
    local godot; godot="$(_godot_bin)"
    info "Running game with ${godot}..."
    "$godot" --path "$PROJECT_DIR" "$@"
}

cmd_editor() {
    _check_plugin
    local godot; godot="$(_godot_bin)"
    info "Opening editor with ${godot}..."
    "$godot" --path "$PROJECT_DIR" --editor "$@"
}

cmd_export() {
    local platform="${1:-all}"
    _check_plugin
    _check_export_presets
    _require_podman

    mkdir -p "$BUILD_DIR"

    case "$platform" in
        linux)
            _export_platform "Linux/X11" "${BUILD_DIR}/flyfishinggame-linux.x86_64"
            ;;
        windows)
            _export_platform "Windows Desktop" "${BUILD_DIR}/flyfishinggame-windows.exe"
            ;;
        all)
            _export_platform "Linux/X11"       "${BUILD_DIR}/flyfishinggame-linux.x86_64"
            _export_platform "Windows Desktop" "${BUILD_DIR}/flyfishinggame-windows.exe"
            ;;
        *)
            error "Unknown platform '${platform}'. Use: linux | windows | all"
            ;;
    esac

    info "Build output in ${BUILD_DIR}/"
}

_export_platform() {
    local preset="$1"
    local output="$2"
    info "Exporting '${preset}' → ${output}..."
    podman run --rm \
        -v "${PROJECT_DIR}":/project:ro \
        -v "${BUILD_DIR}":/builds \
        "$EXPORT_IMAGE" \
        bash -c "cd /project && godot --headless --export-release '${preset}' '${output}'"
}

cmd_shell() {
    _require_podman
    info "Opening shell in export container (${EXPORT_IMAGE})..."
    podman run --rm -it \
        -v "${PROJECT_DIR}":/project \
        -v "${BUILD_DIR}":/builds \
        "$EXPORT_IMAGE" \
        bash
}

cmd_clean() {
    info "Removing ${BUILD_DIR}..."
    rm -rf "$BUILD_DIR"
    info "Done."
}

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

_check_plugin() {
    if [[ ! -f "${PLUGIN_DIR}/gdsqlite.gdextension" ]]; then
        warn "godot-sqlite plugin not found. Run: ./run.sh setup"
    fi
}

_check_export_presets() {
    if [[ ! -f "${PROJECT_DIR}/export_presets.cfg" ]]; then
        error "export_presets.cfg not found. Open the Godot editor, go to Project → Export, add your target platforms, and save. Then re-run this command."
    fi
}

_require_podman() {
    command -v podman &>/dev/null || error "Podman is required for this command."
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

cmd_help() {
    cat <<EOF
Usage: ./run.sh [command] [options]

Commands:
  setup [--force]     Install Godot ${GODOT_VERSION} + godot-sqlite plugin
  run   [args]        Run the game (native Godot, needs GPU)
  editor [args]       Open the Godot editor
  export <platform>   Export a release build via Podman container
                        platforms: linux | windows | all
  shell               Open an interactive shell in the export container
  clean               Remove the builds/ directory
  help                Show this help

Versions:
  GODOT_VERSION         ${GODOT_VERSION}  (installed to ${GODOT_INSTALL_DIR}/godot4)
  GODOT_SQLITE_VERSION  ${GODOT_SQLITE_VERSION}
  EXPORT_IMAGE          ${EXPORT_IMAGE}

Notes:
  - setup installs Godot to ~/.local/bin/godot4 (no sudo required)
  - run / editor require a display and GPU — not suitable for containers
  - export / shell use Podman for a reproducible headless build environment
  - export requires export_presets.cfg (create via: ./run.sh editor → Project → Export)
  - After setup, enable the plugin in: Project → Project Settings → Plugins
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${1:-help}" in
    setup)   shift; cmd_setup  "$@" ;;
    run)     shift; cmd_run    "$@" ;;
    editor)  shift; cmd_editor "$@" ;;
    export)  shift; cmd_export "${1:-all}" ;;
    shell)   cmd_shell ;;
    clean)   cmd_clean ;;
    help|--help|-h) cmd_help ;;
    *) error "Unknown command '${1}'. Run ./run.sh help for usage." ;;
esac
