#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# SamNet-WG One-Line Installer
# https://github.com/SamNet-dev/wg-orchestrator
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/SamNet-dev/wg-orchestrator/main/install.sh | sudo bash
#   wget -qO- https://raw.githubusercontent.com/SamNet-dev/wg-orchestrator/main/install.sh | sudo bash
#
# Options:
#   --zero-touch, -z    Skip interactive prompts (auto-configure)
#   --branch BRANCH     Install from a specific branch (default: main)
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Configuration
REPO_URL="https://github.com/SamNet-dev/wg-orchestrator.git"
INSTALL_DIR="/opt/samnet"
BRANCH="${SAMNET_BRANCH:-main}"
ZERO_TOUCH=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --zero-touch|-z) ZERO_TOUCH=true; shift ;;
        --branch) 
            if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                echo -e "${RED}ERROR: --branch requires a value${RESET}"
                exit 1
            fi
            BRANCH="$2"; shift 2 
            ;;
        *) shift ;;
    esac
done

echo ""
echo -e "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                            ║"
echo "║   ███████╗ █████╗ ███╗   ███╗███╗   ██╗███████╗████████╗     ██╗    ██╗ ██████╗  ║"
echo "║   ██╔════╝██╔══██╗████╗ ████║████╗  ██║██╔════╝╚══██╔══╝     ██║    ██║██╔════╝  ║"
echo "║   ███████╗███████║██╔████╔██║██╔██╗ ██║█████╗     ██║        ██║ █╗ ██║██║  ███╗ ║"
echo "║   ╚════██║██╔══██║██║╚██╔╝██║██║╚██╗██║██╔══╝     ██║        ██║███╗██║██║   ██║ ║"
echo "║   ███████║██║  ██║██║ ╚═╝ ██║██║ ╚████║███████╗   ██║        ╚███╔███╔╝╚██████╔╝ ║"
echo "║   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝         ╚══╝╚══╝  ╚═════╝  ║"
echo "║                                                                            ║"
echo "║                    One-Line Installer                                      ║"
echo "║                                                                            ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo ""

# ─── Root Check ───────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This installer must be run as root.${RESET}"
    echo ""
    echo "  Try: curl -sSL ... | ${BOLD}sudo${RESET} bash"
    echo ""
    exit 1
fi

# ─── OS Detection ─────────────────────────────────────────────────────────────
echo -e "${CYAN}[1/4]${RESET} Detecting system..."

if [[ ! -f /etc/os-release ]]; then
    echo -e "${RED}ERROR: Cannot detect OS. /etc/os-release not found.${RESET}"
    exit 1
fi

source /etc/os-release
case "$ID" in
    debian|ubuntu|raspbian)
        echo -e "       ${GREEN}✓${RESET} Detected: ${BOLD}$PRETTY_NAME${RESET}"
        PKG_MGR="apt-get"
        PKG_INSTALL="apt-get install -y -qq"
        ;;
    fedora|rhel|centos|rocky|almalinux)
        echo -e "       ${GREEN}✓${RESET} Detected: ${BOLD}$PRETTY_NAME${RESET}"
        PKG_MGR="dnf"
        PKG_INSTALL="dnf install -y -q"
        ;;
    alpine)
        echo -e "       ${GREEN}✓${RESET} Detected: ${BOLD}$PRETTY_NAME${RESET}"
        PKG_MGR="apk"
        PKG_INSTALL="apk add --quiet"
        ;;
    *)
        echo -e "${YELLOW}WARNING: Untested OS: $ID. Assuming apt-get...${RESET}"
        PKG_MGR="apt-get"
        PKG_INSTALL="apt-get install -y -qq"
        ;;
esac

# ─── Dependencies ─────────────────────────────────────────────────────────────
echo -e "${CYAN}[2/4]${RESET} Checking dependencies..."

install_pkg() {
    local cmd="$1"
    local pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "       Installing $pkg..."
        # Update package cache
        if [[ "$PKG_MGR" == "apt-get" ]]; then
            apt-get update -qq 2>/dev/null || true
        elif [[ "$PKG_MGR" == "dnf" ]]; then
            dnf makecache -q 2>/dev/null || true
        elif [[ "$PKG_MGR" == "apk" ]]; then
            apk update --quiet 2>/dev/null || true
        fi
        # Install package
        $PKG_INSTALL "$pkg" >/dev/null 2>&1 || true
        
        # Verify installation succeeded
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}ERROR: Failed to install $pkg${RESET}"
            echo -e "       Try manually: sudo $PKG_INSTALL $pkg"
            exit 1
        fi
    fi
}

