
#!/bin/sh

set -eu

# Condense CLI installer
# Supports Linux and macOS: amd64 and arm64.

BASE_URL="${CONDENSE_BASE_URL:-https://cli.example.com/condense-cli}"
INSTALL_DIR="${HOME}/.local/bin"
VERSION=""

usage() {
    cat <<'EOF'
Condense CLI installer

Usage:
  ./install.sh [options]

Options:
  --version VERSION    Install a specific version (e.g. v1.0.0)
  --install-dir DIR    Installation directory
  -h, --help           Display this help message

Environment:
  CONDENSE_BASE_URL    Base URL for Condense CLI downloads

Examples:
  ./install.sh
  ./install.sh --version v1.0.0
  ./install.sh --install-dir "$HOME/bin"
EOF
}

error() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            [ "$#" -ge 2 ] || error "Missing version after --version"
            VERSION="$2"
            shift 2
            ;;
        --install-dir)
            [ "$#" -ge 2 ] || error "Missing directory after --install-dir"
            INSTALL_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown argument: $1"
            ;;
    esac
done

[ -n "${HOME:-}" ] || error "HOME is not set"
[ -n "$INSTALL_DIR" ] || error "Installation directory cannot be empty"

# Detect operating system.
OS="$(uname -s)"

case "$OS" in
    Linux)
        OS="linux"
        ;;
    Darwin)
        OS="darwin"
        ;;
    *)
        error "Unsupported operating system: $OS"
        ;;
esac

# Detect CPU architecture.
ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        error "Unsupported architecture: $ARCH"
        ;;
esac

# Resolve the version from the latest pointer if not specified.
if [ -z "$VERSION" ]; then
    printf 'Fetching latest Condense CLI version...\n'

    VERSION="$(curl -fsSL "${BASE_URL}/latest")" ||
        error "Could not retrieve the latest version"

    # Remove leading/trailing whitespace and CRLF.
    VERSION="$(printf '%s' "$VERSION" | tr -d '\r\n')"
fi

# Validate version to prevent malformed release paths.
case "$VERSION" in
    ""|*[!A-Za-z0-9._+-]*|*..*)
        error "Invalid version: $VERSION"
        ;;
esac

case "$VERSION" in
    v[0-9]*|[0-9]*)
        ;;
    *)
        error "Invalid version format: $VERSION (expected v1.0.0)"
        ;;
esac

BINARY="condense-${OS}-${ARCH}"
RELEASE_URL="${BASE_URL}/releases/${VERSION}"
BINARY_URL="${RELEASE_URL}/${BINARY}"
CHECKSUM_URL="${RELEASE_URL}/checksums.txt"

printf '\nInstalling Condense CLI\n'
printf 'Version:      %s\n' "$VERSION"
printf 'OS:           %s\n' "$OS"
printf 'Architecture: %s\n' "$ARCH"
printf 'Install dir:  %s\n\n' "$INSTALL_DIR"

# Download into a temporary directory first.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/condense-install.XXXXXX")" ||
    error "Could not create temporary directory"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

DOWNLOADED_BINARY="${TMP_DIR}/${BINARY}"
CHECKSUM_FILE="${TMP_DIR}/checksums.txt"

printf 'Downloading binary...\n'
curl -fSL "$BINARY_URL" -o "$DOWNLOADED_BINARY" ||
    error "Binary download failed: $BINARY_URL"

printf 'Downloading checksums...\n'
curl -fSL "$CHECKSUM_URL" -o "$CHECKSUM_FILE" ||
    error "Checksum download failed: $CHECKSUM_URL"

# Read the checksum for this exact binary filename.
EXPECTED_CHECKSUM="$(
    awk -v name="$BINARY" '
        $2 == name || $2 == "*" name {
            print $1
            count++
        }
        END {
            if (count != 1) exit 1
        }
    ' "$CHECKSUM_FILE"
)" || error "Could not find exactly one checksum for $BINARY"

# Calculate SHA-256 using the available platform utility.
if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_CHECKSUM="$(sha256sum "$DOWNLOADED_BINARY" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
    ACTUAL_CHECKSUM="$(shasum -a 256 "$DOWNLOADED_BINARY" | awk '{print $1}')"
else
    error "Neither sha256sum nor shasum is available"
fi

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    error "SHA-256 checksum verification failed"
fi

printf 'Checksum verified successfully.\n'

# Install only after successful verification.
mkdir -p "$INSTALL_DIR" ||
    error "Could not create installation directory: $INSTALL_DIR"

chmod 755 "$DOWNLOADED_BINARY" ||
    error "Could not set executable permissions"

mv -f "$DOWNLOADED_BINARY" "${INSTALL_DIR}/condense" ||
    error "Could not install Condense CLI"

printf '\nCondense CLI %s installed successfully.\n' "$VERSION"
printf 'Location: %s/condense\n' "$INSTALL_DIR"

case ":${PATH:-}:" in
    *":${INSTALL_DIR}:"*)
        ;;
    *)
        printf '\nAdd the following to your shell profile to use condense globally:\n'
        printf '  export PATH="%s:$PATH"\n' "$INSTALL_DIR"
        ;;
esac

printf '\nRun: condense --help\n'

