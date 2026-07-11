#!/usr/bin/env sh
# RTR CLI installer
# Usage: curl -fsSL https://install-rtr.ext.suncanyontech.com/install.sh | sh
#
# Installs the `rtr` binary to /usr/local/bin (or ~/bin if not writable).
# One binary — contains both the CLI and the embedded proxy daemon.

set -eu

# Release binaries are published to the dedicated public releases repo by the
# rtr CI pipeline (.github/workflows/release-rtr.yml uploads to
# suncanyon/rtr-releases). The source repo (suncanyon/rtr) has no release assets.
REPO="suncanyon/rtr-releases"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="rtr"
TMPDIR="${TMPDIR:-/tmp}"

# ---------------------------------------------------------------------------
# Detect OS and architecture
# ---------------------------------------------------------------------------

detect_target() {
    OS=$(uname -s)
    ARCH=$(uname -m)

    case "$OS" in
        Linux)
            case "$ARCH" in
                x86_64)  echo "x86_64-unknown-linux-gnu" ;;
                aarch64) echo "aarch64-unknown-linux-gnu" ;;
                arm64)   echo "aarch64-unknown-linux-gnu" ;;
                *)
                    echo "Unsupported architecture: $ARCH" >&2
                    exit 1
                    ;;
            esac
            ;;
        Darwin)
            case "$ARCH" in
                x86_64) echo "x86_64-apple-darwin" ;;
                arm64)  echo "aarch64-apple-darwin" ;;
                *)
                    echo "Unsupported architecture: $ARCH" >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Unsupported OS: $OS" >&2
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Fetch latest version tag from GitHub
# ---------------------------------------------------------------------------

latest_version() {
    # /releases/latest only returns stable (non-prerelease) releases.
    # To install an alpha/beta, set RTR_VERSION=v0.1.0-alpha.1 explicitly.
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
            | grep '"tag_name"' \
            | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" \
            | grep '"tag_name"' \
            | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
    else
        echo "curl or wget is required" >&2
        exit 1
    fi
}

download() {
    URL="$1"
    DEST="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$URL" -o "$DEST"
    else
        wget -qO "$DEST" "$URL"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

TARGET=$(detect_target)
VERSION="${RTR_VERSION:-$(latest_version)}"
VERSION_NUM="${VERSION#v}"

ARCHIVE="rtr-${VERSION_NUM}-${TARGET}.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ARCHIVE}"

TMP_DIR=$(mktemp -d "${TMPDIR}/rtr-install.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Installing rtr ${VERSION} (${TARGET})..."

# Download archive
download "$DOWNLOAD_URL" "${TMP_DIR}/${ARCHIVE}"

# Verify checksum if sha256sum / shasum available
SHA_URL="${DOWNLOAD_URL}.sha256"
if command -v sha256sum >/dev/null 2>&1; then
    download "$SHA_URL" "${TMP_DIR}/${ARCHIVE}.sha256"
    EXPECTED=$(cat "${TMP_DIR}/${ARCHIVE}.sha256" | cut -d' ' -f1)
    ACTUAL=$(sha256sum "${TMP_DIR}/${ARCHIVE}" | cut -d' ' -f1)
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "Checksum mismatch!" >&2
        echo "  Expected: $EXPECTED" >&2
        echo "  Got:      $ACTUAL" >&2
        exit 1
    fi
elif command -v shasum >/dev/null 2>&1; then
    download "$SHA_URL" "${TMP_DIR}/${ARCHIVE}.sha256"
    EXPECTED=$(cat "${TMP_DIR}/${ARCHIVE}.sha256" | cut -d' ' -f1)
    ACTUAL=$(shasum -a 256 "${TMP_DIR}/${ARCHIVE}" | cut -d' ' -f1)
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "Checksum mismatch!" >&2
        exit 1
    fi
fi

# Extract
tar -xzf "${TMP_DIR}/${ARCHIVE}" -C "${TMP_DIR}"

# Install — unlink first so upgrades succeed even while the proxy daemon is running.
# rm on a running binary is safe on Linux/macOS: the kernel keeps the old inode
# alive until the last fd closes; the new file gets a fresh inode at the same path.
install_binary() {
    TARGET_DIR="$1"
    USE_SUDO="$2"

    if [ "$USE_SUDO" = "yes" ]; then
        sudo rm -f "${TARGET_DIR}/${BINARY_NAME}"
        sudo cp "${TMP_DIR}/${BINARY_NAME}" "${TARGET_DIR}/${BINARY_NAME}"
        sudo chmod +x "${TARGET_DIR}/${BINARY_NAME}"
    else
        rm -f "${TARGET_DIR}/${BINARY_NAME}"
        cp "${TMP_DIR}/${BINARY_NAME}" "${TARGET_DIR}/${BINARY_NAME}"
        chmod +x "${TARGET_DIR}/${BINARY_NAME}"
    fi
}

if [ -w "$INSTALL_DIR" ]; then
    install_binary "$INSTALL_DIR" no
    INSTALLED_TO="${INSTALL_DIR}/${BINARY_NAME}"
elif command -v sudo >/dev/null 2>&1; then
    install_binary "$INSTALL_DIR" yes
    INSTALLED_TO="${INSTALL_DIR}/${BINARY_NAME}"
else
    mkdir -p "$HOME/bin"
    install_binary "$HOME/bin" no
    INSTALLED_TO="$HOME/bin/${BINARY_NAME}"
    echo ""
    echo "Installed to ~/bin — make sure ~/bin is in your PATH:"
    echo '  export PATH="$HOME/bin:$PATH"'
fi

echo ""
echo "rtr ${VERSION} installed to ${INSTALLED_TO}"
echo ""
echo "Get started:"
echo "  rtr claude setup    # Connect Claude Code to RTR"
echo "  rtr init            # Set up the proxy for any other agent"
echo "  rtr --help          # Full command reference"