install_pkg git git
install_pkg curl curl

echo -e "       ${GREEN}✓${RESET} Dependencies ready"

# ─── Download/Update ──────────────────────────────────────────────────────────
echo -e "${CYAN}[3/4]${RESET} Downloading SamNet-WG..."

if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo -e "       Existing installation found. Updating..."
    cd "$INSTALL_DIR"
    git fetch origin "$BRANCH" --quiet 2>/dev/null || true
    git reset --hard "origin/$BRANCH" --quiet 2>/dev/null || {
        echo -e "${YELLOW}       Git update failed. Re-cloning...${RESET}"
        cd /
        rm -rf "$INSTALL_DIR"
        git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR" --quiet || {
            echo -e "${RED}ERROR: Failed to clone repository.${RESET}"
            echo -e "       Check: Internet connection, branch name '$BRANCH'"
            exit 1
        }
    }
else
    # Fresh install - but preserve existing data if present
    preserved_clients=""
    
    # Preserve client configs if they exist
    if [[ -d "$INSTALL_DIR/clients" ]]; then
        echo -e "       ${YELLOW}Preserving existing client configs...${RESET}"
        preserved_clients="/tmp/samnet-clients-backup-$$"
        cp -a "$INSTALL_DIR/clients" "$preserved_clients"
    fi
    
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    
    if ! git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR" --quiet; then
        echo -e "${RED}ERROR: Failed to clone repository.${RESET}"
        echo -e "       Check: Internet connection, branch name '$BRANCH'"
        # Restore clients if we backed them up
        if [[ -n "$preserved_clients" && -d "$preserved_clients" ]]; then
            mkdir -p "$INSTALL_DIR/clients"
            cp -a "$preserved_clients/"* "$INSTALL_DIR/clients/" 2>/dev/null || true
            rm -rf "$preserved_clients"
        fi
        exit 1
    fi
    
    # Restore preserved clients
    if [[ -n "$preserved_clients" && -d "$preserved_clients" ]]; then
        mkdir -p "$INSTALL_DIR/clients"
        cp -a "$preserved_clients/"* "$INSTALL_DIR/clients/" 2>/dev/null || true
        rm -rf "$preserved_clients"
        echo -e "       ${GREEN}✓${RESET} Client configs restored"
    fi
fi

echo -e "       ${GREEN}✓${RESET} Downloaded to ${BOLD}$INSTALL_DIR${RESET}"

# ─── Setup ────────────────────────────────────────────────────────────────────
echo -e "${CYAN}[4/4]${RESET} Setting up..."

# Make executable
chmod +x "$INSTALL_DIR/samnet.sh"

# Create symlink for easy access (remove if it's a directory)
[[ -d /usr/local/bin/samnet ]] && rm -rf /usr/local/bin/samnet
ln -sf "$INSTALL_DIR/samnet.sh" /usr/local/bin/samnet

echo -e "       ${GREEN}✓${RESET} Command ${BOLD}samnet${RESET} is now available"

# ─── Launch ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Download complete!${RESET}"
echo ""

if [[ "$ZERO_TOUCH" == "true" ]]; then
    echo -e "${CYAN}Starting zero-touch installation...${RESET}"
    echo ""
    exec "$INSTALL_DIR/samnet.sh" --zero-touch
else
    echo -e "${CYAN}Launching interactive setup...${RESET}"
    echo -e "You'll be guided through:"
    echo -e "  • Subnet configuration"
    echo -e "  • Web UI or CLI-only mode"
    echo -e "  • Firewall settings"
    echo -e "  • First peer creation"
    echo ""
    echo -e "${BOLD}Press Enter to continue...${RESET}"
    # Read from /dev/tty to work even when script is piped
    read -r < /dev/tty 2>/dev/null || true
    exec "$INSTALL_DIR/samnet.sh"
fi
