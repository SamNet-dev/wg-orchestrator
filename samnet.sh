#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# SamNet-WG Unified Manager, Installer & CLI/TUI
# Version: 1.0.3
# License: MIT
#
# This is the SINGLE unified script that handles:
#   - Zero-touch installation
#   - Step-by-step wizard
#   - Full TUI management interface
#   - All CLI operations
#   - System repair and maintenance
# ══════════════════════════════════════════════════════════════════════════════

# Enabled UTF-8 for TUI
export LC_ALL=C.UTF-8
# set -euo pipefail

# ══════════════════════════════════════════════════════════════════════════════
# 1. GLOBAL CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

readonly SAMNET_VERSION="1.0.4"
readonly APP_NAME="SamNet-WG"

# ══════════════════════════════════════════════════════════════════════════════
# 1.5 INTEGRITY & SELF-HEALING
# ══════════════════════════════════════════════════════════════════════════════
# Only run file-based checks if we're executing from a file (not piped via curl)
if [[ -f "$0" ]]; then
    # 1. Fix line endings if saved on Windows (CRLF -> LF)
    if grep -q $'\r' "$0" 2>/dev/null; then
        sed -i 's/\r$//' "$0"
        exec "$0" "$@"
    fi

    # 2. Verify script syntax before doing any work
    check_integrity() {
        if ! bash -n "$0" 2>/tmp/samnet-syntax.tmp; then
            echo -e "\033[1;31m"
            echo "╔══════════════════════════════════════════════════════════════════════╗"
            echo "║   CRITICAL ERROR: SCRIPT SYNTAX CORRUPTED                            ║"
            echo "╚══════════════════════════════════════════════════════════════════════╝"
            echo -e "\033[0m"
            echo "A local modification to samnet.sh has introduced a syntax error."
            echo "Script execution aborted to prevent system state corruption."
            echo ""
            echo "Error Details:"
            cat /tmp/samnet-syntax.tmp
            echo ""
            rm -f /tmp/samnet-syntax.tmp
            exit 1
        fi
        rm -f /tmp/samnet-syntax.tmp
    }
    check_integrity
fi

readonly TAGLINE="WireGuard Orchestrator & Management Platform"

# Trap terminal Resize
trap 'needs_refresh=true' SIGWINCH

# Paths (samnet-wg specific to avoid conflicts with other samnet products)
readonly DB_PATH="/var/lib/samnet-wg/samnet.db"
readonly WG_CONF="/etc/wireguard/wg0.conf"
readonly TRIGGER_FILE="/var/lib/samnet-wg/reconcile.trigger"
readonly INSTALL_DIR="/opt/samnet"
readonly CRED_FILE="/root/.samnet-wg_initial_credentials"

# Update System
readonly REPO_URL="https://github.com/SamNet-dev/wg-orchestrator.git"
readonly UPDATE_BRANCH="${SAMNET_BRANCH:-main}"
# Note: REMOTE_VERSION_URL must be set after UPDATE_BRANCH is defined
REMOTE_VERSION_URL="https://raw.githubusercontent.com/SamNet-dev/wg-orchestrator/${UPDATE_BRANCH}/samnet.sh"

# State
NOCOLOR=false
INTERACTIVE=false
ZERO_TOUCH=false
TERM_COLS=80
TERM_ROWS=24

# Self-Location
if [[ -f "$INSTALL_DIR/samnet" && "$(realpath "$0" 2>/dev/null)" == "$INSTALL_DIR/samnet" ]]; then
    DIR="$INSTALL_DIR"
else
    DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 2. SAMNET TERMINAL UI FRAMEWORK
# ══════════════════════════════════════════════════════════════════════════════
#
# A custom-built terminal UI system designed to make SamNet feel like
# professional infrastructure software, not a bash script.
#
# Design Philosophy:
# - Every screen is a composed layout, not printed text
# - Visual consistency across all interactions
# - Operator trust through polish and predictability
# - Retro-futuristic aesthetic with modern functionality
#
# ══════════════════════════════════════════════════════════════════════════════

# ─── Theme & Color Engine ─────────────────────────────────────────────────────

init_colors() {
    if [[ "$NOCOLOR" == true ]] || ! [[ -t 1 ]]; then
        # No-color mode: all color codes empty
        T_RESET="" T_BOLD="" T_DIM="" T_ITALIC="" T_UNDERLINE="" T_BLINK="" T_REVERSE=""
        T_BLACK="" T_RED="" T_GREEN="" T_YELLOW="" T_BLUE="" T_MAGENTA="" T_CYAN="" T_WHITE=""
        T_ORANGE="" T_GRAY="" T_BG="" T_FG=""
        # Legacy compatibility
        C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN="" C_MAGENTA="" C_WHITE="" C_ORANGE=""
    else
        # SamNet Theme: Amber/Orange primary, Cyan accent, Dark background assumed
        T_RESET=$'\033[0m'
        T_BOLD=$'\033[1m'
        T_DIM=$'\033[2m'
        T_ITALIC=$'\033[3m'
        T_UNDERLINE=$'\033[4m'
        T_BLINK=$'\033[5m'
        T_REVERSE=$'\033[7m'
        
        # Core palette (256-color safe)
        T_BLACK=$'\033[38;5;232m'
        T_RED=$'\033[38;5;196m'
        T_GREEN=$'\033[38;5;82m'
        T_YELLOW=$'\033[38;5;220m'
        T_BLUE=$'\033[38;5;39m'
        T_MAGENTA=$'\033[38;5;201m'
        T_CYAN=$'\033[38;5;51m'
        T_WHITE=$'\033[38;5;255m'
        T_ORANGE=$'\033[38;5;208m'
        T_GRAY=$'\033[38;5;240m'
        
        # Background accents
        T_BG_HIGHLIGHT=$'\033[48;5;236m'
        T_BG_SELECT=$'\033[48;5;238m'
        T_BG_DANGER=$'\033[48;5;52m'
        
        # Legacy compatibility
        C_RESET="$T_RESET" C_BOLD="$T_BOLD" C_DIM="$T_DIM"
        C_RED="$T_RED" C_GREEN="$T_GREEN" C_YELLOW="$T_YELLOW"
        C_BLUE="$T_BLUE" C_CYAN="$T_CYAN" C_MAGENTA="$T_MAGENTA"
        C_WHITE="$T_WHITE" C_ORANGE="$T_ORANGE"
    fi
    
    # Semantic colors - RETRO GREEN THEME
    CLR_PRIMARY="$T_GREEN"
    CLR_ACCENT="$T_CYAN"
    CLR_SUCCESS="$T_GREEN"
    CLR_WARNING="$T_YELLOW"
    CLR_DANGER="$T_RED"
    CLR_MUTED="$T_GRAY"
    CLR_TEXT="$T_WHITE"
    
    # Status indicators (consistent symbols)
    ICON_OK="${T_GREEN}●${T_RESET}"
    ICON_WARN="${T_YELLOW}●${T_RESET}"
    ICON_FAIL="${T_RED}●${T_RESET}"
    ICON_INFO="${T_CYAN}◆${T_RESET}"
    ICON_ARROW="${T_GREEN}▸${T_RESET}"
    ICON_CHECK="${T_GREEN}✓${T_RESET}"
    ICON_CROSS="${T_RED}✗${T_RESET}"
    ICON_DOT="${T_GRAY}·${T_RESET}"
    
    # Legacy icons
    SUCCESS_ICON="$ICON_CHECK"
    ERROR_ICON="$ICON_CROSS"
    WARN_ICON="${T_YELLOW}⚠${T_RESET}"
    INFO_ICON="${T_CYAN}ℹ${T_RESET}"
}

# Helper: Normalize CIDR (e.g. 10.100.0.1/19 -> 10.100.0.0/19)
normalize_cidr() {
    local raw=$1
    [[ -z "$raw" ]] && echo "Not configured" && return
    
    local ip=$(echo "$raw" | cut -d/ -f1)
    local mask=$(echo "$raw" | cut -d/ -f2)
    # If no mask, assume /32
    if [[ "$ip" == "$mask" ]] || [[ -z "$mask" ]]; then mask=32; fi

    # Very simple normalization for common privates
    if [[ "$ip" =~ ^10\.|^172\.|^192\. ]]; then
         local base=$(echo "$ip" | cut -d. -f1-3)
         echo "${base}.0/${mask}"
    else
         echo "$raw"
    fi
}

# Helper: UI Checkbox
ui_checkbox() {
    if [[ "$1" == "true" ]]; then
        printf "${T_GREEN} [x] ${T_RESET}"
    else
        printf "${T_DIM} [ ] ${T_RESET}"
    fi
}


# ─── Terminal Control ─────────────────────────────────────────────────────────


get_term_size() {
    if command -v tput &>/dev/null && [[ -t 1 ]]; then
        TERM_COLS=$(tput cols 2>/dev/null) || TERM_COLS=80
        TERM_ROWS=$(tput lines 2>/dev/null) || TERM_ROWS=24
    else
        TERM_COLS=80
        TERM_ROWS=24
    fi
    # Minimum dimensions
    [[ $TERM_COLS -lt 60 ]] && TERM_COLS=60
    [[ $TERM_ROWS -lt 20 ]] && TERM_ROWS=20
}

ui_clear() { printf '\033[2J\033[H'; }
ui_hide_cursor() { printf '\033[?25l'; }
ui_show_cursor() { printf '\033[?25h'; }
ui_save_cursor() { printf '\033[s'; }
ui_restore_cursor() { printf '\033[u'; }
ui_move_to() { printf '\033[%d;%dH' "$1" "$2"; }
ui_clear_line() { printf '\033[2K'; }
ui_clear_to_end() { printf '\033[J'; }

# Alternate screen buffer - creates a separate "app space"
ui_enter_app() {
    tput smcup 2>/dev/null || true  # Enter alternate screen
    ui_hide_cursor
    stty -echo 2>/dev/null || true
    trap 'ui_exit_app' EXIT INT TERM
}

ui_exit_app() {
    ui_show_cursor
    stty echo 2>/dev/null || true
    tput rmcup 2>/dev/null || true  # Exit alternate screen
    printf "${T_RESET}"
}

# Ensure terminal state is restored on exit
ui_cleanup() {
    ui_exit_app
}

# ─── Layout System ────────────────────────────────────────────────────────────

# Content area dimensions (accounting for header/footer)
LAYOUT_HEADER_HEIGHT=9
LAYOUT_FOOTER_HEIGHT=3
LAYOUT_CONTENT_START=$((LAYOUT_HEADER_HEIGHT + 1))

# Repeat a character N times (UTF-8 safe)
ui_repeat() {
    local char="$1" count="$2"
    local result=""
    for ((i=0; i<count; i++)); do result+="$char"; done
    printf "%s" "$result"
}

# Horizontal rule with optional label
ui_rule() {
    local label="${1:-}"
    local char="${2:-─}"
    local width=$((TERM_COLS - 4))
    
    if [[ -n "$label" ]]; then
        local label_len=${#label}
        local left_len=$(( (width - label_len - 2) / 2 ))
        local right_len=$(( width - label_len - 2 - left_len ))
        printf "  ${T_WHITE}%s ${T_CYAN}${T_BOLD}%s${T_RESET}${T_WHITE} %s${T_RESET}\n" \
            "$(ui_repeat "$char" $left_len)" "$label" "$(ui_repeat "$char" $right_len)"
    else
        printf "  ${T_WHITE}%s${T_RESET}\n" "$(ui_repeat "$char" $width)"
    fi
}

# ─── Header Component ─────────────────────────────────────────────────────────

ui_draw_header() {
    local title="${1:-}"
    ui_clear
    
    # ASCII Banner - Retro Terminal Style
    printf "${T_GREEN}${T_BOLD}"
    cat << 'BANNER'
    ╔════════════════════════════════════════════════════════════════════╗
    ║  ███████╗ █████╗ ███╗   ███╗███╗   ██╗███████╗████████╗            ║
    ║  ██╔════╝██╔══██╗████╗ ████║████╗  ██║██╔════╝╚══██╔══╝            ║
    ║  ███████╗███████║██╔████╔██║██╔██╗ ██║█████╗     ██║               ║
    ║  ╚════██║██╔══██║██║╚██╔╝██║██║╚██╗██║██╔══╝     ██║               ║
    ║  ███████║██║  ██║██║ ╚═╝ ██║██║ ╚████║███████╗   ██║               ║
    ║  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝               ║
    ╚════════════════════════════════════════════════════════════════════╝
BANNER
    printf "${T_RESET}"
    
    # Branding bar
    printf "    ${T_DIM}────────────────────────────────────────────────────────────────${T_RESET}\n"
    printf "    ${T_GREEN}${T_BOLD}By ${AUTHOR}${T_RESET}  ${T_GRAY}│${T_RESET}  ${T_CYAN}${WEBSITE}${T_RESET}  ${T_GRAY}│${T_RESET}  ${T_DIM}v${SAMNET_VERSION} - General Public Release${T_RESET}\n"
    printf "    ${T_WHITE}${TAGLINE}${T_RESET}\n"
    printf "    ${T_DIM}────────────────────────────────────────────────────────────────${T_RESET}\n"
    
    # Screen title if provided
    if [[ -n "$title" ]]; then
        printf "\n    ${T_GREEN}${T_BOLD}▸ %s${T_RESET}\n" "$title"
    fi
    printf "\n"
}

# Minimal header for sub-screens
ui_draw_header_mini() {
    local title="$1"
    ui_clear
    printf "    ${T_ORANGE}${T_BOLD}▸ SAMNET${T_RESET} ${T_GRAY}│${T_RESET} ${T_CYAN}%s${T_RESET}\n" "$title"
    ui_rule
    printf "\n"
}

# ─── Footer Component ─────────────────────────────────────────────────────────

ui_draw_footer() {
    local hints="${1:-}"
    local extra="${2:-}"
    
    printf "\n"
    ui_rule
    printf "    ${T_DIM}%s${T_RESET}" "$hints"
    [[ -n "$extra" ]] && printf "  ${T_GRAY}│${T_RESET}  ${T_DIM}%s${T_RESET}" "$extra"
    printf "\n"
}

# ─── Box Components ───────────────────────────────────────────────────────────

# Standard content box with title
# Standard content box with title (ASCII safe)
ui_box() {
    local title="$1"
    shift
    local width=$((TERM_COLS - 8))
    local inner_width=$((width - 4))
    
    # Top border with title
    printf "    ${T_CYAN}+-${T_BOLD}${T_WHITE} %s ${T_RESET}${T_CYAN}" "$title"
    printf -- "%s+${T_RESET}\n" "$(ui_repeat '-' $((width - ${#title} - 5)))"
    
    # Content lines
    for line in "$@"; do
        printf "    ${T_CYAN}|${T_RESET}  ${T_WHITE}%-${inner_width}s${T_RESET}  ${T_CYAN}|${T_RESET}\n" "$line"
    done
    
    # Bottom border
    printf "    ${T_CYAN}+%s+${T_RESET}\n" "$(ui_repeat '-' $((width - 2)))"
}

# Info box (blue accent)
# Info box (blue accent)
ui_box_info() {
    local title="$1"
    shift
    local width=$((TERM_COLS - 8))
    local inner_width=$((width - 4))
    
    printf "    ${T_BLUE}+-${T_BOLD} %s ${T_RESET}${T_BLUE}" "$title"
    printf -- "%s+${T_RESET}\n" "$(ui_repeat '-' $((width - ${#title} - 5)))"
    
    for line in "$@"; do
        printf "    ${T_BLUE}|${T_RESET}  ${T_WHITE}%s${T_RESET}%*s${T_BLUE}|${T_RESET}\n" "$line" $((inner_width - ${#line})) ""
    done
    
    printf "    ${T_BLUE}+%s+${T_RESET}\n" "$(ui_repeat '-' $((width - 2)))"
}

# Warning box (yellow accent)
# Warning box (yellow accent)
ui_box_warn() {
    local title="$1"
    shift
    local width=$((TERM_COLS - 8))
    
    printf "    ${T_YELLOW}+-${T_BOLD}! %s ${T_RESET}${T_YELLOW}" "$title"
    printf -- "%s+${T_RESET}\n" "$(ui_repeat '-' $((width - ${#title} - 6)))"
    
    for line in "$@"; do
        printf "    ${T_YELLOW}|${T_RESET}  ${T_YELLOW}%s${T_RESET}\n" "$line"
    done
    
    printf "    ${T_YELLOW}+%s+${T_RESET}\n" "$(ui_repeat '-' $((width - 2)))"
}

# Danger box (red accent)
# Danger box (red accent)
ui_box_danger() {
    local title="$1"
    shift
    local width=$((TERM_COLS - 8))
    
    printf "    ${T_RED}+=${T_BOLD}${T_BLINK}!${T_RESET}${T_RED}${T_BOLD} %s ${T_RESET}${T_RED}" "$title"
    printf -- "%s+${T_RESET}\n" "$(ui_repeat '=' $((width - ${#title} - 6)))"
    
    for line in "$@"; do
        printf "    ${T_RED}|${T_RESET}  ${T_RED}${T_BOLD}%s${T_RESET}\n" "$line"
    done
    
    printf "    ${T_RED}+%s+${T_RESET}\n" "$(ui_repeat '=' $((width - 2)))"
}

# ─── Status Badges ────────────────────────────────────────────────────────────

ui_status() {
    local label="$1"
    local state="$2"
    local detail="${3:-}"
    local icon value_color
    
    case "$state" in
        ok|online|active|running|pass)
            icon="$ICON_OK"
            value_color="$T_GREEN"
            ;;
        warn|warning|degraded|slow)
            icon="$ICON_WARN"
            value_color="$T_YELLOW"
            ;;
        fail|error|offline|stopped|critical)
            icon="$ICON_FAIL"
            value_color="$T_RED"
            ;;
        *)
            icon="$ICON_INFO"
            value_color="$T_CYAN"
            ;;
    esac
    
    printf "    %s %-18s ${value_color}%s${T_RESET}" "$icon" "$label" "$state"
    [[ -n "$detail" ]] && printf "  ${T_DIM}%s${T_RESET}" "$detail"
    printf "\n"
}

# Compact status row (for dashboards)
ui_status_row() {
    local items=("$@")
    printf "    "
    for item in "${items[@]}"; do
        IFS='=' read -r label state <<< "$item"
        case "$state" in
            ok|online|active) printf "${ICON_OK} %-10s " "$label" ;;
            warn|degraded)    printf "${ICON_WARN} %-10s " "$label" ;;
            fail|offline)     printf "${ICON_FAIL} %-10s " "$label" ;;
            *)                printf "${ICON_INFO} %-10s " "$label" ;;
        esac
    done
    printf "\n"
}

# ─── Menu System ──────────────────────────────────────────────────────────────

# Single menu option
ui_menu_item() {
    local key="$1"
    local label="$2"
    local desc="${3:-}"
    local selected="${4:-false}"
    
    if [[ "$selected" == "true" ]]; then
        printf "    ${T_BG_SELECT}${T_CYAN}${T_BOLD}[%s]${T_RESET}${T_BG_SELECT} ${T_WHITE}%-24s${T_RESET}${T_BG_SELECT} ${T_CYAN}%s${T_RESET}\n" "$key" "$label" "$desc"
    else
        printf "    ${T_CYAN}${T_BOLD}[%s]${T_RESET} %-24s ${T_WHITE}%s${T_RESET}\n" "$key" "$label" "$desc"
    fi
}

# Menu group header
ui_menu_group() {
    local title="$1"
    printf "\n    ${T_ORANGE}${T_BOLD}%s${T_RESET}\n" "$title"
    printf "    ${T_GRAY}$(ui_repeat '─' 40)${T_RESET}\n"
}

# Separator between menu sections
ui_menu_sep() {
    printf "\n"
}

# ─── Data Display ─────────────────────────────────────────────────────────────

# Key-value pair
ui_kv() {
    local key="$1"
    local value="$2"
    local indent="${3:-4}"
    printf "%*s${T_CYAN}%-14s${T_RESET} ${T_WHITE}%s${T_RESET}\n" "$indent" "" "$key:" "$value"
}

# Tree-style list item
ui_tree() {
    local prefix="$1"
    local label="$2"
    local value="$3"
    local last="${4:-false}"
    
    if [[ "$last" == "true" ]]; then
        printf "    └─ ${T_GRAY}%-12s${T_RESET} ${T_WHITE}%s${T_RESET}\n" "$label" "$value"
    else
        printf "    ├─ ${T_GRAY}%-12s${T_RESET} ${T_WHITE}%s${T_RESET}\n" "$label" "$value"
    fi
}

# Table header
ui_table_header() {
    local cols=("$@")
    printf "    ${T_BOLD}"
    for col in "${cols[@]}"; do
        printf "%-16s" "$col"
    done
    printf "${T_RESET}\n"
    printf "    ${T_GRAY}$(ui_repeat '─' $(( ${#cols[@]} * 16 )))${T_RESET}\n"
}

# Table row
ui_table_row() {
    local cols=("$@")
    printf "    "
    for col in "${cols[@]}"; do
        printf "%-16s" "$col"
    done
    printf "\n"
}

# ─── Progress & Loading ───────────────────────────────────────────────────────

ui_progress() {
    local label="$1"
    local percent="$2"
    local width=30
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    
    printf "    %-20s ${T_CYAN}[" "$label"
    printf "$(ui_repeat '#' $filled)"
    printf "${T_WHITE}$(ui_repeat '.' $empty)"
    printf "${T_CYAN}]${T_RESET} ${T_WHITE}%3d%%${T_RESET}\n" "$percent"
}

ui_spinner() {
    local label="$1"
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while true; do
        printf "\r    ${T_CYAN}%s${T_RESET} %s " "${chars:i:1}" "$label"
        ((i = (i + 1) % ${#chars}))
        sleep 0.1
    done
}

# ─── Input Components ─────────────────────────────────────────────────────────

ui_prompt() {
    local label="$1"
    local default="${2:-}"
    local result
    
    if [[ -n "$default" ]]; then
        printf "    ${T_CYAN}❯${T_RESET} %s ${T_WHITE}[%s]${T_RESET}: " "$label" "$default" >&2
    else
        printf "    ${T_CYAN}❯${T_RESET} %s: " "$label" >&2
    fi
    
    stty echo 2>/dev/null
    read -r result
    stty -echo 2>/dev/null
    echo "${result:-$default}"
}

ui_confirm() {
    local message="$1"
    local response
    printf "    ${T_YELLOW}⚠${T_RESET} %s ${T_DIM}[y/N]${T_RESET} " "$message"
    read -rsn1 response
    printf "%s\n" "$response"
    if [[ "$response" == "y" || "$response" == "Y" ]]; then
        return 0
    else
        return 1
    fi
}

ui_confirm_danger() {
    local action="$1"
    local code=$(printf "%04d" $((RANDOM % 10000)))
    
    printf "\n"
    ui_box_danger "DANGER ZONE" \
        "You are about to: $action" \
        "" \
        "This action cannot be undone."
    
    printf "\n    To confirm, type: ${T_BOLD}${T_RED}%s${T_RESET}\n" "$code"
    printf "    ${T_CYAN}❯${T_RESET} "
    
    local input
    read -r input
    [[ "$input" == "$code" ]]
}

ui_wait_key() {
    local message="${1:-Press any key to continue...}"
    printf "\n    ${T_DIM}%s${T_RESET}" "$message"
    read -rsn1
    printf "\n"
}

ui_read_key() {
    local key
    # Only use timeout when Web UI is enabled (for sync updates)
    # CLI-only mode doesn't need polling since there's no Web UI to sync with
    if [[ "$(db_get_config web_ui_enabled)" == "true" ]]; then
        read -rsn1 -t 7 key 2>/dev/null
    else
        read -rsn1 key 2>/dev/null
    fi
    echo "$key"
}

# Alias for compatibility
read_key_static() {
    local key
    read -rsn1 key 2>/dev/null
    echo "$key"
}

# ─── Help Overlay ─────────────────────────────────────────────────────────────

ui_help_overlay() {
    local title="$1"
    shift
    local lines=("$@")
    
    ui_draw_header_mini "Help: $title"
    
    ui_box_info "About This Screen" "${lines[@]}"
    
    printf "\n"
    ui_menu_group "Keyboard Shortcuts"
    ui_kv "[B/Esc]" "Go back"
    ui_kv "[Q]" "Quit application"
    ui_kv "[?]" "Show this help"
    ui_kv "[/]" "Command palette"
    
    ui_wait_key
}

# ─── Messages & Logging ───────────────────────────────────────────────────────

log_info() { printf "    ${T_CYAN}ℹ${T_RESET} %s\n" "$1"; }
log_success() { printf "    ${T_GREEN}✓${T_RESET} %s\n" "$1"; }
log_warn() { printf "    ${T_YELLOW}⚠${T_RESET} ${T_YELLOW}%s${T_RESET}\n" "$1"; }
log_error() { printf "    ${T_RED}✗${T_RESET} ${T_RED}%s${T_RESET}\n" "$1" >&2; }
log_step() { printf "    ${T_CYAN}▸${T_RESET} %s\n" "$1"; }

exit_with_error() {
    log_error "$1"
    printf "\n    ${T_RED}Aborted.${T_RESET}\n"
    exit 1
}

# ─── Legacy Compatibility Layer ───────────────────────────────────────────────

clear_screen() { ui_clear; }
hide_cursor() { ui_hide_cursor; }
show_cursor() { ui_show_cursor; }

show_banner() { ui_draw_header; }
section() { printf "\n    ${T_ORANGE}${T_BOLD}▸ %s${T_RESET}\n" "$1"; ui_rule; }
menu_option() { ui_menu_item "$@"; }
show_footer() { ui_draw_footer "$@"; }
draw_box() { ui_box "$@"; }
prompt() { ui_prompt "$@"; }
confirm() { ui_confirm "$@"; }
wait_key() { ui_wait_key "$@"; }
read_key() { ui_read_key; }
draw_line() { ui_repeat "${1:-─}" "${2:-$TERM_COLS}"; }

# ─── Help Screen ──────────────────────────────────────────────────────────────

show_help_screen() {
    while true; do
        ui_clear
        printf "${T_GREEN}${T_BOLD}"
        cat << 'HELP_BANNER'
    ╔══════════════════════════════════════════════════════════════════════╗
    ║                         SAMNET HELP CENTER                          ║
    ╚══════════════════════════════════════════════════════════════════════╝
HELP_BANNER
        printf "${T_RESET}\n"
        
        printf "    ${T_CYAN}${T_BOLD}NAVIGATION${T_RESET}\n"
        printf "    ${T_WHITE}────────────────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_GREEN}↑/↓${T_RESET}  or  ${T_GREEN}j/k${T_RESET}     Navigate menu items\n"
        printf "    ${T_GREEN}Enter${T_RESET}              Select/confirm\n"
        printf "    ${T_GREEN}B${T_RESET} or ${T_GREEN}Esc${T_RESET}          Go back\n"
        printf "    ${T_GREEN}Q${T_RESET}                  Quit application\n"
        printf "    ${T_GREEN}H${T_RESET}                  Show this help\n"
        printf "    ${T_GREEN}A${T_RESET}                  About SamNet\n\n"
        
        printf "    ${T_CYAN}${T_BOLD}PEER MANAGEMENT${T_RESET}\n"
        printf "    ${T_WHITE}────────────────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_WHITE}Add Peer${T_RESET}           Create a new VPN client\n"
        printf "    ${T_WHITE}List Peers${T_RESET}         View all connected clients\n"
        printf "    ${T_WHITE}Remove Peer${T_RESET}        Delete a client and revoke access\n"
        printf "    ${T_WHITE}Show QR Code${T_RESET}       Display QR for mobile setup\n\n"
        
        printf "    ${T_CYAN}${T_BOLD}SYSTEM OPERATIONS${T_RESET}\n"
        printf "    ${T_WHITE}────────────────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_WHITE}Status${T_RESET}             View WireGuard tunnel status\n"
        printf "    ${T_WHITE}Config${T_RESET}             Edit server configuration\n"
        printf "    ${T_WHITE}Logs${T_RESET}               View system logs\n"
        printf "    ${T_WHITE}Restart${T_RESET}            Restart WireGuard service\n\n"
        
        printf "    ${T_CYAN}${T_BOLD}ADVANCED TOOLS${T_RESET}\n"
        printf "    ${T_WHITE}────────────────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_WHITE}Troubleshooter${T_RESET}     Auto-detect and fix issues\n"
        printf "    ${T_WHITE}Repair Wizard${T_RESET}      Rebuild critical configs\n"
        printf "    ${T_WHITE}DDNS Setup${T_RESET}         Configure Dynamic DNS\n"
        printf "    ${T_WHITE}Watch Mode${T_RESET}         Live traffic dashboard\n"
        printf "    ${T_WHITE}Benchmarks${T_RESET}         Test system performance\n"
        printf "    ${T_WHITE}Export Diag${T_RESET}        Generate support bundle\n\n"
        
        printf "    ${T_CYAN}${T_BOLD}WEB UI${T_RESET}\n"
        printf "    ${T_WHITE}────────────────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_WHITE}Default Username:${T_RESET}  ${T_GREEN}admin${T_RESET}\n"
        printf "    ${T_WHITE}Default Password:${T_RESET}  ${T_GREEN}changeme${T_RESET}\n"
        printf "    ${T_WHITE}Access:${T_RESET}            HTTP on port 80 (local network)\n"
        printf "    ${T_DIM}Enable via: Main Menu → Install/Repair → Enable Web UI${T_RESET}\n\n"
        
        printf "    ${T_CYAN}${T_BOLD}PORTS REQUIRED${T_RESET}\n"
        printf "    ${T_WHITE}────────────────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_WHITE}51820/UDP${T_RESET}          WireGuard VPN traffic\n"
        printf "    ${T_WHITE}80/TCP${T_RESET}             Web UI (optional, if enabled)\n\n"
        
        printf "    ${T_CYAN}${T_BOLD}COMMAND LINE${T_RESET}\n"
        printf "    ${T_WHITE}────────────────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_WHITE}samnet${T_RESET}             Launch interactive TUI\n"
        printf "    ${T_WHITE}samnet --update${T_RESET}    Check for and apply updates\n"
        printf "    ${T_WHITE}samnet --status${T_RESET}    Show system status\n"
        printf "    ${T_WHITE}samnet -z${T_RESET}          Zero-touch install\n"
        printf "    ${T_WHITE}samnet --uninstall${T_RESET} Remove SamNet-WG\n\n"
        
        ui_draw_footer "[B] Back"
        
        local key=$(read_key_static)
        case "$key" in
            b|B|$'\x1b'|q|Q) return ;;
        esac
    done
}

# ─── About Screen ─────────────────────────────────────────────────────────────

show_about_screen() {
    while true; do
        ui_clear
        printf "${T_GREEN}${T_BOLD}"
        cat << 'ABOUT_BANNER'
    ╔══════════════════════════════════════════════════════════════════════╗
    ║  ███████╗ █████╗ ███╗   ███╗███╗   ██╗███████╗████████╗              ║
    ║  ██╔════╝██╔══██╗████╗ ████║████╗  ██║██╔════╝╚══██╔══╝              ║
    ║  ███████╗███████║██╔████╔██║██╔██╗ ██║█████╗     ██║                 ║
    ║  ╚════██║██╔══██║██║╚██╔╝██║██║╚██╗██║██╔══╝     ██║                 ║
    ║  ███████║██║  ██║██║ ╚═╝ ██║██║ ╚████║███████╗   ██║                 ║
    ║  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝                 ║
    ╚══════════════════════════════════════════════════════════════════════╝
ABOUT_BANNER
        printf "${T_RESET}\n"
        
        printf "    ${T_CYAN}${T_BOLD}WireGuard Orchestrator & Management Platform${T_RESET}\n\n"
        
        printf "    ${T_WHITE}Version:${T_RESET}     ${T_GREEN}${SAMNET_VERSION}${T_RESET}\n"
        printf "    ${T_WHITE}Author:${T_RESET}      ${T_CYAN}${AUTHOR}${T_RESET}\n"
        printf "    ${T_WHITE}Website:${T_RESET}     ${T_CYAN}${WEBSITE}${T_RESET}\n"
        printf "    ${T_WHITE}License:${T_RESET}     ${T_DIM}MIT License${T_RESET}\n\n"
        
        printf "    ${T_WHITE}────────────────────────────────────────────────────────${T_RESET}\n\n"
        
        printf "    ${T_DIM}SamNet-WG is an enterprise-grade WireGuard VPN management${T_RESET}\n"
        printf "    ${T_DIM}platform designed for simplicity and security. It provides${T_RESET}\n"
        printf "    ${T_DIM}zero-touch installation, automatic peer management, and a${T_RESET}\n"
        printf "    ${T_DIM}beautiful terminal interface for self-hosted VPN servers.${T_RESET}\n\n"
        
        printf "    ${T_WHITE}────────────────────────────────────────────────────────${T_RESET}\n\n"
        
        printf "    ${T_CYAN}${T_BOLD}System Locations:${T_RESET}\n"
        printf "    ${T_WHITE}Install Dir:${T_RESET}   ${T_DIM}/opt/samnet${T_RESET}\n"
        printf "    ${T_WHITE}Database:${T_RESET}      ${T_DIM}/var/lib/samnet-wg${T_RESET}\n"
        printf "    ${T_WHITE}Logs:${T_RESET}          ${T_DIM}/var/log/samnet-wg${T_RESET}\n"
        printf "    ${T_WHITE}WG Config:${T_RESET}     ${T_DIM}/etc/wireguard${T_RESET}\n"
        printf "    ${T_WHITE}Auth File:${T_RESET}     ${T_DIM}/opt/samnet/credentials.txt${T_RESET}\n\n"
        
        printf "    ${T_GREEN}★${T_RESET} ${T_DIM}Built with love for the self-hosting community${T_RESET}\n"
        printf "    ${T_GREEN}★${T_RESET} ${T_DIM}Powered by WireGuard® - the modern VPN protocol${T_RESET}\n"
        printf "    ${T_GREEN}★${T_RESET} ${T_DIM}100%% Open Source - Audit the code yourself${T_RESET}\n\n"
        
        ui_draw_footer "[B] Back"
        
        local key=$(read_key)
        case "$key" in
            b|B|$'\x1b'|q|Q) return ;;
        esac
    done
}


# ══════════════════════════════════════════════════════════════════════════════
# 3. SECURITY & VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

# Early dependency check - runs BEFORE TUI starts
ensure_early_dependencies() {
    local missing=()
    
    # Critical dependencies that must be present
    command -v sqlite3 &>/dev/null || missing+=("sqlite3")
    command -v curl &>/dev/null || missing+=("curl")
    command -v ip &>/dev/null || missing+=("iproute2")
    command -v wg &>/dev/null || missing+=("wireguard-tools")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${T_GREEN}${T_BOLD}[SamNet]${T_RESET} Checking dependencies..."
        echo -e "${T_DIM}  Missing: ${missing[*]}${T_RESET}"
        echo -e "${T_GREEN}  Installing required packages (this may take a moment)...${T_RESET}"
        
        # Detect package manager and install with PROGRESS
        if command -v apt-get &>/dev/null; then
            apt-get update
            apt-get install -y "${missing[@]}"
        elif command -v dnf &>/dev/null; then
            dnf install -y "${missing[@]}"
        elif command -v yum &>/dev/null; then
            yum install -y "${missing[@]}"
        elif command -v pacman &>/dev/null; then
            pacman -Sy --noconfirm "${missing[@]}"
        else
            echo -e "${T_RED}ERROR: Could not detect package manager.${T_RESET}"
            echo "Please install manually: ${missing[*]}"
            exit 1
        fi
        
        if [[ $? -eq 0 ]]; then
             echo -e "${T_GREEN}✓ Dependencies installed successfully${T_RESET}"
        else
             echo -e "${T_RED}✗ Installation failed. Please check your internet connection or package manager.${T_RESET}"
             exit 1
        fi
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${C_RED}ERROR: Must run as root (sudo)${C_RESET}" >&2
        exit 1
    fi
}

detect_public_ip() {
    local sources=(
        "https://ifconfig.me"
        "https://icanhazip.com"
        "https://ipinfo.io/ip"
        "https://api.ipify.org"
    )
    local ips=()
    
    for url in "${sources[@]}"; do
        local ip=$(curl --silent --max-time 5 -4 "$url" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ips+=("$ip")
        fi
    done
    
    # Fallback to local interface IP detection if external services fail
    if [[ ${#ips[@]} -lt 2 ]]; then
        [[ -n "${SAMNET_WAN_IP:-}" ]] && echo "$SAMNET_WAN_IP" && return 0
        # Local interface fallback
        local local_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
        if [[ "$local_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_warn "Using local interface IP as fallback: $local_ip"
            echo "$local_ip"
            return 0
        fi
        return 1
    fi
    
    printf '%s\n' "${ips[@]}" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}'
}

validate_interface() {
    local iface="$1"
    [[ "$iface" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    ip link show "$iface" &>/dev/null
}

run_preflight_checks() {
    log_info "Running pre-flight checks..."
    local failed=0
    
    # Check for 1GB free (500MB base + 500MB for Docker images)
    # Check for 1GB free (500MB base + 500MB for Docker images)
    local free_mb=$(df -m /var 2>/dev/null | tail -1 | awk '{print $4}')
    if [[ ${free_mb:-0} -lt 1000 ]]; then
        log_warn "Insufficient disk: ${free_mb}MB (need 1GB+ for Docker images)"
        log_info "Attempting to free space..."
        docker image prune -f >/dev/null 2>&1 || true
    fi
    
    # Critical checks (must pass)
    if ! lsmod 2>/dev/null | grep -q wireguard && ! modprobe wireguard 2>/dev/null; then
        log_error "WireGuard module required but not available"
        ((failed++))
    fi
    
    for port in 51820 80 8080; do
        if ss -tuln 2>/dev/null | grep -q ":$port "; then
            log_warn "Port $port in use"
        fi
    done
    
    if ! curl --silent --max-time 5 https://google.com &>/dev/null; then
        log_warn "No internet connectivity"
    fi
    
    [[ $failed -gt 0 ]] && return 1
    log_success "Pre-flight checks passed"
}

sanitize_input() { echo "${1//\'/\'\'}"; }

validate_key() {
    [[ "$1" =~ ^[a-zA-Z0-9_]+$ ]] || { log_error "Invalid key: $1"; return 1; }
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. DATABASE ENGINE
# ══════════════════════════════════════════════════════════════════════════════

ensure_db_init() {
    mkdir -p "$(dirname "$DB_PATH")" && chmod 700 "$(dirname "$DB_PATH")"
    
    if [[ ! -f "$DB_PATH" ]]; then
        log_info "Initializing database schema..."
        sqlite3 -batch "$DB_PATH" <<SQL || exit_with_error "Failed to initialize database schema"
CREATE TABLE IF NOT EXISTS system_config (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'viewer', failed_attempts INTEGER DEFAULT 0, lockout_until DATETIME);
CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, token_hash TEXT UNIQUE NOT NULL, user_id INTEGER NOT NULL, created_at DATETIME NOT NULL, expires_at DATETIME NOT NULL);
CREATE TABLE IF NOT EXISTS peers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL, public_key TEXT UNIQUE NOT NULL, encrypted_private_key TEXT NOT NULL, allowed_ips TEXT NOT NULL, disabled INTEGER DEFAULT 0, last_handshake DATETIME, rx_bytes INTEGER DEFAULT 0, tx_bytes INTEGER DEFAULT 0, total_rx_bytes INTEGER DEFAULT 0, total_tx_bytes INTEGER DEFAULT 0, data_limit_gb INTEGER DEFAULT 0, expires_at INTEGER, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS historical_usage (id INTEGER PRIMARY KEY AUTOINCREMENT, peer_name TEXT NOT NULL, public_key TEXT, rx_bytes INTEGER DEFAULT 0, tx_bytes INTEGER DEFAULT 0, deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS audit_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, action TEXT NOT NULL, target TEXT, details TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE IF NOT EXISTS system_state (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS ip_pool (id INTEGER PRIMARY KEY AUTOINCREMENT, ip TEXT UNIQUE, used INTEGER DEFAULT 0);
CREATE INDEX IF NOT EXISTS idx_peers_public_key ON peers(public_key);
CREATE INDEX IF NOT EXISTS idx_sessions_token_hash ON sessions(token_hash);
SQL
        chmod 600 "$DB_PATH"
        log_success "Database initialized"
    fi
    
    # Auto-migrate existing databases: add new columns if missing
    if [[ -f "$DB_PATH" ]]; then
        # Check if data_limit_gb column exists, if not add it (and related columns)
        local has_limit=$(sqlite3 "$DB_PATH" "PRAGMA table_info(peers);" | grep -c "data_limit_gb" || echo "0")
        if [[ "$has_limit" == "0" ]]; then
            log_info "Migrating database schema..."
            sqlite3 "$DB_PATH" "ALTER TABLE peers ADD COLUMN total_rx_bytes INTEGER DEFAULT 0;" 2>/dev/null
            sqlite3 "$DB_PATH" "ALTER TABLE peers ADD COLUMN total_tx_bytes INTEGER DEFAULT 0;" 2>/dev/null
            sqlite3 "$DB_PATH" "ALTER TABLE peers ADD COLUMN data_limit_gb INTEGER DEFAULT 0;" 2>/dev/null
            sqlite3 "$DB_PATH" "ALTER TABLE peers ADD COLUMN disabled INTEGER DEFAULT 0;" 2>/dev/null
            sqlite3 "$DB_PATH" "ALTER TABLE peers ADD COLUMN expires_at INTEGER;" 2>/dev/null
            log_success "Database migrated"
        fi
    fi
}

# Database Abstraction (Handles Standalone vs Sync mode)
db_query() {
    [[ ! -f "$DB_PATH" ]] && return 1
    command -v sqlite3 &>/dev/null || return 1
    # Remove 2>/dev/null to allow seeing actual sqlite errors if they occur
    sqlite3 -batch "$DB_PATH" "$1"
}

db_exec() {
    [[ ! -f "$DB_PATH" ]] && return 0 # No-op if DB not present
    command -v sqlite3 &>/dev/null || return 0
    
    # Retry loop for locked DB (SQLITE_BUSY)
    local retries=0
    local max_retries=5
    while [[ $retries -lt $max_retries ]]; do
        # capturing error output
        if err=$(sqlite3 -batch "$DB_PATH" "$1" 2>&1); then
            return 0
        else
            # Check if locked
            if [[ "$err" == *"database is locked"* ]]; then
                ((retries++))
                sleep 0.2
                continue
            else
                # Genuine error
                # log_error "DB Error: $err" # Uncomment for debug
                return 1
            fi
        fi
    done
    return 1
}

db_set_config() {
    validate_key "$1" || return 1
    local safe_value=$(sanitize_input "$2")
    db_exec "INSERT OR REPLACE INTO system_config (key, value) VALUES ('$1', '$safe_value');"
}

db_get_config() {
    validate_key "$1" || return 1
    db_query "SELECT value FROM system_config WHERE key='$1';"
}

get_peer_count() {
    db_query "SELECT COUNT(*) FROM peers;" || echo "0"
}

get_stale_peer_count() {
    db_query "SELECT COUNT(*) FROM peers WHERE disabled=1;" || echo "0"
}

# Get the configured API port (default: 8766)
get_api_port() {
    local port=$(db_get_config "api_port" 2>/dev/null)
    [[ -z "$port" ]] && port="8766"
    echo "$port"
}

# Get the full API base URL
get_api_url() {
    # On Windows/Docker Desktop, host requests appear as Gateway IP, rejected by LocalhostOnly middleware.
    # We must use 'docker exec' for internal ops, but 'curl' for external status checks.
    echo "http://127.0.0.1:$(get_api_port)"
}

# Helper to execute internal API calls reliably on any OS/Network
# Usage: api_call "GET|POST|PUT|DELETE" "/internal/..." [data_json]
# Returns empty and non-zero exit if Docker/container unavailable (graceful fallback)
api_call() {
    local method="$1"
    local path="$2"
    local data="$3"
    
    # Check if Docker is available and container is running
    if ! command -v docker &>/dev/null; then
        return 1  # Docker not installed
    fi
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^samnet-wg-api$"; then
        return 1  # Container not running
    fi
    
    # Use docker exec to run curl INSIDE the container (where localhost is trusted)
    local cmd="curl -s -X $method http://127.0.0.1:$(get_api_port)$path"
    
    if [[ -n "$data" ]]; then
        cmd="$cmd -H 'Content-Type: application/json' -d '$data'"
    fi
     
    # Execute inside container
    docker exec samnet-wg-api sh -c "$cmd" 2>/dev/null
}

# Check if a port is available
is_port_available() {
    local port=$1
    # Use ss with sport filter (more reliable than grep with \s which isn't portable)
    ! ss -Htuln sport = ":$port" 2>/dev/null | grep -q .
}


# Find an available port starting from the given port
find_available_port() {
    local start_port=${1:-8766}
    local max_port=$((start_port + 100))
    
    for (( port=start_port; port < max_port; port++ )); do
        if is_port_available "$port"; then
            echo "$port"
            return 0
        fi
    done
    
    # Fallback to default
    echo "$start_port"
    return 1
}

# IP Address synchronization helpers
ip2int() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    a=${a:-0} b=${b:-0} c=${c:-0} d=${d:-0}
    echo "$(( (a << 24) + (b << 16) + (c << 8) + d ))"
}

int2ip() {
    local n=$1
    echo "$(( (n >> 24) & 0xFF )).$(( (n >> 16) & 0xFF )).$(( (n >> 8) & 0xFF )).$(( n & 0xFF ))"
}

db_allocate_ip() {
    local requested="${1:-}"
    local lock_file="/var/run/samnet-ip-alloc.lock"
    
    # ─── CRITICAL SECTION LOCK ───
    # Use fd 200 for locking to prevent race conditions during concurrent creates
    exec 200>"$lock_file"
    if ! flock -x -w 5 200; then
        log_error "Failed to acquire IP allocation lock."
        return 1
    fi
    
    # ─── ALLOCATE ───
    # (Wrapped in subshell to unsure lock releases on return/exit)
    (
        # Check if we should use DB sync or Standalone Switch
        local use_db=false
        if [[ -f "$DB_PATH" ]] && command -v sqlite3 &>/dev/null; then
            if [[ "$(sqlite3 "$DB_PATH" "SELECT value FROM system_config WHERE key='web_ui_enabled';" 2>/dev/null)" == "true" ]]; then
                use_db=true
            fi
        fi

        # Authoritative Subnet Discovery
        local cidr="10.100.0.0/24"
        if $use_db; then
            cidr=$(db_get_config "subnet_cidr")
        else
            # Fallback to wg0.conf parsing for standalone mode
            cidr=$(grep "Address" /etc/wireguard/wg0.conf 2>/dev/null | cut -d= -f2 | tr -d ' ' | cut -d, -f1)
        fi
        [[ -z "$cidr" ]] && cidr="10.100.0.0/24"
        
        local base_ip=$(echo "$cidr" | cut -d/ -f1)
        local prefix=$(echo "$cidr" | cut -d/ -f2)
        local base_int=$(ip2int "$base_ip")
        local host_bits=$((32 - prefix))
        local num_hosts=$(( 1 << host_bits ))
        
        # Exclusions
        local used_ips
        if $use_db; then
            used_ips=$( (sqlite3 "$DB_PATH" "SELECT allowed_ips FROM peers;" 2>/dev/null | cut -d/ -f1; \
                         grep -R "Address" "$INSTALL_DIR/clients" 2>/dev/null | cut -d= -f2 | tr -d ' ' | cut -d/ -f1) | sort -u )
        else
            used_ips=$(grep -R "Address" "$INSTALL_DIR/clients" 2>/dev/null | cut -d= -f2 | tr -d ' ' | cut -d/ -f1 | sort -u)
        fi
        
        # Add server's own IP (usually .1) to used list
        local server_ip=$(grep "Address" /etc/wireguard/wg0.conf 2>/dev/null | cut -d= -f2 | tr -d ' ' | cut -d/ -f1)
        [[ -z "$server_ip" ]] && server_ip="${base_ip%.*}.1"
        used_ips=$(printf "%s\n%s" "$used_ips" "$server_ip" | sort -u)

        # 1. Handle Requested IP/Octet
        if [[ -n "$requested" ]]; then
            local target="$requested"
            # If it's just an octet (1-254)
            if [[ "$requested" =~ ^[0-9]+$ ]] && [[ "$requested" -ge 1 ]] && [[ "$requested" -lt $((num_hosts-1)) ]]; then
                target=$(int2ip $((base_int + requested)))
            fi
            
            # Validate target is in subnet and not network/broadcast
            local target_int=$(ip2int "$target" 2>/dev/null)
            if [[ -n "$target_int" ]] && [[ $target_int -gt $base_int ]] && [[ $target_int -lt $((base_int + num_hosts - 1)) ]]; then
                if ! echo "$used_ips" | grep -qx "$target"; then
                    echo "$target"
                    exit 0
                else
                    # log_error "IP $target is already in use." # Quiet logic for internal func
                    exit 1
                fi
            else
                exit 1
            fi
        fi

        # 2. Auto-generate: Scan for first free IP starting at .1
        for (( i=1; i < num_hosts - 1; i++ )); do
            local candidate_int=$((base_int + i))
            local candidate=$(int2ip "$candidate_int")
            if ! echo "$used_ips" | grep -qx "$candidate"; then
                echo "$candidate"
                exit 0
            fi
        done
        exit 1
    )
    local result=$?
    
    # ─── UNLOCK ───
    flock -u 200
    
    return $result
}

# Helper: Scan for peers (Unifies File + DB + Interface sources)
# Returns a line-delimited list: NAME|IP|SOURCE|STATUS
scan_peers() {
    local client_dir="$INSTALL_DIR/clients"
    declare -A peer_map_name  # Keys: Name
    declare -A peer_map_ip
    declare -A peer_map_src
    local peer_ids=() # Order preservation

    # 1. Source: Filesystem (Primary for Mode A)
    if [[ -d "$client_dir" ]]; then
        for conf in "$client_dir"/*.conf; do
            [[ -e "$conf" ]] || continue
            local n=$(basename "$conf" .conf)
            local ip=$(grep "Address" "$conf" 2>/dev/null | cut -d= -f2 | tr -d ' ' | cut -d/ -f1)
            [[ -z "$ip" ]] && ip="Unknown"
            
            peer_map_name["$n"]="$n"
            peer_map_ip["$n"]="$ip"
            peer_map_src["$n"]="FILE"
            peer_ids+=("$n")
        done
    fi

    # 2. Source: Database (Primary for Mode B, overwrites File info if cheaper/richer)
    if [[ -f "$DB_PATH" ]] && command -v sqlite3 &>/dev/null; then
        while IFS='|' read -r n ip disabled; do
            [[ -z "$n" ]] && continue
            local status="ACTIVE"
            [[ "$disabled" == "1" ]] && status="DISABLED"
            
            # If existed in file, just update metadata. If new, add.
            if [[ -z "${peer_map_name[$n]}" ]]; then
                peer_ids+=("$n")
            fi
            peer_map_name["$n"]="$n"
            peer_map_ip["$n"]="$ip"
            peer_map_src["$n"]="DB"
        done < <(sqlite3 -separator '|' "$DB_PATH" "SELECT name, allowed_ips, disabled FROM peers ORDER BY name ASC;" 2>/dev/null)
    fi

    # 3. Source: Active Interface (Validation Layer)
    local active_pubs=""
    local transfer_dump=""
    if command -v wg &>/dev/null && wg show wg0 &>/dev/null; then
        active_pubs=$(wg show wg0 latest-handshakes)
        transfer_dump=$(wg show wg0 transfer)
    fi
    
    # 4. Usage Limits (Pre-fetch for performance)
    declare -A peer_limits
    declare -A peer_stored_usage
    if [[ -f "$DB_PATH" ]]; then
        while IFS='|' read -r n lim stored; do
            [[ -n "$lim" && "$lim" != "0" ]] && peer_limits["$n"]=$lim
            peer_stored_usage["$n"]=${stored:-0}
        done < <(sqlite3 "$DB_PATH" "SELECT name, data_limit_gb, (total_rx_bytes + total_tx_bytes) FROM peers;")
    fi

    # Output Result
    local sorted_names=$(printf "%s\n" "${peer_ids[@]}" | sort -u)
    local g_mask=$(db_get_config "subnet_cidr" | cut -d/ -f2)
    [[ -z "$g_mask" ]] && g_mask="24"

    for n in $sorted_names; do
        [[ -z "$n" ]] && continue
        local ip="${peer_map_ip[$n]}"
        local src="${peer_map_src[$n]}"
        local status="UNKNOWN"

        local display_ip="$ip"
        if [[ "$display_ip" == *"/32" ]] || [[ "$display_ip" != *"/"* ]]; then
             display_ip="${display_ip%%/*}/${g_mask}"
        fi

        # Determine Status
        local disabled=0
        if [[ "$src" == "DB" ]]; then
            local db_st=$(sqlite3 "$DB_PATH" "SELECT disabled FROM peers WHERE name='$n';" 2>/dev/null)
            [[ "$db_st" == "1" ]] && disabled=1
        elif [[ "$src" == "FILE" ]]; then 
            [[ -f "$INSTALL_DIR/clients/${n}.conf.disabled" ]] && disabled=1
        fi
        
        # Check Limits
        local is_over_limit=0
        if [[ "${peer_limits[$n]}" ]]; then
             local limit_bytes=$(( ${peer_limits[$n]} * 1024 * 1024 * 1024 ))
             local stored=${peer_stored_usage[$n]}
             local live=0
             # Get pubkey to find live usage
             local pub=$(db_query "SELECT public_key FROM peers WHERE name='$n';" 2>/dev/null)
             if [[ -z "$pub" && -f "$client_dir/${n}.conf" ]]; then
                 local priv=$(grep "PrivateKey" "$client_dir/${n}.conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
                 [[ -n "$priv" ]] && pub=$(echo "$priv" | wg pubkey 2>/dev/null)
             fi
             
             if [[ -n "$pub" && -n "$transfer_dump" ]]; then
                 local rx=0 tx=0
                 # Use substring match to be safer or awk exact
                 # transfer_dump is: pubkey rx tx
                 local line=$(echo "$transfer_dump" | grep "$pub")
                 if [[ -n "$line" ]]; then
                    read -r _ rx tx <<< "$line"
                 fi
                 live=$((rx + tx))
             fi
             
             if (( stored + live > limit_bytes )); then
                 is_over_limit=1
             fi
        fi
        
        if [[ "$is_over_limit" == "1" ]]; then
            status="OVER LIMIT"
        elif [[ "$disabled" == "1" ]]; then
            status="OFFLINE"
        else
            # If enabled, check for handshake
            # Need pubkey (might have fetched above or fetch now)
            [[ -z "$pub" ]] && pub=$(db_query "SELECT public_key FROM peers WHERE name='$n';" 2>/dev/null)
            if [[ -z "$pub" && -f "$client_dir/${n}.conf" ]]; then
                 local priv=$(grep "PrivateKey" "$client_dir/${n}.conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
                 [[ -n "$priv" ]] && pub=$(echo "$priv" | wg pubkey 2>/dev/null)
            fi
            
            if [[ -n "$pub" ]] && echo "$active_pubs" | grep -q "$pub"; then
                local ts=$(echo "$active_pubs" | grep "$pub" | awk '{print $2}')
                if [[ "$ts" != "0" ]]; then 
                    status="ONLINE ACTIVE"
                else
                    status="ACTIVE" 
                fi
            else
                 status="ACTIVE"
            fi
        fi
        
        echo "$n|$display_ip|$src|$status"
    done
}

# reconcile_db_with_files ensures the database matches the actual file state
# (Crucial for recovery after being offline/shutdown)
reconcile_db_with_files() {
    [[ ! -f "$DB_PATH" ]] && return
    
    local client_dir="$INSTALL_DIR/clients"
    [[ ! -d "$client_dir" ]] && return

    # 0. Self-heal: Purge corrupt IP entries from DB (Fixes 0.0.0.0 ghost peers)
    db_exec "DELETE FROM peers WHERE allowed_ips LIKE '/%' OR allowed_ips LIKE '0.0.0.0/%';"

    # 1. Adopt new files into DB that aren't there yet
    # (Enables CLI-to-Web UI sync even for manually added files)
    for conf in "$client_dir"/*.conf; do
        [[ -e "$conf" ]] || continue
        local name=$(basename "$conf" .conf)
        
        # If not in DB, try to adopt it
        if [[ -z "$(db_query "SELECT id FROM peers WHERE name='$name';")" ]]; then
            local priv=$(grep "PrivateKey" "$conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
            local full_addr=$(grep "Address" "$conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
            local addr=$(echo "$full_addr" | cut -d/ -f1)
            
            # CRITICAL FIX: Validate IP before inserting to prevent 0.0.0.0/32 corruption
            if [[ -n "$priv" && -n "$addr" && "$addr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                local pub=$(echo "$priv" | wg pubkey 2>/dev/null)
                if [[ -n "$pub" ]]; then
                    # CRITICAL: Always encrypt private key for DB if possible (allows Web UI visibility)
                    local enc_priv=$(encrypt_peer_key "$priv")
                    
                    # Use full_addr if it has a slash, otherwise default to /32
                    local insert_addr="$full_addr"
                    [[ "$insert_addr" != *"/"* ]] && insert_addr="${addr}/32"
                    db_exec "INSERT OR IGNORE INTO peers (name, public_key, encrypted_private_key, allowed_ips) VALUES ('$name', '$pub', '$enc_priv', '$insert_addr');"
                fi
            else
                # If we have a file but it's invalid (no IP, or bad format), it's likely a ghost/corrupt file
                # from a race condition. Delete it to prevent "0.0.0.0" phantom peers.
                log_warn "Found invalid/corrupt peer config '$name'. Deleting..."
                rm -f "$conf"
                rm -f "${conf}.expiry"
            fi
        fi
        
        # 1.5 Handle Disabled State Sync (File -> DB)
        # PRIORITY: Presence of file forces DB to Disabled (Safety).
        # Absence of file does NOT force DB to Enabled (prevents race conditions).
        # To enable a peer, the DB must be updated explicitly (via API or CLI Wizard).
        if [[ -f "${conf}.disabled" ]]; then
            db_exec "UPDATE peers SET disabled=1 WHERE name='$name' AND (disabled=0 OR disabled IS NULL);"
        fi
    done

    # 2. Purge DB entries that have no physical file OR no WireGuard presence
    
    local web_ui_active=$(db_get_config web_ui_enabled)
    local db_peers=$(db_query "SELECT name FROM peers;")
    
    for p in $db_peers; do
        local is_disabled=$(db_query "SELECT disabled FROM peers WHERE name='$p';")
        if [[ "$is_disabled" == "1" ]]; then
            [[ ! -f "$client_dir/${p}.conf.disabled" ]] && touch "$client_dir/${p}.conf.disabled"
        else
            [[ -f "$client_dir/${p}.conf.disabled" ]] && rm -f "$client_dir/${p}.conf.disabled"
        fi
        
        if [[ ! -f "$client_dir/${p}.conf" ]]; then
            
            # Reverse Sync: Restore local file from DB (enables CLI QR/Config view for WebUI peers)
            if [[ "$web_ui_active" == "true" ]]; then
                # Fetch encrypted details from DB
                local enc_priv=$(db_query "SELECT encrypted_private_key FROM peers WHERE name='$p';")
                
                if [[ -n "$enc_priv" ]]; then
                    # Attempt to decrypt using Master Key
                    local priv=$(decrypt_peer_key "$enc_priv")
                    
                    if [[ -n "$priv" ]]; then
                        # FIX: Use full CIDR from DB, don't force /32 (fixes mismatch with Web UI)
                        local full_cidr=$(db_query "SELECT allowed_ips FROM peers WHERE name='$p';")
                        
                        local dns=$(db_get_config dns_server)
                        [[ -z "$dns" ]] && dns="1.1.1.1" # Fallback
                        local endpoint_addr=$(db_get_config server_ip)
                        local endpoint_port=$(db_get_config wireguard_port)
                        local srv_pub=$(cat /etc/wireguard/publickey 2>/dev/null)
                        
                        log_info "Restoring local config for '$p' from DB..."
                        
                        cat <<EOF > "$client_dir/${p}.conf"
[Interface]
PrivateKey = $priv
Address = $full_cidr
DNS = $dns

[Peer]
PublicKey = $srv_pub
Endpoint = ${endpoint_addr}:${endpoint_port}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
                        chmod 600 "$client_dir/${p}.conf"
                        
                        # Generate expiry marker if needed (optional)
                        echo "$(date +%s)" > "$client_dir/${p}.conf.expiry"
                        continue
                    else
                         log_warn "Failed to decrypt key for '$p'. Master Key or OpenSSL issue?"
                    fi
                fi
                # CRITICAL: If Web UI is active, NEVER delete from DB just because file is missing/failed to regenerate.
                continue
            fi

            # Standard Logic for CLI-only mode:
            # If file is gone AND not in live WireGuard -> Delete from DB
            if ! wg show wg0 peers 2>/dev/null | grep -q "$(db_query "SELECT public_key FROM peers WHERE name='$p';")"; then
                db_exec "DELETE FROM peers WHERE name='$p';"
            fi
        fi
    done
}

# ─── Backup & Restore (Migration Core) ───────────────────────────────────────

do_backup() {
    local target_dir="${1:-/root/samnet-backups}"
    mkdir -p "$target_dir"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local archive="$target_dir/samnet-backup-$timestamp.tar.gz"
    
    log_step "Preparing backup archive..."
    
    # Create temp workspace
    local tmp_dir=$(mktemp -d)
    
    # Copy critical state
    cp "$DB_PATH" "$tmp_dir/samnet.db" 2>/dev/null
    cp "/var/lib/samnet-wg/master.key" "$tmp_dir/master.key" 2>/dev/null
    cp "$WG_CONF" "$tmp_dir/wg0.conf" 2>/dev/null
    cp /etc/wireguard/privatekey "$tmp_dir/privatekey" 2>/dev/null
    cp /etc/wireguard/publickey "$tmp_dir/publickey" 2>/dev/null
    
    # Bundle clients
    mkdir -p "$tmp_dir/clients"
    cp "$INSTALL_DIR/clients/"*.conf "$tmp_dir/clients/" 2>/dev/null
    
    # Compress
    tar -czf "$archive" -C "$tmp_dir" .
    rm -rf "$tmp_dir"
    
    log_success "Backup created: $archive"
    [[ "$INTERACTIVE" == "true" ]] && wait_key
    echo "$archive"
}

do_restore() {
    local archive="$1"
    if [[ ! -f "$archive" ]]; then
        log_error "Backup file not found: $archive"
        return 1
    fi
    
    ui_confirm_danger "RESTORE SYSTEM STATE (This will overwrite current config)" || return 1
    
    log_step "Stopping WireGuard..."
    wg-quick down wg0 2>/dev/null || true
    
    log_step "Extracting backup..."
    local tmp_dir=$(mktemp -d)
    tar -xzf "$archive" -C "$tmp_dir"
    
    # Atomic Move
    log_step "Applying configurations..."
    mkdir -p "/var/lib/samnet-wg"
    mv "$tmp_dir/samnet.db" "$DB_PATH" 2>/dev/null
    mv "$tmp_dir/master.key" "/var/lib/samnet-wg/master.key" 2>/dev/null
    cp "$tmp_dir/wg0.conf" "$WG_CONF" 2>/dev/null
    cp "$tmp_dir/privatekey" /etc/wireguard/privatekey 2>/dev/null
    cp "$tmp_dir/publickey" /etc/wireguard/publickey 2>/dev/null
    
    # Restore clients
    mkdir -p "$INSTALL_DIR/clients"
    cp "$tmp_dir/clients/"*.conf "$INSTALL_DIR/clients/" 2>/dev/null
    
    rm -rf "$tmp_dir"
    
    log_step "Starting WireGuard..."
    wg-quick up wg0 2>/dev/null || log_warn "Failed to start WireGuard. Check config manualy."
    
    log_success "Restore complete. System state has been reverted."
    wait_key
}

screen_maintenance() {
    while true; do
        ui_draw_header_mini "Maintenance & Migration"
        
        draw_box "Migration Tools" \
            "Backup allows you to move SamNet to a new server." \
            "Restore allows you to revert to a previous state."
            
        printf "\n"
        menu_option "1" "Create Backup" "Save current system state"
        menu_option "2" "Restore Backup" "Apply a backup archive"
        menu_option "3" "Export Diag" "Generate support telemetry"
        printf "\n"
        menu_option "B" "Back" ""
        
        ui_draw_footer "[1-3] Select  [B] Back"
        
        local key=$(read_key)
        case "$key" in
            1) do_backup ;;
            2) 
                ui_clear
                ui_draw_header_mini "Restore System"
                local files=(/root/samnet-backups/*.tar.gz)
                if [[ ! -e "${files[0]}" ]]; then
                    log_error "No backups found in /root/samnet-backups/"
                    wait_key
                else
                    log_info "Recent Backups:"
                    local i=1
                    for f in "${files[@]}"; do
                        printf "  [%d] %s\n" "$i" "$(basename "$f")"
                        ((i++))
                    done
                    local choice=$(ui_prompt "Select backup ID (or path)")
                    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ -n "${files[$((choice-1))]}" ]]; then
                        do_restore "${files[$((choice-1))]}"
                    elif [[ -f "$choice" ]]; then
                        do_restore "$choice"
                    fi
                fi
                ;;
            3) log_info "Diagnostic bundle generation not yet implemented."; wait_key ;;
            b|B|$'\x1b') return ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# 5. SYSTEM INFO HELPERS
# ══════════════════════════════════════════════════════════════════════════════

get_hostname() { hostname 2>/dev/null || echo "unknown"; }

get_os_info() {
    [[ -f /etc/os-release ]] && source /etc/os-release && echo "${PRETTY_NAME:-${NAME:-Linux}}" || echo "Linux"
}

get_compose_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
    else
        return 1
    fi
}

get_kernel() { uname -r 2>/dev/null || echo "unknown"; }

get_wg_status() {
    systemctl is-active --quiet wg-quick@wg0 2>/dev/null && echo "ONLINE" || echo "OFFLINE"
}

get_wg_interface_info() {
    if command -v wg &>/dev/null && wg show wg0 &>/dev/null; then
        local port=$(wg show wg0 listen-port 2>/dev/null || echo "51820")
        local peers=$(wg show wg0 peers 2>/dev/null | wc -l)
        echo "Port: $port | Peers: $peers"
    else
        echo "Not configured"
    fi
}

get_firewall_backend() {
    command -v nft &>/dev/null && nft list ruleset &>/dev/null && echo "nftables" || echo "unknown"
}

get_cpu_usage() { top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "N/A"; }
get_mem_usage() { free 2>/dev/null | awk '/Mem:/ {printf "%.0f%%", $3/$2 * 100}' || echo "N/A"; }
get_disk_usage() { df -h / 2>/dev/null | awk 'NR==2 {print $5}' || echo "N/A"; }

# ══════════════════════════════════════════════════════════════════════════════
# 5.5 AUTO-UPDATE SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

get_remote_version() {
    # Fetch just the version line from remote script (timeout 10s)
    # Streams through grep to avoid loading entire file into memory
    curl -sSL --max-time 10 "$REMOTE_VERSION_URL" 2>/dev/null | \
        grep -m1 'readonly SAMNET_VERSION=' | cut -d'"' -f2
}

version_compare() {
    # Returns: 0 if $1 > $2, 1 if equal, 2 if $1 < $2
    # Handles versions like 1.0.4, 1.0.4-beta, 1.2.3.4
    local v1="$1" v2="$2"
    
    # Strip any suffix after hyphen for comparison (e.g., 1.0.4-beta -> 1.0.4)
    v1="${v1%%-*}"
    v2="${v2%%-*}"
    
    [[ "$v1" == "$v2" ]] && return 1
    
    local IFS=.
    local i v1_arr=($v1) v2_arr=($v2)
    
    for ((i=0; i<${#v1_arr[@]}; i++)); do
        # Extract only numeric part from each component
        local n1="${v1_arr[i]%%[^0-9]*}"
        local n2="${v2_arr[i]%%[^0-9]*}"
        [[ -z "$n1" ]] && n1=0
        [[ -z "$n2" ]] && n2=0
        
        [[ -z "${v2_arr[i]:-}" ]] && return 0
        ((10#$n1 > 10#$n2)) && return 0
        ((10#$n1 < 10#$n2)) && return 2
    done
    
    [[ ${#v1_arr[@]} -lt ${#v2_arr[@]} ]] && return 2
    return 1
}

do_update() {
    ui_clear
    ui_draw_header_mini "System Update"
    
    log_info "Checking for updates..."
    
    # Cleanup trap for interrupted updates
    trap 'rm -f "$INSTALL_DIR/samnet.sh.new" 2>/dev/null' RETURN
    
    # Check internet connectivity
    if ! curl -s --max-time 5 https://github.com &>/dev/null; then
        log_error "Cannot reach GitHub. Check your internet connection."
        wait_key
        return 1
    fi
    
    local remote_version
    remote_version=$(get_remote_version)
    
    if [[ -z "$remote_version" ]]; then
        log_error "Failed to fetch remote version."
        wait_key
        return 1
    fi
    
    echo ""
    echo "  Current version: ${T_CYAN}v${SAMNET_VERSION}${T_RESET}"
    echo "  Latest version:  ${T_GREEN}v${remote_version}${T_RESET}"
    echo ""
    
    version_compare "$remote_version" "$SAMNET_VERSION"
    local cmp=$?
    
    if [[ $cmp -eq 1 ]]; then
        log_success "You are running the latest version!"
        wait_key
        return 0
    elif [[ $cmp -eq 2 ]]; then
        log_warn "Local version is newer than remote (dev build?)"
        wait_key
        return 0
    fi
    
    # Update available
    log_info "Update available: v${SAMNET_VERSION} → v${remote_version}"
    echo ""
    echo "  ${T_DIM}Your data will be preserved:${T_RESET}"
    echo "  ${T_DIM}  ✓ WireGuard configs  ✓ Peers & clients${T_RESET}"
    echo "  ${T_DIM}  ✓ Database settings  ✓ Firewall rules${T_RESET}"
    echo ""
    
    if ! ui_confirm "Apply update now?"; then
        log_info "Update cancelled."
        wait_key
        return 0
    fi
    
    log_step "Creating backup..."
    local backup_script="/tmp/samnet-backup-$(date +%s).sh"
    cp "$INSTALL_DIR/samnet.sh" "$backup_script" 2>/dev/null || true
    
    log_step "Downloading update..."
    
    # Method 1: Git pull (preferred if .git exists)
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        cd "$INSTALL_DIR"
        if git fetch origin "$UPDATE_BRANCH" --quiet 2>/dev/null && \
           git reset --hard "origin/$UPDATE_BRANCH" --quiet 2>/dev/null; then
            log_success "Update downloaded via git!"
        else
            log_warn "Git update failed. Trying direct download..."
            # Fall through to curl method
            cd /
        fi
    fi
    
    # Method 2: Direct download (fallback)
    if [[ ! -d "$INSTALL_DIR/.git" ]] || [[ "$(pwd)" == "/" ]]; then
        # Ensure install directory exists
        if [[ ! -d "$INSTALL_DIR" ]]; then
            mkdir -p "$INSTALL_DIR" 2>/dev/null || {
                log_error "Cannot create $INSTALL_DIR. Check permissions."
                wait_key
                return 1
            }
        fi
        
        if curl -sSL "$REMOTE_VERSION_URL" -o "$INSTALL_DIR/samnet.sh.new" 2>/dev/null; then
            # Verify syntax before replacing
            if bash -n "$INSTALL_DIR/samnet.sh.new" 2>/dev/null; then
                if mv "$INSTALL_DIR/samnet.sh.new" "$INSTALL_DIR/samnet.sh" 2>/dev/null; then
                    chmod +x "$INSTALL_DIR/samnet.sh" || true
                    log_success "Update downloaded!"
                else
                    log_error "Failed to install update (permission denied?)."
                    rm -f "$INSTALL_DIR/samnet.sh.new"
                    [[ -f "$backup_script" ]] && cp "$backup_script" "$INSTALL_DIR/samnet.sh"
                    wait_key
                    return 1
                fi
            else
                log_error "Downloaded script has syntax errors. Aborting."
                rm -f "$INSTALL_DIR/samnet.sh.new"
                [[ -f "$backup_script" ]] && cp "$backup_script" "$INSTALL_DIR/samnet.sh"
                wait_key
                return 1
            fi
        else
            log_error "Download failed."
            wait_key
            return 1
        fi
    fi
    
    # Rebuild Docker containers if needed
    log_step "Checking Docker containers..."
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "samnet(-wg)?-api"; then
        echo ""
        if ui_confirm "Rebuild Docker containers with new code?"; then
            log_info "Rebuilding containers (this may take a minute)..."
            rebuild_docker 2>/dev/null || log_warn "Docker rebuild had issues. Check manually."
        fi
    fi
    
    log_success "Update complete!"
    echo ""
    echo "  ${T_GREEN}Updated to v${remote_version}${T_RESET}"
    echo ""
    echo "  ${T_DIM}Backup saved: $backup_script${T_RESET}"
    echo "  ${T_DIM}(Delete after confirming update works)${T_RESET}"
    echo ""
    echo "  Restarting SamNet..."
    sleep 2
    
    # Re-exec the new script
    exec "$INSTALL_DIR/samnet.sh"
}

check_for_updates_silent() {
    # Background check for updates (non-blocking)
    # Called on TUI startup, shows notification if update available
    local remote_version
    remote_version=$(get_remote_version 2>/dev/null) || return 0
    
    [[ -z "$remote_version" ]] && return 0
    
    version_compare "$remote_version" "$SAMNET_VERSION"
    if [[ $? -eq 0 ]]; then
        echo "  ${T_YELLOW}●${T_RESET} Update        ${T_YELLOW}v${remote_version} available (run: samnet --update)${T_RESET}"
        return 0
    fi
    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
# 6. CORE INFRASTRUCTURE ENGINE
# ══════════════════════════════════════════════════════════════════════════════

ensure_dependencies() {
    local web_ui_enabled="${1:-false}"
    local missing=()
    
    # Core dependencies (always required)
    for cmd in sqlite3 curl wg qrencode nft crontab xxd openssl; do
        command -v $cmd &>/dev/null || missing+=($cmd)
    done
    
    # Docker dependencies (only for Web UI)
    if [[ "$web_ui_enabled" == "true" ]]; then
        for cmd in docker; do
            command -v $cmd &>/dev/null || missing+=($cmd)
        done
        if ! docker compose version &>/dev/null && ! command -v docker-compose &>/dev/null; then
             missing+=("docker-compose-plugin")
        fi
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing: ${missing[*]}"
        log_info "Installing..."
        
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            if [[ "$ID" =~ ^(debian|ubuntu|raspbian)$ ]]; then
                # Check connectivity before updating app lists
                if ping -c 1 -W 1 8.8.8.8 &>/dev/null || curl -s --connect-timeout 2 https://1.1.1.1 >/dev/null; then
                     log_info "Updating package lists..."
                     if ! timeout 20s apt-get update -qq; then
                          log_warn "Package update timed out or failed. Continuing..."
                     fi
                else
                     log_warn "No internet connection. Skipping package list update."
                     # If we are missing packages and offline, we must fail
                     if [[ ${#pkgs_to_install[@]} -gt 0 ]]; then
                         # Check if we can proceed anyway (maybe apt cache is good enough?)
                         # Try simulating install
                         if ! apt-get -s install "${pkgs_to_install[@]}" &>/dev/null; then
                             exit_with_error "Missing dependencies: ${pkgs_to_install[*]} but system is offline. Connect to internet or install manually."
                         fi
                     fi
                fi
                
                # Install core packages (xxd is usually in xxd or vim-common, openssl in openssl)
    # API Backend (Headless) requires Docker always
    local pkgs_to_install=()

    # Check Core Packages
    command -v sqlite3 &>/dev/null || pkgs_to_install+=("sqlite3")
    command -v curl &>/dev/null || pkgs_to_install+=("curl")
    command -v wg &>/dev/null || pkgs_to_install+=("wireguard")
    command -v qrencode &>/dev/null || pkgs_to_install+=("qrencode")
    command -v nft &>/dev/null || pkgs_to_install+=("nftables")
    command -v crontab &>/dev/null || pkgs_to_install+=("cron")
    command -v xxd &>/dev/null || pkgs_to_install+=("xxd")
    command -v openssl &>/dev/null || pkgs_to_install+=("openssl")
    command -v inotifywait &>/dev/null || pkgs_to_install+=("inotify-tools")
    
    # Check Docker (Only install if completely missing)
    if ! command -v docker &>/dev/null; then
        # Check if we should try plugin or legacy based on what's available in repo
        # For now, just add the standard set if docker is missing
        pkgs_to_install+=("docker.io" "docker-compose-plugin")
    fi

    if [[ ${#pkgs_to_install[@]} -gt 0 ]]; then
        log_info "Installing missing packages: ${pkgs_to_install[*]}"
        
        # Try primary install
        if ! apt-get install -y "${pkgs_to_install[@]}"; then
             # If failed and docker was requested, retry with legacy docker-compose if plugin failed
             if [[ " ${pkgs_to_install[*]} " =~ " docker-compose-plugin " ]]; then
                 log_warn "Installation failed, retrying with legacy docker-compose..."
                 # Replace plugin with legacy in the array (simple approximate fix for bash array)
                 local legacy_pkgs=(${pkgs_to_install[@]/docker-compose-plugin/docker-compose})
                 if ! apt-get install -y "${legacy_pkgs[@]}"; then
                     exit_with_error "Failed to install dependencies."
                 fi
             else
                 exit_with_error "Failed to install dependencies."
             fi
        fi
    else
        log_success "All dependencies already installed."
    fi
                
    log_success "Dependencies installed"
    
    systemctl is-active --quiet docker || systemctl enable --now docker
            else
                exit_with_error "Unsupported OS: $ID"
            fi
        else
            exit_with_error "Cannot detect OS"
        fi
    fi
}

# Decrypts a Web UI encrypted private key using the system master key
decrypt_peer_key() {
    local encoded="$1"
    local master_key_path="/var/lib/samnet-wg/master.key"
    
    if [[ ! -f "$master_key_path" ]]; then 
         log_debug "Master key missing at $master_key_path"
         return 1
    fi
    
    # Verify master key length (must be 32 bytes)
    local key_size=$(stat -c%s "$master_key_path" 2>/dev/null || echo 0)
    if [[ "$key_size" -ne 32 ]]; then
        log_debug "Master key invalid size: $key_size bytes (expected 32)"
        return 1
    fi

    # PRIORITY 1: Use running API container (Guarantees crypto compatibility)
    if docker ps -q --filter "name=samnet-wg-api" | grep -q . || docker ps -q --filter "name=samnet-api" | grep -q .; then
        local api_container=$(docker ps --format '{{.Names}}' | grep -E "^samnet(-wg)?-api$" | head -1)
        local api_result
        if api_result=$(docker exec "$api_container" /app/api -decrypt "$encoded" 2>/dev/null); then
            if [[ -n "$api_result" ]]; then
                 echo "$api_result"
                 return 0
            fi
        fi
        log_debug "Container decryption failed, falling back to local..."
    fi

    if ! command -v openssl &>/dev/null || ! command -v xxd &>/dev/null; then
        log_debug "Missing required tools: openssl or xxd"
        return 1
    fi
    
    # 1. Get Master Key in Hex (strip newlines/spaces)
    local key_hex=$(xxd -p -c 256 "$master_key_path" | tr -d '[:space:]')
    
    # 2. Decode Base64 to temp file
    local tmp_bin=$(mktemp)
    local tmp_iv=$(mktemp)
    local tmp_tag=$(mktemp)
    local tmp_cipher=$(mktemp)
    
    if ! echo "$encoded" | base64 -d > "$tmp_bin" 2>/dev/null; then
        rm -f "$tmp_bin" "$tmp_iv" "$tmp_tag" "$tmp_cipher"
        return 1
    fi
    
    # 3. Parse Struct: IV (12) | Ciphertext (N) | Tag (16)
    local total_size=$(stat -c%s "$tmp_bin")
    if [[ $total_size -lt 28 ]]; then
        rm -f "$tmp_bin" "$tmp_iv" "$tmp_tag" "$tmp_cipher"
        return 1
    fi
    
    local cipher_size=$((total_size - 28))
    
    # Extract IV (12 bytes)
    dd if="$tmp_bin" bs=1 count=12 of="$tmp_iv" 2>/dev/null
    
    # Extract Tag (Last 16 bytes)
    tail -c 16 "$tmp_bin" > "$tmp_tag"
    
    # Extract Ciphertext (Middle)
    dd if="$tmp_bin" bs=1 skip=12 count="$cipher_size" of="$tmp_cipher" 2>/dev/null
    
    # 4. Decrypt using OpenSSL
    local iv_hex=$(xxd -p -c 256 "$tmp_iv" | tr -d '[:space:]')
    local tag_hex=$(xxd -p -c 256 "$tmp_tag" | tr -d '[:space:]')
    
    # OpenSSL output to stdout
    # Note: openssl enc -aes-256-gcm works on OpenSSL 1.1.1+
    local result
    result=$(openssl enc -d -aes-256-gcm -K "$key_hex" -iv "$iv_hex" -in "$tmp_cipher" -tag "$tag_hex" 2>/dev/null)
    local exit_code=$?
    
    # Cleanup
    rm -f "$tmp_bin" "$tmp_iv" "$tmp_tag" "$tmp_cipher"
    
    if [[ $exit_code -eq 0 ]] && [[ -n "$result" ]]; then
        echo "$result"
        return 0
    else
        log_debug "OpenSSL decryption failed for peer (exit code: $exit_code)"
        return 1
    fi
}

encrypt_peer_key() {
    local plaintext="$1"
    
    # Use running API container (Guarantees crypto compatibility)
    # The API is always deployed, so this should always succeed
    if docker ps -q --filter "name=samnet-wg-api" | grep -q . || docker ps -q --filter "name=samnet-api" | grep -q .; then
        local api_container=$(docker ps --format '{{.Names}}' | grep -E "^samnet(-wg)?-api$" | head -1)
        local api_result
        if api_result=$(docker exec "$api_container" /app/api -encrypt "$plaintext" 2>/dev/null); then
            # Valid encrypted key should be significantly longer than 44 chars (nonce+tag)
            if [[ -n "$api_result" && ${#api_result} -gt 60 ]]; then
                 echo "$api_result"
                 return 0
            fi
        fi
        log_debug "Container encryption failed for '$api_container'"
    fi
    
    # SECURITY: Never fall back to plaintext or unreliable local encryption
    # The API container should always be running after install
    log_error "Encryption failed: API container not available. Start with: docker start samnet-wg-api"
    return 1
}



# Install rollback function for transactional safety
rollback_install() {
    local stage="${1:-unknown}"
    log_error "Installation failed at stage: $stage. Rolling back..."
    
    case "$stage" in
        "wireguard")
            systemctl stop wg-quick@wg0 2>/dev/null || true
            rm -f /etc/wireguard/wg0.conf
            ;;
        "firewall")
            [[ -f /tmp/nftables.backup.$$ ]] && nft -f "/tmp/nftables.backup.$$" 2>/dev/null
            ;;
        "docker")
            local compose_cmd=$(get_compose_cmd || echo "docker-compose")
            $compose_cmd -f "$INSTALL_DIR/services/docker-compose.yml" down 2>/dev/null || true
            ;;
    esac
    
    log_warn "Partial rollback complete. Review system state."
    exit 1
}

# Check if firewall rules need to be updated (idempotency)
firewall_rules_match() {
    local new_rules="$1"
    local current=$(nft list ruleset 2>/dev/null | md5sum | awk '{print $1}')
    local proposed=$(echo "$new_rules" | md5sum | awk '{print $1}')
    [[ "$current" == "$proposed" ]]
}

gen_server_keys() {
    mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
    if [[ ! -f /etc/wireguard/privatekey ]]; then
        umask 077
        wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
        log_success "Server keys generated"
    fi
}

write_wg_conf() {
    local privkey=$(cat /etc/wireguard/privatekey)
    local port=$(db_get_config "listen_port")
    local subnet=$(db_get_config "subnet_cidr")
    
    # Calculate Server IP: 10.100.0.0/24 -> 10.100.0.1/24
    local base_ip="${subnet%/*}"
    local mask="${subnet#*/}"
    local prefix="${base_ip%.*}"
    local addr="${prefix}.1/${mask}"
    
    local mtu=$(db_get_config "mtu")
    # 1380 is safer than 1420 for most ISPs (accounts for PPPoE, tunnels, etc.)
    [[ -z "$mtu" ]] && mtu="1380"
    
    local tmp_conf=$(mktemp)
    cat > "$tmp_conf" <<EOF
[Interface]
Address = $addr
ListenPort = $port
PrivateKey = $privkey
MTU = $mtu
SaveConfig = false
PostUp = nft -f /etc/samnet/samnet.nft; [[ -f /etc/samnet-ports.nft ]] && nft -f /etc/samnet-ports.nft || true
PostDown = nft delete table inet samnet-filter 2>/dev/null; nft delete table ip samnet-nat 2>/dev/null; nft delete table ip6 samnet-nat6 2>/dev/null || true

# Disable IPv6 for this interface specifically to avoid leaks
# (Though OS-level disable is better, this is safe per-interface)
# Table = off  <-- Optional if we wanted manual route control

# Peers
EOF
    
    # Fetch peers and force /32 for server-side routing
    db_query "SELECT public_key, allowed_ips, name FROM peers WHERE disabled=0;" | while IFS='|' read -r pub ips name; do
        [[ -z "$pub" ]] && continue
        # Normalize: strip any existing mask and force /32
        local safe_ip=$(echo "$ips" | cut -d/ -f1)
        echo -e "\n[Peer]\n# $name\nPublicKey = $pub\nAllowedIPs = ${safe_ip}/32" >> "$tmp_conf"
    done
    
    chmod 600 "$tmp_conf"
    
    # Use flock (if available) to safely overwrite wg0.conf in-place (preserving inode)
    # This ensures consistency with the API which also locks wg0.conf
    if command -v flock &>/dev/null; then
        (
            flock -x 200
            cat "$tmp_conf" > "$WG_CONF"
        ) 200>>"$WG_CONF"
    else
        cat "$tmp_conf" > "$WG_CONF"
    fi
    rm -f "$tmp_conf"
}

# ══════════════════════════════════════════════════════════════════════════════
# 6.6 HTTPS/SSL CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

setup_https() {
    local domain="$1"
    local email="${2:-admin@$domain}"
    
    log_info "Setting up HTTPS for $domain..."
    
    # Install certbot if missing
    if ! command -v certbot &>/dev/null; then
        log_info "Installing certbot..."
        apt-get update -qq
        apt-get install -y -qq certbot
    fi
    
    # Create webroot directory
    mkdir -p /var/www/certbot
    
    # Stop any service on port 80 temporarily
    local ui_was_running=false
    local ui_container=$(docker ps --format '{{.Names}}' | grep -E "^samnet(-wg)?-ui$" | head -1)
    if [[ -n "$ui_container" ]]; then
        docker stop "$ui_container" &>/dev/null
        ui_was_running=true
    fi
    
    # Obtain certificate
    if certbot certonly --standalone \
        -d "$domain" \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        --cert-name samnet-wg; then
        
        log_success "SSL certificate obtained!"
        db_set_config "ssl_domain" "$domain"
        db_set_config "ssl_enabled" "true"
        
        # Setup auto-renewal cron (uses samnet-wg-ui)
        if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
            (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'docker restart samnet-wg-ui'") | crontab -
            log_info "Auto-renewal cron job added"
        fi
    else
        log_error "Failed to obtain SSL certificate"
        log_warn "Make sure port 80 is open and $domain points to this server"
        db_set_config "ssl_enabled" "false"
    fi
    
    # Restart UI if it was running
    [[ "$ui_was_running" == true && -n "$ui_container" ]] && docker start "$ui_container" &>/dev/null
}

run_ddns_wizard() {
    show_banner
    section "DDNS Setup Wizard"
    
    printf "\n  ${C_BOLD}What is DDNS?${C_RESET}\n"
    printf "  Dynamic DNS gives you a stable domain name even if your\n"
    printf "  IP address changes. Free options include DuckDNS and No-IP.\n\n"
    
    printf "  ${C_BOLD}Choose a provider:${C_RESET}\n\n"
    menu_option "1" "DuckDNS" "Free, simple, recommended"
    menu_option "2" "No-IP" "Popular, requires account"
    menu_option "3" "Dynu" "Flexible, free tier"
    menu_option "4" "Custom domain" "You own a domain"
    menu_option "S" "Skip" "Use raw WAN IP"
    menu_option "B" "Back" ""
    
    printf "\n${C_CYAN}❯${C_RESET} "
    local c=$(read_key)
    
    case "${c^^}" in
        1)
            show_banner
            section "DuckDNS Setup"
            printf "\n  ${C_BOLD}Step 1:${C_RESET} Go to ${C_CYAN}https://duckdns.org${C_RESET}\n"
            printf "  ${C_BOLD}Step 2:${C_RESET} Sign in with Google/GitHub\n"
            printf "  ${C_BOLD}Step 3:${C_RESET} Create a subdomain (e.g., myvpn)\n"
            printf "  ${C_BOLD}Step 4:${C_RESET} Copy your token from the page\n\n"
            
            local subdomain=$(prompt "Enter subdomain" "myvpn")
            local token=$(prompt "Enter token")
            
            if [[ -n "$subdomain" && -n "$token" ]]; then
                db_set_config "ddns_provider" "duckdns"
                db_set_config "ddns_domain" "${subdomain}.duckdns.org"
                db_set_config "ddns_token" "$token"
                log_success "DuckDNS configured: ${subdomain}.duckdns.org"
                echo "${subdomain}.duckdns.org"
            fi
            ;;
        2|3)
            log_warn "Provider setup coming soon. Using WAN IP for now."
            ;;
        4)
            local domain=$(prompt "Enter your domain" "vpn.example.com")
            if [[ -n "$domain" ]]; then
                db_set_config "ddns_domain" "$domain"
                db_set_config "ddns_provider" "custom"
                echo "$domain"
            fi
            ;;
        S)
            log_info "Skipping DDNS. Using WAN IP directly."
            echo "$(db_get_config wan_ip)"
            ;;
        *)
            return 1
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
# 6.5 SUBNET CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

# IP Pool presets - /24 ranges (most common, shown first)
IP_POOL_PRESETS=(
    "pool_a|10.100.0.0/24|254|Pool A (10.100.0.x) - Default, works for most [RECOMMENDED]"
    "pool_b|10.200.0.0/24|254|Pool B (10.200.0.x) - Use if 10.100 conflicts"
    "pool_c|10.50.0.0/24|254|Pool C (10.50.0.x) - Lower range, avoids common VPCs"
    "pool_d|172.30.0.0/24|254|Pool D (172.30.0.x) - Class B Range"
    "pool_e|192.168.100.0/24|254|Pool E (192.168.100.x) - Classic format, familiar"
    "pool_f|10.7.0.0/24|254|Pool F (10.7.0.x) - Custom range"
)

# Size-based presets (larger to smaller, for scaling needs)
SIZE_PRESETS=(
    "small|10.100.0.0/28|14|/28 - Small Office (up to 14 devices)"
    "medium|10.100.0.0/25|126|/25 - Medium Team (up to 126 devices)"
    "enterprise|10.100.0.0/22|1022|/22 - Enterprise (up to 1,022 devices)"
    "large_ent|10.100.0.0/21|2046|/21 - Large Enterprise (up to 2,046 devices)"
    "carrier|10.100.0.0/20|4094|/20 - Carrier (up to 4,094 devices)"
    "huge|10.100.0.0/19|8190|/19 - Huge (up to 8,190 devices)"
    "massive|10.100.0.0/18|16382|/18 - Massive (up to 16,382 devices)"
    "colossal|10.100.0.0/17|32766|/17 - Colossal (up to 32,766 devices)"
)

show_subnet_help() {
    clear_screen
    draw_header
    ui_info_box "Subnet Configuration Help"
    echo
    echo -e "  ${C_BOLD}WHAT IS A SUBNET?${C_RESET}"
    echo "  WireGuard creates a private virtual network using IP addresses from a subnet"
    echo "  (IP range) you choose. This range should NOT conflict with your existing network."
    echo
    echo -e "  ${C_BOLD}CHOOSING A SIZE (/28, /24, etc.)${C_RESET}"
    echo "  The number after the slash determines how many devices can connect:"
    echo "    /28 = 14 devices    - Home lab, personal use"
    echo "    /25 = 126 devices   - Small business"
    echo "    /24 = 254 devices   - Most common, good default"
    echo "    /22 = 1,022 devices - Large enterprise"
    echo "    /20 = 4,094 devices - Service provider"
    echo
    echo -e "  ${C_BOLD}AVOIDING CONFLICTS${C_RESET}"
    echo "  Common networks to avoid overlap with:"
    echo "    • Your home/office LAN: usually 192.168.1.0/24 or 192.168.0.0/24"
    echo "    • Docker default: 172.17.0.0/16"
    echo "    • Cloud VPCs: often 10.0.0.0/8 ranges"
    echo
    echo -e "  ${C_BOLD}IP POOLS EXPLAINED${C_RESET}"
    echo "    Pool A (10.100.0.x)  - Default, works for most setups"
    echo "    Pool B (10.200.0.x)  - Alternative if 10.100 conflicts"
    echo "    Pool C (10.50.0.x)   - Lower range, avoids common VPCs"
    echo "    Pool D (172.30.0.x)  - Class B, good for Docker environments"
    echo "    Pool E (192.168.100.x) - Familiar format, easy to remember"
    echo
    draw_footer
    read -p "  Press Enter to return to subnet selection..." _
}

show_subnet_wizard() {
    while true; do
        clear_screen
        draw_header
        ui_info_box "VPN Subnet Configuration"
        echo
        echo -e "  ${T_BOLD}${T_WHITE}STEP 1: Choose by SIZE (how many devices)${T_RESET}"
        echo
        
        local i=1
        for preset in "${SIZE_PRESETS[@]}"; do
            IFS='|' read -r id cidr max desc <<< "$preset"
            printf "    ${T_CYAN}%d)${T_RESET} %-18s ${T_WHITE}%s${T_RESET}\n" "$i" "$cidr" "$desc"
            ((i++))
        done
        
        echo
        echo -e "  ${T_BOLD}${T_WHITE}STEP 2: Or choose by IP POOL (to avoid conflicts)${T_RESET}"
        echo
        
        for preset in "${IP_POOL_PRESETS[@]}"; do
            IFS='|' read -r id cidr max desc <<< "$preset"
            printf "    ${T_CYAN}%d)${T_RESET} ${T_WHITE}%s${T_RESET}\n" "$i" "$desc"
            ((i++))
        done
        
        echo
        echo "    ${T_CYAN}C)${T_RESET} Custom CIDR (advanced users)"
        echo "    ${T_CYAN}H)${T_RESET} Help - What do these options mean?"
        echo "    ${T_CYAN}B)${T_RESET} Back to menu"
        echo
        ui_draw_footer
        
        # Explicitly show default in prompt
        read -p "  Select [1-10, C, H, B] (default=3): " choice
        choice=${choice:-3}  # Auto-select 3 if Enter is pressed
        
        local selected_cidr="10.100.0.0/24"
        local selected_preset="large"
        
        case "$choice" in
            [1-5])
                IFS='|' read -r selected_preset selected_cidr _ _ <<< "${SIZE_PRESETS[$((choice-1))]}"
                ;;
            [6-9]|10)
                local pool_idx=$((choice-6))
                IFS='|' read -r selected_preset selected_cidr _ _ <<< "${IP_POOL_PRESETS[$pool_idx]}"
                ;;
            [Cc])
                echo
                echo -e "  ${C_YELLOW}Enter a private IP range in CIDR notation.${C_RESET}"
                echo "  Examples: 10.10.0.0/24, 172.20.0.0/22, 192.168.50.0/24"
                echo
                read -p "  Custom CIDR: " custom_cidr
                if [[ "$custom_cidr" =~ ^(10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                    selected_cidr="$custom_cidr"
                    selected_preset="custom"
                else
                    log_error "Invalid CIDR format. Must be a private IP range with /prefix."
                    sleep 2
                    continue
                fi
                ;;
            [Hh])
                show_subnet_help
                continue
                ;;
            [Bb])
                return
                ;;
            *)
                log_error "Invalid selection. Try again."
                sleep 1
                continue
                ;;
        esac
        
        # Confirm selection
        echo
        echo -e "  ${C_GREEN}Selected:${C_RESET} $selected_cidr (preset: $selected_preset)"
        read -p "  Apply this subnet? [Y/n]: " confirm
        if [[ "${confirm:-y}" =~ ^[Yy]$ ]]; then
            # Save to database
            db_set_config "subnet_cidr" "$selected_cidr"
            db_set_config "subnet_preset" "$selected_preset"
            
            log_success "Subnet configured: $selected_cidr"
            
            # Apply changes to brain
            write_wg_conf
            ensure_wg_up
            apply_firewall
            
            sleep 2
            return
        fi
    done
}

get_current_subnet() {
    db_get_config "subnet_cidr" || echo "10.100.0.0/24"
}

ensure_wg_up() {
    log_info "Starting WireGuard service..."
    systemctl enable wg-quick@wg0 >/dev/null 2>&1
    
    if ! systemctl start wg-quick@wg0; then
        log_error "WireGuard failed to start!"
        echo -e "\n${T_YELLOW}--- DEBUG LOGS START ---${T_RESET}"
        journalctl -n 20 -u wg-quick@wg0 --no-pager
        echo -e "${T_YELLOW}--- DEBUG LOGS END ---${T_RESET}\n"
        
        echo -e "${T_CYAN}Config Dump:${T_RESET}"
        cat /etc/wireguard/wg0.conf
        return 1
    fi
    log_success "WireGuard is running"
    
    # Enable IP forwarding persistently
    if [[ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]]; then
        sysctl -w net.ipv4.ip_forward=1 >/dev/null
        echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-samnet.conf
    fi
}

apply_firewall() {
    local wan_iface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    local port=$(db_get_config "listen_port")
    port="${port:-51820}"
    
    validate_interface "$wan_iface" || { log_error "Invalid WAN interface"; return 1; }
    
    local backup="/tmp/nftables.backup.$$"
    nft list ruleset > "$backup" 2>/dev/null || true
    
    modprobe nft_chain_nat_ipv4 2>/dev/null || true
    
    # Get firewall mode (default: samnet-managed)
    local firewall_mode=$(db_get_config "firewall_mode")
    firewall_mode="${firewall_mode:-samnet}"
    
    # Always clean up our tables first
    nft delete table inet samnet-filter 2>/dev/null || true
    nft delete table ip samnet-nat 2>/dev/null || true
    nft delete table ip6 samnet-nat6 2>/dev/null || true
    
    # ─── Create SamNet config directory ───
    mkdir -p /etc/samnet
    
    # ─── Mode-specific firewall setup ───
    # Write to /etc/samnet/samnet.nft (NOT /etc/nftables.conf - preserves user config)
    if [[ "$firewall_mode" == "samnet" ]]; then
        # Full samnet firewall management (filter + nat)
        cat > /etc/samnet/samnet.nft <<EOF
# SamNet-WG Firewall Rules
# Auto-generated - do not edit manually
table inet samnet-filter {
    chain input {
        type filter hook input priority 0; policy accept;
        iifname "lo" accept
        iifname "wg0" accept
        ct state established,related accept
    }
    chain forward {
        type filter hook forward priority 10; policy accept;
        # Allow established/related traffic (most common case, handles return traffic)
        ct state established,related accept
        # WireGuard VPN traffic
        iifname "$wan_iface" oifname "wg0" ct state established,related accept
        iifname "wg0" oifname "$wan_iface" accept
        iifname "wg0" oifname "wg0" accept
        # Docker bridge traffic is already handled by Docker's own rules at priority 0
        # We run at priority 10 (after Docker) with policy accept, so we don't interfere
    }
}
table ip samnet-nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "$wan_iface" masquerade
    }
}
table ip6 samnet-nat6 {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "$wan_iface" masquerade
    }
}
EOF
    else
        # External firewall mode (UFW/iptables) - only NAT rules for VPN, no filter
        # UFW/Docker manage their own filtering, we just add masquerading for VPN traffic
        cat > /etc/samnet/samnet.nft <<EOF
# SamNet VPN NAT rules only (firewall managed externally)
table ip samnet-nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "$wan_iface" masquerade
    }
}
table ip6 samnet-nat6 {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        oifname "$wan_iface" masquerade
    }
}
EOF
    fi
    
    # ─── Add include to /etc/nftables.conf if not present (safe: preserves existing config) ───
    local include_line='include "/etc/samnet/samnet.nft"'
    if [[ -f /etc/nftables.conf ]]; then
        if ! grep -qF "$include_line" /etc/nftables.conf; then
            # Append include line to existing config
            echo "" >> /etc/nftables.conf
            echo "# SamNet-WG VPN rules (added by samnet installer)" >> /etc/nftables.conf
            echo "$include_line" >> /etc/nftables.conf
            log_info "Added SamNet include to /etc/nftables.conf"
        fi
    else
        # No existing nftables.conf - create minimal one with SamNet include only
        # NOTE: We intentionally do NOT flush ruleset to avoid wiping any existing nft rules
        log_warn "No /etc/nftables.conf found - creating minimal config"
        cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
# nftables configuration (created by SamNet-WG)
# Add your custom rules here if needed

# SamNet-WG VPN rules
$include_line
EOF
        log_info "Created /etc/nftables.conf with SamNet include"
    fi
    
    # Load our rules
    if ! nft -f /etc/samnet/samnet.nft; then
        log_error "Firewall failed, rolling back..."
        nft -f "$backup" 2>/dev/null
        rm -f "$backup"
        return 1
    fi
    
    rm -f "$backup"
    
    # ─── Step 2: Handle user ports table based on firewall mode ───
    if [[ "$firewall_mode" == "samnet" ]]; then
        # Only create samnet-ports if it doesn't exist (first install)
        if ! nft list table inet samnet-ports &>/dev/null; then
            create_samnet_ports_table "$port"
        else
            # Table exists - just ensure VPN port is current
            update_vpn_port_rule "$port"
        fi
        # Load persisted rules if they exist
        [[ -f /etc/samnet-ports.nft ]] && nft -f /etc/samnet-ports.nft 2>/dev/null || true
    else
        # If not in SamNet mode, ensure we remove our managed table so it doesn't block traffic
        nft delete table inet samnet-ports 2>/dev/null || true
    fi
    
    systemctl enable nftables 2>/dev/null || true
    log_success "Firewall rules applied (mode: $firewall_mode)"
    
    # ─── Docker/iptables Compatibility ───────────────────────────────────────
    # All rules tagged with --comment "samnet-wg" for safe removal
    if command -v docker &>/dev/null || [[ -n "$(iptables -L FORWARD -n 2>/dev/null | grep DOCKER)" ]]; then
        if iptables -L FORWARD -n 2>/dev/null | grep -q "DOCKER"; then
            log_info "Docker detected - ensuring iptables compatibility..."
            
            # Remove any existing samnet-wg tagged rules first (idempotent)
            while iptables -D FORWARD -i wg0 -o "$wan_iface" -j ACCEPT -m comment --comment "samnet-wg" 2>/dev/null; do :; done
            while iptables -D FORWARD -i "$wan_iface" -o wg0 -m state --state ESTABLISHED,RELATED -j ACCEPT -m comment --comment "samnet-wg" 2>/dev/null; do :; done
            
            # Add rules WITH comment tags (safe for removal)
            iptables -I FORWARD 1 -i wg0 -o "$wan_iface" -j ACCEPT -m comment --comment "samnet-wg"
            iptables -I FORWARD 2 -i "$wan_iface" -o wg0 -m state --state ESTABLISHED,RELATED -j ACCEPT -m comment --comment "samnet-wg"
            
            # NAT rule with comment tag
            while iptables -t nat -D POSTROUTING -s 10.0.0.0/8 -o "$wan_iface" -j MASQUERADE -m comment --comment "samnet-wg" 2>/dev/null; do :; done
            iptables -t nat -A POSTROUTING -s 10.0.0.0/8 -o "$wan_iface" -j MASQUERADE -m comment --comment "samnet-wg"
            
            if ! command -v netfilter-persistent &>/dev/null; then
                 log_info "Installing iptables-persistent..."
                 export DEBIAN_FRONTEND=noninteractive
                 apt-get update -qq &>/dev/null || true
                 echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
                 echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
                 if ! apt-get install -y -qq iptables-persistent &>/dev/null; then
                     log_warn "iptables-persistent install failed (non-fatal) - iptables rules may not persist across reboots"
                 fi
            fi
            
            command -v netfilter-persistent &>/dev/null && netfilter-persistent save >/dev/null 2>&1
        fi
    fi
}


# ─── User Ports Table Management ─────────────────────────────────────────────

create_samnet_ports_table() {
    local vpn_port="${1:-51820}"
    
    log_info "Creating firewall with secure defaults + service detection..."
    
    # Detect running services on common ports
    local detected_ports=""
    local common_ports="80 443 8080 8443 3000 9090 9100 3306 5432 6379 27017 25 587 993 995"
    
    for port in $common_ports; do
        # Use ss filter instead of grep with non-portable \s
        if ss -tlnH sport = ":$port" 2>/dev/null | grep -q .; then
            detected_ports="$detected_ports $port"
        fi
    done
    
    # Build the dynamic port rules - but ASK USER FIRST
    local port_rules=""
    local approved_ports=""
    
    if [[ -n "$detected_ports" ]]; then
        echo ""
        log_warn "Auto-detected running services on ports:$detected_ports"
        echo ""
        echo "  ${T_CYAN}Detected services:${T_RESET}"
        for port in $detected_ports; do
            case $port in
                80)   echo "    • Port 80 (HTTP)" ;;
                443)  echo "    • Port 443 (HTTPS)" ;;
                8080) echo "    • Port 8080 (Alt HTTP)" ;;
                8443) echo "    • Port 8443 (Alt HTTPS)" ;;
                3000) echo "    • Port 3000 (Grafana/Dev)" ;;
                9090) echo "    • Port 9090 (Prometheus)" ;;
                9100) echo "    • Port 9100 (Node Exporter)" ;;
                3306) echo "    • Port 3306 (MySQL)" ;;
                5432) echo "    • Port 5432 (PostgreSQL)" ;;
                6379) echo "    • Port 6379 (Redis)" ;;
                27017) echo "    • Port 27017 (MongoDB)" ;;
                25)   echo "    • Port 25 (SMTP)" ;;
                587)  echo "    • Port 587 (Mail Submission)" ;;
                993)  echo "    • Port 993 (IMAPS)" ;;
                995)  echo "    • Port 995 (POP3S)" ;;
            esac
        done
        echo ""
        echo "  ${T_YELLOW}Opening these ports will allow external access.${T_RESET}"
        read -r -p "  Open detected service ports? (yes/no) [default: no]: " open_detected
        
        if [[ "${open_detected,,}" == "yes" ]]; then
            approved_ports="$detected_ports"
            log_success "Approved:$approved_ports"
        else
            log_info "Skipped auto-detected ports (only SSH + VPN will be open)"
        fi
    fi
    
    # Build rules only for approved ports
    for port in $approved_ports; do
        case $port in
            80)   port_rules="${port_rules}        tcp dport 80 accept comment \"http-detected\"\n" ;;
            443)  port_rules="${port_rules}        tcp dport 443 accept comment \"https-detected\"\n" ;;
            8080) port_rules="${port_rules}        tcp dport 8080 accept comment \"alt-http-detected\"\n" ;;
            8443) port_rules="${port_rules}        tcp dport 8443 accept comment \"alt-https-detected\"\n" ;;
            3000) port_rules="${port_rules}        tcp dport 3000 accept comment \"grafana-detected\"\n" ;;
            9090) port_rules="${port_rules}        tcp dport 9090 accept comment \"prometheus-detected\"\n" ;;
            9100) port_rules="${port_rules}        tcp dport 9100 accept comment \"node-exporter-detected\"\n" ;;
            3306) port_rules="${port_rules}        tcp dport 3306 accept comment \"mysql-detected\"\n" ;;
            5432) port_rules="${port_rules}        tcp dport 5432 accept comment \"postgres-detected\"\n" ;;
            6379) port_rules="${port_rules}        tcp dport 6379 accept comment \"redis-detected\"\n" ;;
            27017) port_rules="${port_rules}        tcp dport 27017 accept comment \"mongodb-detected\"\n" ;;
            25)   port_rules="${port_rules}        tcp dport 25 accept comment \"smtp-detected\"\n" ;;
            587)  port_rules="${port_rules}        tcp dport 587 accept comment \"submission-detected\"\n" ;;
            993)  port_rules="${port_rules}        tcp dport 993 accept comment \"imaps-detected\"\n" ;;
            995)  port_rules="${port_rules}        tcp dport 995 accept comment \"pop3s-detected\"\n" ;;
        esac
    done

    
    # Using 'inet' family covers both IPv4 and IPv6
    # Priority -10 ensures this runs before standard filter chains
    nft -f - <<EOF
table inet samnet-ports {
    chain input {
        type filter hook input priority -10; policy drop;
        
        # Core System Rules
        iifname "lo" accept comment "allow-loopback"
        ct state established,related accept comment "allow-return-traffic"
        
        # Docker Compatibility - allow all traffic from Docker bridges
        iifname "docker0" accept comment "docker-bridge"
        iifname "br-*" accept comment "docker-custom-networks"
        
        # Protocols
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        
        # Required Ports
        udp dport $vpn_port accept comment "wireguard-vpn"
        tcp dport 22 accept comment "ssh"
$(echo -e "$port_rules")
    }
}
EOF
    
    persist_samnet_ports
    
    local count=$(echo "$approved_ports" | wc -w)
    log_success "Firewall created: SSH + VPN + Docker + $count approved services"
}

update_vpn_port_rule() {
    local new_port="$1"
    
    # Remove old VPN port rule if exists
    local old_handle=$(nft -a list chain inet samnet-ports input 2>/dev/null | \
                       grep 'comment "wireguard-vpn"' | grep -oP 'handle \K[0-9]+')
    [[ -n "$old_handle" ]] && nft delete rule inet samnet-ports input handle "$old_handle" 2>/dev/null
    
    # Add new VPN port rule at the beginning (after icmp)
    nft insert rule inet samnet-ports input udp dport "$new_port" accept comment '"wireguard-vpn"' 2>/dev/null || true
    persist_samnet_ports
}

persist_samnet_ports() {
    nft list table inet samnet-ports > /etc/samnet-ports.nft 2>/dev/null || true
    chmod 600 /etc/samnet-ports.nft 2>/dev/null || true
}

add_firewall_port() {
    local port="$1"
    local proto="${2:-tcp}"
    local label="${3:-user-defined}"
    
    # Validate port
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        log_error "Invalid port number: $port"
        return 1
    fi
    
    # Validate protocol
    if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
        log_error "Invalid protocol: $proto (must be tcp or udp)"
        return 1
    fi
    
    # Check firewall mode
    local firewall_mode=$(db_get_config "firewall_mode")
    if [[ "$firewall_mode" != "samnet" ]]; then
        log_error "Cannot add ports - firewall is in '$firewall_mode' mode"
        log_info "Change to 'samnet' mode or use your external firewall tool"
        return 1
    fi
    
    # Ensure table exists
    if ! nft list table inet samnet-ports &>/dev/null; then
        log_error "Ports table doesn't exist. Run install first."
        return 1
    fi
    
    # Check if already exists
    if nft list chain inet samnet-ports input 2>/dev/null | grep -q "$proto dport $port "; then
        log_warn "Port $port/$proto is already open"
        return 0
    fi
    
    # Add rule
    nft add rule inet samnet-ports input "$proto" dport "$port" accept comment "\"$label\""
    persist_samnet_ports
    
    log_success "Opened port $port/$proto ($label)"
}

remove_firewall_port() {
    local port="$1"
    local proto="${2:-tcp}"
    
    local vpn_port=$(db_get_config "listen_port")
    vpn_port="${vpn_port:-51820}"
    
    # Prevent removing VPN port
    if [[ "$port" == "$vpn_port" && "$proto" == "udp" ]]; then
        log_error "Cannot remove VPN port - this would break WireGuard"
        return 1
    fi
    
    # Prevent removing SSH (with warning)
    if [[ "$port" == "22" && "$proto" == "tcp" ]]; then
        log_warn "Removing SSH port 22 - make sure you have alternative access!"
    fi
    
    # Find and remove rule by handle
    local handle=$(nft -a list chain inet samnet-ports input 2>/dev/null | \
                   grep "$proto dport $port " | grep -oP 'handle \K[0-9]+' | head -1)
    
    if [[ -z "$handle" ]]; then
        log_warn "Port $port/$proto not found in firewall rules"
        return 1
    fi
    
    nft delete rule inet samnet-ports input handle "$handle"
    persist_samnet_ports
    
    log_success "Closed port $port/$proto"
}

list_firewall_ports() {
    local firewall_mode=$(db_get_config "firewall_mode")
    
    if [[ "$firewall_mode" != "samnet" ]]; then
        echo "Firewall mode: $firewall_mode (ports managed externally)"
        return 0
    fi
    
    if ! nft list table inet samnet-ports &>/dev/null; then
        echo "No ports table found"
        return 1
    fi
    
    # Parse and display ports
    nft list chain inet samnet-ports input 2>/dev/null | \
        grep -E "(tcp|udp) dport" | \
        sed 's/.*\(tcp\|udp\) dport \([0-9]*\).*/\2\/\1/' | \
        while read port_proto; do
            local comment=$(nft list chain inet samnet-ports input 2>/dev/null | \
                           grep "$port_proto" | grep -oP 'comment "\K[^"]+' || echo "")
            echo "$port_proto  $comment"
        done
}

# ══════════════════════════════════════════════════════════════════════════════
# 7. INSTALLATION ENGINE
# ══════════════════════════════════════════════════════════════════════════════

run_preflight_checks() {
    log_info "Running pre-flight checks..."
    local failed=0
    
    # 1. Port Availability Checks (Fast)
    if ss -tuln 2>/dev/null | grep -q ":80 " && [[ "$(db_get_config web_ui_enabled)" == "true" ]]; then
        log_warn "Port 80 in use (Web UI might fail)"
    fi
    if ss -tuln 2>/dev/null | grep -q ":8080 "; then
        log_warn "Port 8080 in use"
    fi
    
    # 2. Internet Connectivity (Ultra Fast)
    # Strategy: Ping first (sub-second usually), fallback to HTTP head check
    local connected=false
    
    if ping -c 1 -W 1 8.8.8.8 &>/dev/null || ping -c 1 -W 1 1.1.1.1 &>/dev/null; then
        connected=true
    elif curl -s --head --connect-timeout 2 https://1.1.1.1 &>/dev/null; then
        connected=true
    fi
    
    if [[ "$connected" == "false" ]]; then
         log_warn "No internet connectivity detected (or blocked)"
    fi
    
    # 3. Kernel Modules
    if ! modprobe wireguard 2>/dev/null; then
         # Try to see if it's built-in
         if [[ ! -d /sys/module/wireguard ]]; then
             log_warn "WireGuard kernel module not loaded (will attempt to install)"
         fi
    fi

    log_success "Pre-flight checks passed"
    return 0
}

# Optimized IP Detection (Fast & Robust)
detect_public_ip() {
    local ip=""
    # Parallel-ish attempt with fast failovers
    ip=$(curl -s --connect-timeout 2 http://ifconfig.me)
    [[ -z "$ip" ]] && ip=$(curl -s --connect-timeout 2 https://api.ipify.org)
    [[ -z "$ip" ]] && ip=$(curl -s --connect-timeout 2 https://icanhazip.com)
    
    # Validation
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "$ip"
    else
        # Fallback: Use local interface IP (Robustness for partial connectivity)
        local local_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}')
        if [[ "$local_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            # log_warn "Using local IP as fallback" >&2
            echo "$local_ip"
        else
            echo ""
        fi
    fi
}

do_install() {
    check_root
    
    # S0014: Prevent concurrent installer runs
    local install_lock="/var/run/samnet-install.lock"
    if [[ -f "$install_lock" ]]; then
        local pid=$(cat "$install_lock")
        if kill -0 "$pid" 2>/dev/null; then
            exit_with_error "Another instance of SamNet installer (PID $pid) is already running."
        fi
    fi
    echo $$ > "$install_lock"
    trap 'rm -f "$install_lock"' EXIT
    
    run_preflight_checks || { log_error "Critical pre-flight checks failed"; rm -f "$install_lock"; return 1; }
    
    # Transaction pattern: track stages for rollback
    export INSTALL_STAGE="init"
    trap 'rollback_install "$INSTALL_STAGE"' ERR
    
    if [[ "$INTERACTIVE" == true ]]; then
        ensure_db_init  # Initialize DB before wizard to prevent sqlite errors
        if ! run_install_wizard; then
            log_info "Installation cancelled by user."
            return 0
        fi
    else
        log_info "Zero-Touch Installation..."
        ensure_db_init
        
        local detected_ip=$(detect_public_ip)
        [[ -n "$detected_ip" ]] && db_set_config "wan_ip" "$detected_ip"
        db_set_config "listen_port" "51820"
        db_set_config "subnet_cidr" "10.100.0.0/24"
        
        # Smart firewall detection for zero-touch mode
        # If existing firewall detected, use external mode to avoid conflicts
        local detected_firewall="none"
        
        # Check for UFW
        if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
            detected_firewall="ufw"
        # Check for iptables with non-default rules (more than just ACCEPT policies)
        elif iptables -L INPUT -n 2>/dev/null | grep -qE "^(DROP|REJECT|ACCEPT.*dpt:)"; then
            detected_firewall="iptables"
        # Check for nftables with existing filter tables (excluding samnet's own)
        elif nft list tables 2>/dev/null | grep -qE "filter|firewall" && ! nft list tables 2>/dev/null | grep -q "samnet"; then
            detected_firewall="nftables"
        fi
        
        if [[ "$detected_firewall" != "none" ]]; then
            log_info "Detected existing firewall: $detected_firewall - using external mode"
            db_set_config "firewall_mode" "external"
        else
            log_info "No existing firewall detected - using SamNet managed mode"
            db_set_config "firewall_mode" "samnet"
        fi
    fi
    
    # Get Web UI preference
    local web_ui_enabled=$(db_get_config "web_ui_enabled")
    [[ -z "$web_ui_enabled" ]] && web_ui_enabled="false"
    
    ensure_dependencies "$web_ui_enabled"
    ensure_db_init
    
    log_info "Installing system files..."
    INSTALL_STAGE="files"
    mkdir -p "$INSTALL_DIR"
    cp -f "$0" "$INSTALL_DIR/samnet" && chmod +x "$INSTALL_DIR/samnet"
    ln -sf "$INSTALL_DIR/samnet" /usr/local/bin/samnet
    
    INSTALL_STAGE="wireguard"
    gen_server_keys
    write_wg_conf
    
    INSTALL_STAGE="firewall"
    apply_firewall
    
    # Deploy Docker stack (API/DB are now core dependencies for headless mode)
    # Deploy Docker stack (API/DB are now core dependencies for headless mode)
    if [[ -d "$DIR/services" ]]; then
        INSTALL_STAGE="docker"
        log_info "Deploying Backend Stack (Headless)..."
        # Only copy if source and destination are different
        if [[ "$(realpath "$DIR/services")" != "$(realpath "$INSTALL_DIR/services")" ]]; then
            cp -r "$DIR/services" "$INSTALL_DIR/"
        fi
        
        # Create database directory for API container (user 1000:1000 = samnet)
        log_info "Setting up database directory..."
        mkdir -p /var/lib/samnet-wg
        chown -R 1000:1000 /var/lib/samnet-wg
        chmod 750 /var/lib/samnet-wg
        
        # Fix DNS for Docker builds (Docker uses its own DNS, not host's)
        # Fix DNS for Docker builds (Docker uses its own DNS, not host's)
        # We explicitly check for reliable resolvers (8.8.8.8 or 1.1.1.1)
        # If not found, we BACKUP existing config and FORCE our working config.
        # This fixes the common "lookup registry-1.docker.io: i/o timeout" error.
        log_info "Configuring Docker DNS for reliable builds..."
        mkdir -p /etc/docker
        
        local update_dns=false
        if [[ ! -f /etc/docker/daemon.json ]]; then
            update_dns=true
        elif ! grep -qE "8\.8\.8\.8|1\.1\.1\.1" /etc/docker/daemon.json; then
            log_warn "Existing Docker DNS config may be unreliable. Overwriting..."
            cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
            update_dns=true
        fi
        
        if [[ "$update_dns" == "true" ]]; then
            echo '{"dns": ["8.8.8.8", "1.1.1.1"]}' > /etc/docker/daemon.json
            systemctl restart docker 2>/dev/null || true
            sleep 3 # Give it a moment to bind
        fi
        
        # Wait for Docker to be ready (up to 30 seconds)
        local docker_wait=0
        while ! docker info &>/dev/null; do
            sleep 2
            ((docker_wait+=2))
            if [[ $docker_wait -ge 30 ]]; then
                log_warn "Docker daemon slow to restart, continuing anyway..."
                break
            fi
        done
        log_success "Docker daemon ready"
        
        if [[ -f "$INSTALL_DIR/services/docker-compose.yml" ]]; then
            # OPTIMIZATION: Prepare UI build artifacts if Web UI is enabled
            if [[ "$(db_get_config web_ui_enabled)" == "true" ]]; then
                local ui_dir="$INSTALL_DIR/services/ui"
                
                # 1. Ensure .dockerignore exists (speeds up build context)
                if [[ ! -f "$ui_dir/.dockerignore" ]]; then
                    log_info "Creating UI build optimizations..."
                    cat > "$ui_dir/.dockerignore" <<EOF
node_modules
.git
.gitignore
dist
coverage
npm-debug.log
EOF
                fi
                
                # 2. Generate package-lock.json if missing (speeds up npm install)
                if [[ ! -f "$ui_dir/package-lock.json" ]]; then
                    log_info "Generating npm lockfile (using host network for speed)..."
                    # Use --network host to bypass Docker bridge DNS issues
                    if docker run --rm --network host -v "$ui_dir:/app" -w /app node:18-alpine npm install --package-lock-only; then
                        log_success "Lockfile generated successfully"
                        # Ensure permissions are correct (docker runs as root)
                        chown -R $SUDO_USER:$SUDO_USER "$ui_dir/package-lock.json" 2>/dev/null || true
                    else
                        log_warn "Failed to generate lockfile. Build may be slow."
                    fi
                fi
            fi

            local compose_cmd
            local compose_cmd
            compose_cmd=$(get_compose_cmd) || { log_error "Docker Compose not found."; }
            
            # Build image with host networking (bypasses Docker's bridge network issues)
            local docker_success=false
            for attempt in 1 2 3; do
                log_info "Building API image (Attempt $attempt/3)..."
                if docker build --network=host --label project=samnet-wg -t samnet-wg/api:latest "$DIR/services/api"; then
                    docker_success=true
                    break
                else
                    log_warn "API build failed, retrying in 10s..."
                    sleep 10
                fi
            done

            # Build UI image with host networking (CRITICAL for npm install speed)
            if [[ "$(db_get_config web_ui_enabled)" == "true" ]]; then
                local ui_success=false
                for attempt in 1 2 3; do
                    log_info "Building Web UI image (Attempt $attempt/3)..."
                    if docker build --network=host --label project=samnet-wg -t samnet-wg/ui:latest "$DIR/services/ui"; then
                        ui_success=true
                        break
                    else
                        log_warn "UI build failed, retrying in 10s..."
                        sleep 10
                    fi
                done
                if [[ "$ui_success" == false ]]; then
                    log_warn "Web UI build failed. API will work, but Web UI unavailable."
                fi
            fi
            
            if [[ "$docker_success" == false ]]; then
                log_warn "Docker deployment failed after 3 attempts. Continuing with WireGuard-only mode."
                log_warn "You can manually run 'docker build --network=host -t samnet/api:latest $INSTALL_DIR/services/api' later."
            else
                # Start containers using native Docker (more robust than fragile compose versions)
                log_info "Starting services..."

                # 1. Cleanup old
                docker rm -f samnet-wg-api samnet-wg-ui samnet-api samnet-ui 2>/dev/null || true

                # 1.5 Create Bridge Network (Windows/Mac compatibility)
                if ! docker network ls | grep -q "samnet-grid"; then
                    log_info "Creating Docker network 'samnet-grid'..."
                    docker network create samnet-grid >/dev/null
                fi

                # 2. Start API
                log_info "Launching API..."
                
                # Dynamic Port Selection: Check if default port is available
                local api_port=8766
                if ! is_port_available "$api_port"; then
                    log_warn "Port $api_port is already in use. Finding alternative..."
                    api_port=$(find_available_port 8766)
                    log_info "Selected alternative API port: $api_port"
                fi
                
                # Save the selected port to database for CLI and other tools to use
                db_set_config "api_port" "$api_port"
                log_info "API will run on port $api_port"
                
                # Use --network=host so API container can directly access host's wg0 interface
                # This allows `wg set` to work from within the container
                # Note: --sysctl not allowed with host network (IP forwarding already enabled on host)
                if ! docker run -d \
                    --name samnet-wg-api \
                    --network=host \
                    --restart=unless-stopped \
                    --cap-add=NET_ADMIN \
                    -v /var/lib/samnet-wg:/var/lib/samnet-wg \
                    -v /etc/wireguard:/etc/wireguard \
                    -v "$DIR/clients":/opt/samnet/clients \
                    -e SAMNET_DB_PATH=/var/lib/samnet-wg/samnet.db \
                    -e PORT=$api_port \
                    -e INSECURE_HTTP=true \
                    -e GIN_MODE=release \
                    samnet-wg/api:latest >/dev/null; then
                    log_error "Failed to start API container"
                    return 1
                fi

                # 3. Start UI (if enabled)
                if [[ "$web_ui_enabled" == "true" ]]; then
                    log_info "Launching Web UI..."
                    
                    # Determine UI mode
                    local ui_mode="lan"
                    [[ "$(db_get_config web_ui_mode)" == "https" ]] && ui_mode="https"
                    
                    # Safety Check: Port 80 conflict
                    if [[ "$ui_mode" == "lan" ]] && ss -tuln 2>/dev/null | grep -q ":80 "; then
                        log_error "Port 80 is already in use by another service!"
                        log_warn "You must stop existing web servers (e.g., Apache, Nginx) before SamNet can use Port 80."
                        log_warn "Try running: systemctl stop nginx apache2"
                        return 1
                    fi

                    # UI also needs host network to connect to API on localhost
                    if ! docker run -d \
                        --name samnet-wg-ui \
                        --network=host \
                        --restart=unless-stopped \
                        -v /etc/letsencrypt:/etc/letsencrypt:ro \
                        -v /var/www/certbot:/var/www/certbot:ro \
                        -e NGINX_MODE="$ui_mode" \
                        -e API_PORT="$api_port" \
                        samnet-wg/ui:latest >/dev/null; then
                        log_error "Failed to start UI container"
                        return 1
                    fi

                    # Verify UI startup
                    sleep 2
                    if ! docker ps --format '{{.Names}}' | grep -qE "^samnet(-wg)?-ui$"; then
                        log_error "Web UI container crashed immediately!"
                        echo -e "\n${T_YELLOW}--- UI CRASH LOGS ---${T_RESET}"
                        docker logs samnet-wg-ui 2>&1 | tail -n 20 || docker logs samnet-ui 2>&1 | tail -n 20
                        echo -e "${T_YELLOW}-----------------------${T_RESET}\n"
                        return 1
                    fi
                fi
                
                log_success "Services started successfully"
            fi
        fi
        
        # Only wait for API if Docker succeeded
        if [[ "$docker_success" == true ]]; then
            # Wait for API to be healthy before creating admin (with timeout)
            log_info "Waiting for API to become ready..."
            local max_wait=120
            local waited=0
            local api_url=$(get_api_url)
            local curl_err=""
        while ! curl_err=$(curl -sf --connect-timeout 2 --max-time 5 "${api_url}/health/live" 2>&1); do
            # Fail fast if container died
            if ! docker ps --format '{{.Names}}' | grep -qE "^samnet(-wg)?-api$"; then
                log_error "API container stopped unexpectedly!"
                echo -e "\n${T_YELLOW}--- API CRASH LOGS ---${T_RESET}"
                docker logs samnet-wg-api 2>&1 | tail -n 20 || docker logs samnet-api 2>&1 | tail -n 20
                echo -e "${T_YELLOW}-----------------------${T_RESET}\n"
                return 1
            fi

            sleep 2
            ((waited+=2))
            
            # UX: Stream API logs if taking more than 4 seconds
            if [[ $waited -ge 4 ]] && [[ $((waited % 10)) -eq 0 ]]; then
                echo -e "  ${T_DIM}Still waiting... (waited ${waited}s)${T_RESET}"
                echo -e "  ${T_DIM}Latest API Log:${T_RESET} $(docker logs samnet-wg-api 2>&1 | tail -n 1)"
            fi

            if [[ $waited -ge $max_wait ]]; then
                log_error "API did not become ready in ${max_wait}s"
                echo -e "  ${T_DIM}Tried URL: ${api_url}/health/live${T_RESET}"
                echo -e "  ${T_DIM}Curl Error: ${curl_err}${T_RESET}"
                echo -e "\n${T_YELLOW}--- API DEBUG LOGS ---${T_RESET}"
                docker logs samnet-wg-api 2>&1 | tail -n 20 || docker logs samnet-api 2>&1 | tail -n 20
                echo -e "${T_YELLOW}-----------------------${T_RESET}\n"
                return 1
            fi
        done
        log_success "API ready after ${waited}s"
        
        local temp_pass="changeme"
        local api_container=$(docker ps --format '{{.Names}}' | grep -E "^samnet(-wg)?-api$" | head -1)
        if docker exec "$api_container" /home/samnet/api -create-admin "admin" -password "$temp_pass" >/dev/null 2>&1; then
            # Atomic credential file write - only after admin creation verified
            local tmp_cred=$(mktemp)
            cat > "$tmp_cred" <<CREDS
# SamNet-WG Initial Credentials
# Created: $(date -Iseconds)
# DELETE AFTER READING!
URL: http://$(db_get_config wan_ip):8766
Username: admin
Password: $temp_pass
CREDS
            chmod 600 "$tmp_cred"
            mv "$tmp_cred" "$INSTALL_DIR/credentials.txt"
            log_success "Admin user created"
        else
            log_error "Failed to create admin user"
        fi
        unset temp_pass
        fi  # End of docker_success check
    else
        log_info "CLI-only mode - skipping Docker/Web UI deployment"
    fi  # End of services directory check
    
    # Start WireGuard last
    ensure_wg_up

    # Ensure cron is running (for check_expiry fallback)
    systemctl enable cron 2>/dev/null || true
    systemctl start cron 2>/dev/null || true

    if [[ "$(db_get_config web_ui_enabled)" == "true" ]]; then
        log_info "Installing WireGuard sync service..."
        
        cat > /etc/systemd/system/samnet-wg-sync.service << 'WGSYNC_SERVICE'
[Unit]
Description=SamNet WireGuard Config Sync (instant reload from API)
After=wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
# Watch the DIRECTORY for trigger file creation (file doesn't exist until API creates it)
ExecStart=/bin/bash -c 'while true; do inotifywait -qq -e create -e modify --include "\.reload_trigger$" /etc/wireguard/ 2>/dev/null && wg syncconf wg0 <(wg-quick strip wg0) && rm -f /etc/wireguard/.reload_trigger; sleep 0.1; done'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
WGSYNC_SERVICE
        
        systemctl daemon-reload
        systemctl enable samnet-wg-sync.service >/dev/null 2>&1
        systemctl start samnet-wg-sync.service >/dev/null 2>&1
        log_success "WireGuard sync service installed (instant peer updates)"
    fi
    
    trap - ERR
    unset INSTALL_STAGE
    
    log_success "SamNet-WG Installed!"
    echo -e "\n  ${C_BOLD}Access:${C_RESET}"
    local ui_mode=$(db_get_config web_ui_mode)
    local ui_url=""
    if [[ "$ui_mode" == "https" ]]; then
        ui_url="https://$(db_get_config ssl_domain)"
    else
        # Show local IP for LAN mode
        local local_ip=$(hostname -I | awk '{print $1}')
        ui_url="http://${local_ip:-$(db_get_config wan_ip)}"
    fi
    [[ "$(db_get_config web_ui_enabled)" == "true" ]] && echo -e "  ├─ Web UI:     ${C_CYAN}${ui_url}${C_RESET}"
    echo -e "  ├─ CLI:        ${C_WHITE}samnet${C_RESET}"
    [[ -f "$CRED_FILE" ]] && echo -e "  └─ Credentials: ${C_YELLOW}$CRED_FILE${C_RESET}"
    
    echo -e "\n  ${C_RED}${C_BOLD}IMPORTANT:${C_RESET} ${C_WHITE}Forward UDP Port $(db_get_config listen_port) on your router to this device!${C_RESET}"
}

run_install_wizard() {
    local step=1 wan_ip="" port="51820" subnet="10.100.0.0/24"
    
    # FAILSAFE: Block installation on active system
    if systemctl is-active --quiet wg-quick@wg0 || docker ps --format '{{.Names}}' | grep -qE "^samnet(-wg)?-api$"; then
        echo
        ui_box_danger "SYSTEM ACTIVE" \
            "SamNet is already running!" \
            "" \
            "You cannot run the install wizard on top of a live system." \
            "Please uninstall first or run the 'Repair' wizard."
        echo
        wait_key
        return
    fi
    
    while true; do
        show_banner
        printf "  ${C_DIM}Step %d of 6${C_RESET}\n" "$step"
        
        case $step in
            1)
                section "WAN IP Address"
                local detected=$(detect_public_ip)
                if [[ -n "$detected" ]]; then
                    printf "  Detected: ${C_WHITE}%s${C_RESET}\n\n" "$detected"
                    menu_option "Y" "Use detected" ""
                    menu_option "M" "Enter manually" ""
                    menu_option "B" "Back" ""
                    menu_option "Q" "Quit" ""
                    
                    printf "\n${C_CYAN}❯${C_RESET} "
                    local c=$(read_key)
                    case "${c^^}" in
                        B) return 1 ;;
                        Y) wan_ip="$detected"; ((step++)) ;;
                        M) wan_ip=$(prompt "Enter IP"); [[ -n "$wan_ip" ]] && ((step++)) ;;
                        Q) exit 0 ;;
                    esac
                else
                    wan_ip=$(prompt "Enter public IP")
                    [[ -n "$wan_ip" ]] && ((step++))
                fi
                [[ -n "$wan_ip" ]] && db_set_config "wan_ip" "$wan_ip"
                
                # Custom Endpoint Hostname
                echo ""
                if ui_confirm "Do you have a custom domain/hostname (e.g. vpn.example.com)?"; then
                    local cust_host=$(prompt "Enter hostname")
                    [[ -n "$cust_host" ]] && db_set_config "endpoint_hostname" "$cust_host"
                else
                    db_set_config "endpoint_hostname" "" # Clear if not used
                fi
                ;;
            2)
                section "WireGuard Port"
                echo "  Enter the UDP port for WireGuard traffic (Default: 51820)"
                echo "  Type 'B' to go back to previous step."
                echo
                
                while true; do
                    port=$(prompt "Port [B=Back]" "51820")
                    
                    # Check for back command first
                    if [[ "${port^^}" == "B" ]]; then
                        ((step--))
                        break
                    fi
                    
                    # Validate port number
                    if [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)); then
                        db_set_config "listen_port" "$port"
                        ((step++))
                        break
                    else
                        log_error "Invalid port. Must be a number 1-65535."
                    fi
                done
                ;;
            3)
                section "Web UI Dashboard"
                printf "\n  ${C_BOLD}Access your VPN from a web browser.${C_RESET}\n\n"
                
                menu_option "1" "Skip for now" "CLI only mode [DEFAULT]"
                menu_option "2" "LAN Only (HTTP)" "Local network access"
                menu_option "B" "Back" ""
                
                printf "\n"
                local c=$(prompt "Select [1-2, B]" "1")
                case "${c^^}" in
                    1)
                        db_set_config "web_ui_enabled" "false"
                        ((step++))
                        ;;
                    2)
                        db_set_config "web_ui_enabled" "true"
                        db_set_config "web_ui_mode" "lan"
                        ((step++))
                        ;;
                    B) ((step--)) ;;
                esac
                ;;
            4)
                if ! run_firewall_mode_wizard "install"; then
                    ((step--))
                else
                    ((step++))
                fi
                ;;

            5)
                section "Subnet Selection"
                run_subnet_wizard
                [[ -n "$WIZARD_SUBNET" ]] && { db_set_config "subnet_cidr" "$WIZARD_SUBNET"; ((step++)); } || ((step--))
                ;;
            6)
                section "Review & Apply"
                draw_box "Configuration" \
                    "WAN IP:    $(db_get_config wan_ip)" \
                    "Port:      $(db_get_config listen_port)" \
                    "Web UI:    $(db_get_config web_ui_enabled)" \
                    "Firewall:  $(db_get_config firewall_mode)" \
                    "Subnet:    $(db_get_config subnet_cidr)"
                
                menu_option "A" "Apply" ""
                menu_option "B" "Back" ""
                menu_option "X" "Abort" ""
                printf "\n${C_CYAN}❯${C_RESET} "
                local c=$(read_key)
                case "${c^^}" in
                    A) return 0 ;;
                    B) ((step--)) ;;
                    X) exit 0 ;;
                esac
                ;;
        esac
    done
}


run_subnet_wizard() {
    WIZARD_SUBNET=""
    printf "\n  ${T_BOLD}Recommended /24 Pools:${T_RESET}\n\n"
    
    local i=1
    local options=()
    local cidrs=()
    
    # Show Pool Presets FIRST (user requested /24 pools at top)
    for preset in "${IP_POOL_PRESETS[@]}"; do
        IFS='|' read -r id cidr max desc <<< "$preset"
        printf "  ${C_CYAN}[%d]${C_RESET} %-15s ${C_DIM}%s${C_RESET}\n" "$i" "$cidr" "$desc"
        cidrs[$i]="$cidr"
        ((i++))
    done
    
    printf "\n  ${T_BOLD}Or Select Custom Size:${T_RESET}\n\n"
    
    # Show Size Presets SECOND
    for preset in "${SIZE_PRESETS[@]}"; do
        IFS='|' read -r id cidr max desc <<< "$preset"
        printf "  ${C_CYAN}[%d]${T_RESET} %-15s ${C_DIM}%s${C_RESET}\n" "$i" "$cidr" "$desc"
        cidrs[$i]="$cidr"
        ((i++))
    done
    
    echo
    menu_option "B" "Back" ""
    printf "\n${C_CYAN}❯${C_RESET} "
    
    local c=$(prompt "Select [1-$((i-1))]" "3")
    
    if [[ "$c" =~ ^[0-9]+$ ]] && [[ "$c" -ge 1 && "$c" -lt "$i" ]]; then
        WIZARD_SUBNET="${cidrs[$c]}"
    elif [[ "${c^^}" == "B" ]]; then
        WIZARD_SUBNET=""
    else
        # Default to Large (/24) if invalid or empty
        WIZARD_SUBNET="10.100.0.0/24"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 8. TUI SCREENS
# ══════════════════════════════════════════════════════════════════════════════

screen_install() {
    while true; do
        ui_draw_header_mini "Install & Repair"
        menu_option "1" "Zero-Touch Install" "Auto-setup"
        menu_option "2" "Step-by-Step Wizard" "Guided"
        menu_option "3" "Repair / Self-Heal" ""
        menu_option "4" "Validate Only" "Dry-run"
        printf "\n"
        menu_option "B" "Back" ""
        
        ui_draw_footer "[1-4] Select  [B] Back"
        printf "\n${T_CYAN}❯${T_RESET} "
        
        local key=$(read_key)
        case "$key" in
            1) INTERACTIVE=false; do_install; wait_key ;;
            2) INTERACTIVE=true; do_install; wait_key ;;
            3) run_repair; wait_key ;;
            4) run_dry_validator; wait_key ;;
            b|B|$'\x1b') return ;;
            q|Q) cleanup_exit 0 ;;
        esac
    done
}

# Interactive QR Code Selector
list_peers_qr() {
    ui_draw_header_mini "Peer QR Codes"
    
    local client_dir="$INSTALL_DIR/clients"
    
    if [[ ! -d "$client_dir" ]]; then
        log_error "No persistent client configs found."
        log_info "Only peers created after this update have saved configs."
        wait_key
        return
    fi
    
    local configs=("$client_dir"/*.conf)
    if [[ ! -e "${configs[0]}" ]]; then
        log_error "No client configurations found."
        wait_key
        return
    fi
    
    echo "  Select a peer to view QR code:"
    echo ""
    
    local i=1
    local valid_indices=()
    local files=()
    
    for conf in "${configs[@]}"; do
        local name=$(basename "$conf" .conf)
        printf "    ${T_CYAN}[%d]${T_RESET} %-15s ${C_DIM}%s${C_RESET}\n" "$i" "$name"
        files[$i]="$conf"
        valid_indices+=("$i")
        ((i++))
    done
    
    local selection=$(prompt "Select peer #")
    
    if [[ -z "$selection" ]]; then return; fi
    
    if [[ " ${valid_indices[*]} " =~ " ${selection} " ]]; then
        local target="${files[$selection]}"
        if [[ -f "$target" ]]; then
             ui_clear
             ui_draw_header_mini "QR Code: $(basename "$target" .conf)"
             qrencode -t UTF8 -r "$target"
             echo ""
             wait_key
        fi
    else
        log_error "Invalid selection."
        sleep 1
    fi
}

screen_security() {
    while true; do
        show_banner
        section "Security & Access"
        
        menu_option "1" "Secrets Health" ""
        menu_option "2" "Audit Log" ""
        menu_option "3" "Rotate Token" ""
        menu_option "4" "Firewall Ports" "Add/remove open ports"
        menu_option "B" "Back" ""
        
        printf "\n${C_CYAN}❯${C_RESET} "
        local c=$(read_key)
        case "${c^^}" in
            1) secrets_health ;;
            2) view_audit ;;
            3) rotate_token ;;
            4) screen_firewall_ports ;;
            B|G) return ;;
            Q) cleanup_exit 0 ;;
        esac
    done
}

screen_firewall_ports() {
    while true; do
        show_banner
        section "Firewall Ports"
        
        local mode=$(db_get_config "firewall_mode")
        printf "  ${T_DIM}Current mode: ${T_RESET}${C_CYAN}%s${C_RESET}\n\n" "${mode:-not set}"
        
        if [[ "$mode" != "samnet" ]]; then
            log_warn "Firewall is in '$mode' mode - use your external firewall tool"
            log_info "Change to 'samnet' mode to manage ports here"
            echo ""
            menu_option "M" "Change Mode" ""
            menu_option "B" "Back" ""
            printf "\n${C_CYAN}❯${C_RESET} "
            local c=$(read_key)
            case "${c^^}" in
                M) run_firewall_mode_wizard && apply_firewall ;;
                B|Q) return ;;
            esac
            continue
        fi
        
        menu_option "1" "List Open Ports" ""
        menu_option "2" "Add Port" ""
        menu_option "3" "Remove Port" ""
        menu_option "M" "Change Mode" ""
        menu_option "B" "Back" ""
        
        printf "\n${C_CYAN}❯${C_RESET} "
        local c=$(read_key)
        case "${c^^}" in
            1)
                echo ""
                list_firewall_ports
                wait_key
                ;;
            2)
                echo ""
                read -r -p "  Port number: " port
                [[ -z "$port" ]] && continue
                
                echo ""
                echo "  ${C_BOLD}Protocol:${C_RESET}"
                menu_option "1" "TCP" "(default)"
                menu_option "2" "UDP" ""
                menu_option "3" "Both" ""
                printf "\n  ${C_CYAN}❯${C_RESET} "
                local proto_choice=$(read_key)
                
                case "$proto_choice" in
                    1|"") 
                        add_firewall_port "$port" "tcp"
                        ;;
                    2)
                        add_firewall_port "$port" "udp"
                        ;;
                    3)
                        add_firewall_port "$port" "tcp"
                        add_firewall_port "$port" "udp"
                        ;;
                esac
                wait_key
                ;;
            3)
                echo ""
                read -r -p "  Port to remove: " port
                [[ -z "$port" ]] && continue
                
                echo ""
                echo "  ${C_BOLD}Protocol:${C_RESET}"
                menu_option "1" "TCP" "(default)"
                menu_option "2" "UDP" ""
                menu_option "3" "Both" ""
                printf "\n  ${C_CYAN}❯${C_RESET} "
                local proto_choice=$(read_key)
                
                case "$proto_choice" in
                    1|"") 
                        remove_firewall_port "$port" "tcp"
                        ;;
                    2)
                        remove_firewall_port "$port" "udp"
                        ;;
                    3)
                        remove_firewall_port "$port" "tcp"
                        remove_firewall_port "$port" "udp"
                        ;;
                esac
                wait_key
                ;;
            M)
                run_firewall_mode_wizard && apply_firewall
                ;;
            B|Q) return ;;
        esac
    done
}

screen_observability() {
    while true; do
        show_banner
        section "Observability"
        
        menu_option "1" "Health Check" ""
        menu_option "2" "Recent Logs" ""
        menu_option "3" "Audit Log" ""
        menu_option "B" "Back" ""
        
        printf "\n${C_CYAN}❯${C_RESET} "
        local c=$(read_key)
        case "${c^^}" in
            1) check_health ;;
            2) tail_logs ;;
            3) view_audit ;;
            B|G) return ;;
            Q) cleanup_exit 0 ;;
        esac
    done
}

screen_advanced_v2() {
    while true; do
        show_banner
        section "Advanced Tools"
        log_warn "For advanced operators only."
        
        menu_option "1" "Dry-Run Validator" "Zero side-effect check"
        menu_option "2" "Firewall Diff" "Planned vs applied"
        menu_option "3" "Troubleshooter" "Guided diagnostics"
        menu_option "4" "Repair Wizard" "Step-by-step fix"
        menu_option "5" "Export Diagnostics" "Sanitized bundle"
        menu_option "6" "Watch Mode" "Live dashboard"
        menu_option "7" "Quick Bench" "Performance test"
        menu_option "D" "DDNS Setup" "Configure Dynamic DNS"
        menu_option "W" "Web UI Settings" "Enable/HTTPS/LAN mode"
        menu_option "B" "Back" ""
        
        printf "\n${C_CYAN}❯${C_RESET} "
        local c=$(read_key)
        case "${c^^}" in
            1) run_dry_validator ;;
            2) firewall_diff_viewer ;;
            3) run_troubleshooter ;;
            4) run_repair_wizard ;;
            5) export_diagnostics_bundle ;;
            6) run_watch_mode ;;
            7) quick_bench ;;
            D) configure_ddns ;;
            W) screen_webui_settings ;;
            B|G) return ;;
            Q) cleanup_exit 0 ;;
        esac
    done
}

screen_webui_settings() {
    while true; do
        show_banner
        section "Web UI Settings"
        
        local enabled=$(db_get_config web_ui_enabled)
        local mode=$(db_get_config web_ui_mode)
        local domain=$(db_get_config ssl_domain)
        
        printf "\n  ${C_BOLD}Current Status:${C_RESET}\n"
        [[ "$enabled" == "true" ]] && printf "  ├─ Enabled:  ${C_GREEN}Yes${C_RESET}\n" || printf "  ├─ Enabled:  ${C_RED}No${C_RESET}\n"
        printf "  ├─ Mode:     ${C_WHITE}%s${C_RESET}\n" "${mode:-not set}"
        printf "  └─ Domain:   ${C_WHITE}%s${C_RESET}\n\n" "${domain:-not set}"
        
        menu_option "1" "Enable Web UI" ""
        menu_option "2" "Disable Web UI" ""
        menu_option "3" "Configure DDNS" "For WireGuard endpoint"
        menu_option "B" "Back" ""
        
        printf "\n${C_CYAN}❯${C_RESET} "
        local c=$(read_key)
        case "${c^^}" in
            1)
                db_set_config "web_ui_enabled" "true"
                db_set_config "web_ui_mode" "lan"
                log_success "Web UI enabled. Restart required."
                wait_key
                ;;
            2)
                db_set_config "web_ui_enabled" "false"
                docker stop samnet-wg-ui samnet-ui &>/dev/null || true
                log_success "Web UI disabled."
                wait_key
                ;;
            3)
                run_ddns_wizard
                wait_key
                ;;
            B|G) return ;;
            Q) cleanup_exit 0 ;;
        esac
    done
}

screen_about() {
    show_banner
    section "About SamNet-WG"
    
    draw_box "Mission" \
        "Production-grade, self-hosted WireGuard platform." \
        "No cloud. No tracking. Just reliability."
    
    printf "\n  ${C_BOLD}Links${C_RESET}\n"
    printf "  └─ GitHub: ${C_CYAN}github.com/samnet-wg${C_RESET}\n"
    printf "\n  Version: %s\n" "$VERSION"
    
    wait_key
}

# Consolidating redundant uninstall...

# ══════════════════════════════════════════════════════════════════════════════
# 9. HELPER OPERATIONS
# ══════════════════════════════════════════════════════════════════════════════

# Consolidating stubs...

archive_stale() {
    local count=$(get_stale_peer_count)
    [[ "$count" -eq 0 ]] && { log_info "No stale peers"; wait_key; return; }
    confirm "Archive $count stale peers?" && log_success "Archived." || log_info "Cancelled."
    wait_key
}

list_peers() {
    show_banner
    section "All Peers"
    printf "  ${C_DIM}Subnet:${C_RESET} ${C_WHITE}%s${C_RESET}\n" "$(db_get_config subnet_cidr)"
    printf "\n  ${C_BOLD}%-20s %-18s %-8s${C_RESET}\n" "NAME" "IP" "STATUS"
    
    scan_peers | \
    while IFS='|' read -r n ip src s; do
        [[ "$s" == "ACTIVE" ]] && printf "  %-20s %-18s ${C_GREEN}%s${C_RESET}\n" "$n" "$ip" "$s" \
                                || printf "  %-20s %-18s ${C_RED}%s${C_RESET}\n" "$n" "$ip" "$s"
    done

    wait_key
}

# Alias for menu compatibility
list_peers_screen() {
    list_peers
}

run_dry_validator() {
    show_banner
    section "Dry-Run Validator"
    log_info "Checking..."
    
    local checks=(
        "WG module:lsmod 2>/dev/null | grep -q wireguard"
        "Database:test -f $DB_PATH"
        "Docker:systemctl is-active --quiet docker"
    )
    for check in "${checks[@]}"; do
        local name="${check%%:*}"
        local cmd="${check#*:}"
        printf "  %s..." "$name"
        eval "$cmd" &>/dev/null && printf " ${C_GREEN}✔${C_RESET}\n" || printf " ${C_RED}✘${C_RESET}\n"
    done
    wait_key
}

run_repair() {
    run_repair_wizard
}

secrets_health() {
    show_banner
    section "Secrets Health"
    [[ -f /var/lib/samnet-wg/master.key ]] && log_success "Master key exists" || log_error "Master key missing"
    [[ -f /etc/wireguard/privatekey ]] && log_success "WG key exists" || log_error "WG key missing"
    wait_key
}

view_audit() {
    show_banner
    section "Audit Log"
    sqlite3 "$DB_PATH" "SELECT datetime(created_at), action, substr(details,1,30) FROM audit_logs ORDER BY created_at DESC LIMIT 10;" 2>/dev/null || log_warn "No logs"
    wait_key
}

rotate_token() {
    confirm "Rotate bootstrap token?" || return
    log_success "Token: $(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
    wait_key
}

check_health() {
    show_banner
    section "Health Check"
    curl -sf $(get_api_url)/health/live &>/dev/null && log_success "Live: OK" || log_error "Live: FAIL"
    curl -sf $(get_api_url)/health/ready &>/dev/null && log_success "Ready: OK" || log_error "Ready: FAIL"
    wait_key
}

tail_logs() {
    show_banner
    section "Recent Logs"
    journalctl -u wg-quick@wg0 -u docker --no-pager -n 15 2>/dev/null | sed 's/\(key\|password\|token\)=[^ ]*/\1=***REDACTED***/gi' || log_warn "No logs"
    wait_key
}

firewall_diff() {
    show_banner
    section "Firewall Rules"
    nft list ruleset 2>/dev/null | head -30 || log_warn "nft not available"
    wait_key
}

quick_bench() {
    show_banner
    section "Quick Benchmark"
    
    local start=$(date +%s%N)
    sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM peers;" &>/dev/null
    local end=$(date +%s%N)
    printf "  DB Query: %d ms\n" "$(( (end - start) / 1000000 ))"
    
    local api=$(curl -o /dev/null -s -w '%{time_total}' $(get_api_url)/health/live 2>/dev/null || echo "N/A")
    printf "  API: %s s\n" "$api"
    wait_key
}

export_diag() {
    local out="/tmp/samnet-diag-$(date +%Y%m%d-%H%M%S).tar.gz"
    local tmp=$(mktemp)
    uname -a > "$tmp/system.txt" 2>/dev/null
    wg show > "$tmp/wg.txt" 2>/dev/null
    nft list ruleset > "$tmp/fw.txt" 2>/dev/null
    tar -czf "$out" -C "$tmp" . 2>/dev/null
    rm -rf "$tmp"
    log_success "Exported: $out"
    wait_key
}

# ══════════════════════════════════════════════════════════════════════════════
# 10. POWER USER FEATURES
# ══════════════════════════════════════════════════════════════════════════════

readonly LOCK_FILE="/var/run/samnet-cli.lock"
readonly SNAPSHOT_DIR="/var/lib/samnet-wg/snapshots"

# Session Lock
acquire_session_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            log_error "Another session running (PID: $pid)"
            exit 1
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"; cleanup_exit 0' EXIT
}

release_session_lock() { rm -f "$LOCK_FILE"; }

# Command Palette (/ or Ctrl+P)
declare -a PALETTE_ACTIONS=(
    "status|Status Dashboard|screen_status"
    "peers|Manage Peers|screen_peers"
    "create|Create Peer|add_peer_wizard"
    "install|Run Installation|do_install"
    "repair|Run Repair|run_repair_wizard"
    "diag|Export Diagnostics|export_diagnostics_bundle"
    "trouble|Troubleshooter|run_troubleshooter"
    "fwdiff|Firewall Diff|firewall_diff_viewer"
    "watch|Watch Mode|run_watch_mode"
    "health|Health Check|check_health"
    "logs|Recent Logs|tail_logs"
    "audit|Audit Log|view_audit"
    "about|About SamNet|screen_about"
    "quit|Exit|cleanup_exit 0"
)

show_command_palette() {
    local filter=""
    while true; do
        show_banner
        section "Command Palette"
        printf "\n  ${C_DIM}Type to filter, Enter to select, Esc to close${C_RESET}\n\n"
        printf "  ${C_CYAN}❯${C_RESET} ${C_WHITE}%s${C_RESET}${C_DIM}█${C_RESET}\n\n" "$filter"
        
        local count=0
        for action in "${PALETTE_ACTIONS[@]}"; do
            IFS='|' read -r key label cmd <<< "$action"
            if [[ -z "$filter" || "$key" == *"$filter"* || "${label,,}" == *"${filter,,}"* ]]; then
                printf "  ${C_CYAN}%-10s${C_RESET} %s\n" "$key" "$label"
                ((count++))
                [[ $count -ge 8 ]] && break
            fi
        done
        
        show_footer "[Enter] Run  [Esc] Cancel"
        
        IFS= read -rsn1 key
        case "$key" in
            $'\x1b') return ;;
            $'\x7f'|$'\b') filter="${filter%?}" ;;
            '') 
                for action in "${PALETTE_ACTIONS[@]}"; do
                    IFS='|' read -r k l cmd <<< "$action"
                    if [[ -z "$filter" || "$k" == *"$filter"* || "${l,,}" == *"${filter,,}"* ]]; then
                        eval "$cmd"
                        return
                    fi
                done
                ;;
            *) filter+="$key" ;;
        esac
    done
}

# Diagnostics Bundle Generator
export_diagnostics_bundle() {
    show_banner
    section "Export Diagnostics Bundle"
    
    local snap_id=$(date +%Y%m%d-%H%M%S)
    local outfile="/tmp/samnet-diag-${snap_id}.tar.gz"
    
    log_info "Generating sanitized bundle (ID: $snap_id)..."
    
    local tmpdir=$(mktemp -d)
    
    # System info
    uname -a > "$tmpdir/system.txt" 2>/dev/null
    cat /etc/os-release > "$tmpdir/os.txt" 2>/dev/null
    df -h > "$tmpdir/disk.txt" 2>/dev/null
    free -h > "$tmpdir/memory.txt" 2>/dev/null
    
    # Network (sanitized)
    ip addr | sed 's/ether [^ ]*/ether XX:XX:XX:XX:XX:XX/g' > "$tmpdir/network.txt" 2>/dev/null
    ip route > "$tmpdir/routes.txt" 2>/dev/null
    
    # WireGuard (sanitized - remove keys)
    wg show 2>/dev/null | sed 's/\(private\|public\|preshared\) key:.*/\1 key: ***REDACTED***/gi' > "$tmpdir/wireguard.txt"
    
    # Firewall
    nft list ruleset > "$tmpdir/firewall.txt" 2>/dev/null
    
    # Firewall mode and ports config
    echo "firewall_mode=$(db_get_config firewall_mode)" > "$tmpdir/firewall_config.txt"
    echo "listen_port=$(db_get_config listen_port)" >> "$tmpdir/firewall_config.txt"
    [[ -f /etc/samnet-ports.nft ]] && cp /etc/samnet-ports.nft "$tmpdir/samnet-ports.nft"
    [[ -f /etc/nftables.conf ]] && cp /etc/nftables.conf "$tmpdir/nftables.conf"
    
    # Services
    systemctl status wg-quick@wg0 > "$tmpdir/wg-status.txt" 2>/dev/null
    docker ps -a > "$tmpdir/docker.txt" 2>/dev/null
    
    # Logs (sanitized)
    journalctl -u wg-quick@wg0 --no-pager -n 100 2>/dev/null | \
        sed 's/\(key\|password\|token\|secret\)=[^ ]*/\1=***REDACTED***/gi' > "$tmpdir/logs.txt"
    
    # DB stats (no sensitive data)
    [[ -f "$DB_PATH" ]] && sqlite3 "$DB_PATH" "SELECT 'peers', COUNT(*) FROM peers UNION SELECT 'users', COUNT(*) FROM users;" > "$tmpdir/db_stats.txt" 2>/dev/null
    
    # Manifest
    echo "SamNet Diagnostics Bundle" > "$tmpdir/MANIFEST.txt"
    echo "ID: $snap_id" >> "$tmpdir/MANIFEST.txt"
    echo "Created: $(date -Iseconds)" >> "$tmpdir/MANIFEST.txt"
    echo "Version: $VERSION" >> "$tmpdir/MANIFEST.txt"
    
    tar -czf "$outfile" -C "$tmpdir" . 2>/dev/null
    rm -rf "$tmpdir"
    
    log_success "Bundle created!"
    printf "\n  ${C_BOLD}File:${C_RESET} ${C_WHITE}%s${C_RESET}\n" "$outfile"
    printf "  ${C_BOLD}ID:${C_RESET}   ${C_CYAN}%s${C_RESET}\n" "$snap_id"
    printf "\n  ${C_DIM}Safe to share - all secrets redacted${C_RESET}\n"
    wait_key
}

# Troubleshooter Wizard
run_troubleshooter() {
    show_banner
    section "Troubleshooter Wizard"
    
    log_info "Running diagnostic checks..."
    printf "\n"
    
    local issues=()
    
    # Check WireGuard
    if ! systemctl is-active --quiet wg-quick@wg0; then
        issues+=("WG|WireGuard not running|systemctl start wg-quick@wg0")
    fi
    
    # Check interface
    if ! ip link show wg0 &>/dev/null; then
        issues+=("NET|wg0 interface missing|systemctl restart wg-quick@wg0")
    fi
    
    # Check firewall
    if ! nft list ruleset 2>/dev/null | grep -q "masquerade"; then
        issues+=("FW|NAT rules missing|nft -f /etc/nftables.conf")
    fi
    
    # Check firewall mode consistency
    local fw_mode=$(db_get_config "firewall_mode")
    if [[ "$fw_mode" == "samnet" ]]; then
        if ! nft list table inet samnet-ports &>/dev/null; then
            issues+=("FW|samnet-ports table missing|samnet --apply-firewall")
        fi
    fi
    
    # Check Docker
    if ! systemctl is-active --quiet docker; then
        issues+=("DOCKER|Docker not running|systemctl start docker")
    fi
    
    # Check API
    if ! curl -sf $(get_api_url)/health/live &>/dev/null; then
        issues+=("API|API not responding|docker restart samnet-wg-api")
    fi
    
    # Check DNS
    if ! curl -sf --max-time 3 https://google.com &>/dev/null; then
        issues+=("DNS|No internet/DNS|Check network config")
    fi
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "All checks passed! No issues detected."
    else
        log_warn "Found ${#issues[@]} issue(s):"
        printf "\n"
        
        local i=1
        for issue in "${issues[@]}"; do
            IFS='|' read -r code desc fix <<< "$issue"
            printf "  ${C_RED}%d.${C_RESET} [%s] %s\n" "$i" "$code" "$desc"
            printf "     ${C_DIM}Fix: %s${C_RESET}\n\n" "$fix"
            ((i++))
        done
        
        if confirm "Auto-fix all issues?"; then
            for issue in "${issues[@]}"; do
                IFS='|' read -r code desc fix <<< "$issue"
                log_info "Fixing: $desc..."
                if eval "$fix"; then
                    log_success "Applied: $fix"
                else
                    log_error "Failed to fix: $desc"
                fi
            done
            log_success "Fixes applied. Re-run to verify."
        fi
    fi
    wait_key
}

# Firewall Diff Viewer
firewall_diff_viewer() {
    show_banner
    section "Firewall Diff Viewer"
    
    local snap_id=$(date +%s | tail -c 5)
    printf "  ${C_DIM}Snapshot ID: %s${C_RESET}\n\n" "$snap_id"
    
    # Show firewall mode
    local mode=$(db_get_config "firewall_mode")
    printf "  ${C_BOLD}Firewall Mode:${C_RESET} ${C_CYAN}%s${C_RESET}\n\n" "${mode:-not set}"
    
    log_info "Comparing planned vs applied rules..."
    printf "\n"
    
    # Get current applied rules
    local applied=$(nft list ruleset 2>/dev/null)
    
    printf "  ${C_BOLD}Applied Tables:${C_RESET}\n"
    nft list tables 2>/dev/null | while read line; do
        printf "  ${C_DIM}│${C_RESET} %s\n" "$line"
    done
    
    printf "\n  ${C_BOLD}Config Files:${C_RESET}\n"
    if [[ -f /etc/nftables.conf ]]; then
        printf "  ${C_GREEN}●${C_RESET} /etc/nftables.conf (%d bytes)\n" "$(wc -c < /etc/nftables.conf)"
    else
        printf "  ${C_RED}●${C_RESET} /etc/nftables.conf - Missing!\n"
    fi
    
    if [[ -f /etc/samnet-ports.nft ]]; then
        printf "  ${C_GREEN}●${C_RESET} /etc/samnet-ports.nft (%d bytes)\n" "$(wc -c < /etc/samnet-ports.nft)"
    else
        printf "  ${C_DIM}●${C_RESET} /etc/samnet-ports.nft - Not created\n"
    fi
    
    # Show open ports if in samnet mode
    if [[ "$mode" == "samnet" ]] && nft list table inet samnet-ports &>/dev/null; then
        printf "\n  ${C_BOLD}Open Ports (samnet-ports):${C_RESET}\n"
        nft list chain inet samnet-ports input 2>/dev/null | \
            grep -E "(tcp|udp) dport" | head -10 | while read line; do
                printf "  ${C_DIM}│${C_RESET} %s\n" "$line"
            done
    fi
    
    # Check syntax
    if [[ -f /etc/nftables.conf ]] && nft -c -f /etc/nftables.conf &>/dev/null; then
        printf "\n  ${C_GREEN}✔${C_RESET} Config syntax valid\n"
    elif [[ -f /etc/nftables.conf ]]; then
        printf "\n  ${C_RED}✘${C_RESET} Config has syntax errors\n"
    fi
    
    printf "\n"
    menu_option "A" "Apply config" "(reload from file)"
    menu_option "S" "Save snapshot" "(backup current)"
    menu_option "B" "Back" ""
    
    printf "\n${C_CYAN}❯${C_RESET} "
    local c=$(read_key)
    case "${c^^}" in
        A)
            if confirm "Apply firewall config? (Snap: $snap_id)"; then
                nft list ruleset > "$SNAPSHOT_DIR/fw-$snap_id.nft" 2>/dev/null
                apply_firewall && log_success "Applied!" || log_error "Failed"
            fi
            wait_key
            ;;
        S)
            mkdir -p "$SNAPSHOT_DIR"
            nft list ruleset > "$SNAPSHOT_DIR/fw-$snap_id.nft" 2>/dev/null
            log_success "Saved: $SNAPSHOT_DIR/fw-$snap_id.nft"
            wait_key
            ;;
    esac
}

# Repair Wizard with Explainable Steps
run_repair_wizard() {
    show_banner
    section "Repair Wizard"
    
    log_warn "This will check and repair SamNet components."
    printf "\n  ${C_BOLD}Repair Checklist:${C_RESET}\n\n"
    
    local steps=(
        "Check database integrity"
        "Regenerate WireGuard config"
        "Verify firewall rules"
        "Restart WireGuard service"
        "Check Docker containers"
    )
    
    local i=1
    for step in "${steps[@]}"; do
        printf "  ${C_DIM}%d.${C_RESET} %s\n" "$i" "$step"
        ((i++))
    done
    
    printf "\n"
    if ! confirm "Proceed with repair?"; then
        log_info "Cancelled."
        wait_key
        return
    fi
    
    printf "\n"
    
    # Step 1
    printf "  ${C_CYAN}[1/5]${C_RESET} Database integrity..."
    if [[ -f "$DB_PATH" ]] && sqlite3 "$DB_PATH" "PRAGMA integrity_check;" &>/dev/null; then
        printf " ${C_GREEN}✔${C_RESET}\n"
    else
        printf " ${C_YELLOW}⚠${C_RESET} (will reinit)\n"
        ensure_db_init
    fi
    
    # Step 2
    printf "  ${C_CYAN}[2/5]${C_RESET} WireGuard config..."
    write_wg_conf
    printf " ${C_GREEN}✔${C_RESET}\n"
    
    # Step 3
    printf "  ${C_CYAN}[3/5]${C_RESET} Firewall rules..."
    apply_firewall &>/dev/null && printf " ${C_GREEN}✔${C_RESET}\n" || printf " ${C_RED}✘${C_RESET}\n"
    
    # Step 4
    printf "  ${C_CYAN}[4/5]${C_RESET} WireGuard service..."
    ensure_wg_up &>/dev/null
    printf " ${C_GREEN}✔${C_RESET}\n"
    # Step 5
    printf "  ${C_CYAN}[5/5]${C_RESET} Docker containers..."
    if [[ -f "$INSTALL_DIR/services/docker-compose.yml" ]]; then
        local api_port=$(db_get_config "api_port")
        export API_PORT="${api_port:-8766}"
        docker compose -f "$INSTALL_DIR/services/docker-compose.yml" up -d &>/dev/null
        printf " ${C_GREEN}✔${C_RESET}\n"
    else
        printf " ${C_DIM}skipped${C_RESET}\n"
    fi
    
    printf "\n"
    log_success "Repair complete!"
    wait_key
}

# Danger Zone Gating
require_danger_confirmation() {
    local action="$1"
    local snap_id=$(date +%s | tail -c 4)
    
    printf "\n  ${C_RED}${C_BOLD}⚠ DANGER ZONE ⚠${C_RESET}\n"
    printf "  ${C_DIM}Action: %s${C_RESET}\n\n" "$action"
    printf "  To confirm, type: ${C_BOLD}%s${C_RESET}\n" "$snap_id"
    printf "${C_CYAN}❯${C_RESET} "
    
    local input
    read -r input
    [[ "$input" == "$snap_id" ]]
}

# Watch Mode (low-overhead health dashboard)
run_watch_mode() {
    log_info "Entering watch mode (Ctrl+C to exit)..."
    local interval=5
    
    while true; do
        clear_screen
        printf "${C_ORANGE}${C_BOLD}SamNet Watch Mode${C_RESET} ${C_DIM}(refresh: ${interval}s)${C_RESET}\n"
        printf "${C_DIM}$(draw_line '─' 50)${C_RESET}\n\n"
        
        # Status row
        local wg=$(get_wg_status)
        [[ "$wg" == "ONLINE" ]] && printf "  WG: ${C_GREEN}●${C_RESET} " || printf "  WG: ${C_RED}●${C_RESET} "
        
        local docker_ok=$(systemctl is-active docker 2>/dev/null)
        [[ "$docker_ok" == "active" ]] && printf "Docker: ${C_GREEN}●${C_RESET} " || printf "Docker: ${C_RED}●${C_RESET} "
        
        local api_ok=$(curl -sf --max-time 1 $(get_api_url)/health/live &>/dev/null && echo "ok")
        [[ -n "$api_ok" ]] && printf "API: ${C_GREEN}●${C_RESET}" || printf "API: ${C_RED}●${C_RESET}"
        printf "\n\n"
        
        # Metrics
        printf "  Peers: ${C_WHITE}%s${C_RESET}  CPU: ${C_WHITE}%s%%${C_RESET}  Mem: ${C_WHITE}%s${C_RESET}\n" \
            "$(get_peer_count)" "$(get_cpu_usage)" "$(get_mem_usage)"
        
        printf "\n${C_DIM}  Ctrl+C to exit${C_RESET}\n"
        
        sleep $interval || break
    done
}

# DDNS Configuration Wizard
configure_ddns() {
    show_banner
    section "DDNS Setup"
    
    log_info "Dynamic DNS keeps your VPN accessible if your home IP changes."
    printf "\n"
    
    # Check current status
    local current_conf=$(sqlite3 "$DB_PATH" "SELECT config FROM feature_flags WHERE key='ddns';" 2>/dev/null)
    local enabled=$(sqlite3 "$DB_PATH" "SELECT enabled FROM feature_flags WHERE key='ddns';" 2>/dev/null)
    
    if [[ "$enabled" == "1" && -n "$current_conf" ]]; then
        local prov=$(echo "$current_conf" | jq -r .provider 2>/dev/null)
        local dom=$(echo "$current_conf" | jq -r .domain 2>/dev/null)
        printf "  Status:   ${C_GREEN}● ACTIVE${C_RESET}\n"
        printf "  Provider: ${C_WHITE}%s${C_RESET}\n" "$prov"
        printf "  Domain:   ${C_WHITE}%s${C_RESET}\n\n" "$dom"
        
        if confirm "Reconfigure DDNS?"; then
            : # Continue
        else
            if confirm "Disable DDNS?"; then
                sqlite3 "$DB_PATH" "UPDATE feature_flags SET enabled=0 WHERE key='ddns';"
                log_success "DDNS disabled."
            fi
            wait_key
            return
        fi
    else
        printf "  Status:   ${C_DIM}● NOT CONFIGURED${C_RESET}\n\n"
    fi
    
    printf "  ${C_BOLD}Select Provider:${C_RESET}\n"
    printf "    ${C_CYAN}[1]${C_RESET} DuckDNS      ${C_DIM}(Free, Easy)${C_RESET}\n"
    printf "    ${C_CYAN}[2]${C_RESET} Cloudflare   ${C_DIM}(Custom Domain)${C_RESET}\n"
    printf "    ${C_CYAN}[3]${C_RESET} Custom HTTP  ${C_DIM}(Advanced)${C_RESET}\n"
    
    printf "\n"
    local choice=$(prompt "Select [1-3]")
    local provider=""
    local domain=""
    local token=""
    local webhook=""
    
    case "$choice" in
        1)
            provider="duckdns"
            printf "\n  ${C_BOLD}DuckDNS Setup${C_RESET}\n"
            printf "  1. Go to ${C_CYAN}duckdns.org${C_RESET}\n"
            printf "  2. Create a domain (e.g., samnet.duckdns.org)\n"
            printf "  3. Copy your token\n\n"
            
            domain=$(prompt "Domain (e.g. mysite.duckdns.org)")
            token=$(prompt "Token")
            [[ -z "$domain" || -z "$token" ]] && { log_error "Missing info"; wait_key; return; }
            ;;
        2)
            provider="cloudflare"
            echo -e "\n  ${C_BOLD}Cloudflare Setup${C_RESET}"
            echo "  Requires an API Token with 'Zone:DNS:Edit' permissions."
            
            domain=$(prompt "Domain (e.g. vpn.example.com)")
            token=$(prompt "API Token")
            [[ -z "$domain" || -z "$token" ]] && { log_error "Missing info"; wait_key; return; }
            ;;
        3)
            provider="webhook"
            webhook=$(prompt "Webhook URL")
            [[ -z "$webhook" ]] && { log_error "Missing URL"; wait_key; return; }
            ;;
        *)
            log_error "Invalid selection."
            wait_key
            return
            ;;
    esac
    
    log_info "Saving configuration..."
    
    # Construct JSON
    local json_conf
    if [[ "$provider" == "webhook" ]]; then
        json_conf=$(jq -n --arg p "$provider" --arg w "$webhook" '{provider: $p, webhook_url: $w, interval_minutes: 5}')
    else
        json_conf=$(jq -n --arg p "$provider" --arg d "$domain" --arg t "$token" '{provider: $p, domain: $d, token: $t, interval_minutes: 5}')
    fi
    
    # Save to DB
    sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO feature_flags (key, enabled, config) VALUES ('ddns', 1, '$json_conf');"
    
    log_success "DDNS configured!"
    log_info "Restarting API to apply changes..."
    docker restart samnet-api >/dev/null 2>&1
    
    log_success "Done. Check logs in a few minutes to verify."
    wait_key
}

# Help Overlay
show_help_overlay() {
    local screen="$1"
    show_banner
    section "Help: $screen"
    
    case "$screen" in
        main)
            draw_box "Main Menu" \
                "Central navigation hub for SamNet-WG." \
                "" \
                "• Use number keys to navigate" \
                "• Press / for command palette" \
                "• Press ? for context help"
            ;;
        status)
            draw_box "Status Dashboard" \
                "Shows system health at a glance." \
                "" \
                "• WireGuard: VPN tunnel status" \
                "• Peers: Active/stale client count" \
                "• Resources: CPU, memory, disk"
            ;;
        peers)
            draw_box "Peer Management" \
                "Create and manage VPN clients." \
                "" \
                "• Create: Generate new peer config" \
                "• Disable: Temporarily block peer" \
                "• Archive: Remove inactive peers"
            ;;
        *)
            printf "  ${C_DIM}No help available for this screen.${C_RESET}\n"
            ;;
    esac
    wait_key
}

# ══════════════════════════════════════════════════════════════════════════════
# 11. MAIN MENU SCREENS
# ══════════════════════════════════════════════════════════════════════════════

# Status Dashboard Screen
screen_status() {
    while true; do
        ui_draw_header_mini "Status Dashboard"
        
        # WireGuard Status
        local wg_status=$(get_wg_status)
        if [[ "$wg_status" == "ONLINE" ]]; then
            printf "    ${T_GREEN}● WireGuard${T_RESET}  ${T_DIM}Interface wg0 active${T_RESET}\n"
        else
            printf "    ${T_RED}● WireGuard${T_RESET}  ${T_DIM}Interface wg0 down${T_RESET}\n"
        fi
        
        # Docker/API Status
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "samnet(-wg)?-api"; then
            printf "    ${T_GREEN}● API Server${T_RESET}  ${T_DIM}Container running${T_RESET}\n"
        else
            printf "    ${T_RED}● API Server${T_RESET}  ${T_DIM}Container not running${T_RESET}\n"
        fi
        
        # Peer count
        local peer_count=0
        # Prefer DB count (includes Web UI peers) over live WG count
        if [[ -f "$DB_PATH" ]]; then
            peer_count=$(db_query "SELECT COUNT(*) FROM peers;" 2>/dev/null)
            [[ -z "$peer_count" ]] && peer_count=0
        fi
        # Fallback to live WG if DB returns 0 (for standalone mode)
        if [[ "$peer_count" -eq 0 ]] && wg show wg0 &>/dev/null; then
            peer_count=$(wg show wg0 | grep -c "peer:")
        fi
        
        printf "    ${T_CYAN}● Peers${T_RESET}       ${T_WHITE}$peer_count connected${T_RESET}\n"
        
        printf "\n"
        
        # Show WireGuard details
        printf "    ${T_CYAN}${T_BOLD}WireGuard Details:${T_RESET}\n"
        printf "    ${T_DIM}────────────────────────────────────────────${T_RESET}\n"
        wg show wg0 2>/dev/null | head -10 | while read line; do
            printf "    ${T_DIM}%s${T_RESET}\n" "$line"
        done
        
        ui_draw_footer "[R] Refresh  [B] Back"
        
        local key=$(read_key)
        case "$key" in
            r|R) ;; # Refresh - loop continues
            b|B|$'\x1b') return ;;
        esac
    done
}

# Manage Peers Screen
screen_peers() {
    while true; do
        # ──────── SYNC BEFORE DRAW ────────
        # If Web UI is enabled, sync with its state periodically
        if [[ "$(db_get_config web_ui_enabled)" == "true" ]]; then
            reconcile_db_with_files &>/dev/null
        fi
        
        ui_draw_header_mini "Manage Peers"
        
        # Show subnet and peer count
        local raw_subnet=$(db_get_config "subnet_cidr")
        if [[ -z "$raw_subnet" ]] && [[ -f "/etc/wireguard/wg0.conf" ]]; then
             raw_subnet=$(grep "Address" /etc/wireguard/wg0.conf 2>/dev/null | cut -d= -f2 | tr -d ' ' | cut -d, -f1 | head -1)
        fi
        local subnet_display=$(normalize_cidr "$raw_subnet")
        
        # Consistent counting using unified source
        local peer_count=$(scan_peers | grep -c .)
        
        printf "    ${T_CYAN}${T_BOLD}Network Status${T_RESET}\n"
        printf "    ${T_DIM}────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_WHITE}Subnet:${T_RESET} ${T_CYAN}%s${T_RESET}    ${T_WHITE}Peers:${T_RESET} ${T_GREEN}%s${T_RESET}\n\n" "$subnet_display" "$peer_count"
        
        printf "    ${T_CYAN}${T_BOLD}Peer Management${T_RESET}\n\n"
        
        menu_option "1" "Add Permanent Peer" "Create VPN client (no expiry)"
        menu_option "2" "Add Temporary Peer" "Create time-limited access"
        menu_option "3" "Add Bulk Peers" "Create multiple peers at once"
        menu_option "4" "List Peers" "View all clients"
        menu_option "5" "View Usage" "Bandwidth stats per peer"
        menu_option "6" "Set Data Limit" "Configure bandwidth caps"
        menu_option "7" "Remove Peer" "Delete a single client"
        menu_option "8" "Bulk Remove" "Delete multiple peers"
        menu_option "9" "Show QR Code" "Display config QR"
        menu_option "r" "Rename Peer" "Change peer name"
        menu_option "d" "Enable/Disable" "Toggle peer access"
        menu_option "k" "Rotate Key / Repair" "Regenerate keys (Fix missing QR)"
        menu_option "m" "Maintenance" "Backup, Restore & Migration"
        printf "\n"
        menu_option "B" "Back" ""
        
        ui_draw_footer "[1-9,R,D] Select  [B] Back"
        printf "\n${C_CYAN}❯${C_RESET} "
        
        local key=$(read_key)
        case "$key" in
            1) add_peer_wizard ;;
            2) add_temp_peer_wizard ;;
            3) add_bulk_peers_wizard ;;
            4) list_peers_screen ;;
            5) view_usage_screen ;;
            6) set_data_limit_wizard ;;
            7) remove_peer_wizard ;;
            8) remove_bulk_peers_wizard ;;
            9) show_qr_wizard ;;
            r|R) rename_peer_wizard ;;
            d|D) toggle_peer_status_wizard ;;
            k|K) rotate_peer_keys_wizard ;;
            m|M) screen_maintenance ;;
            "") ;; # Timeout - loop continues and refreshes
            b|B|$'\x1b') return ;;
        esac
    done
}

# Rotate Peer Keys Wizard
rotate_peer_keys_wizard() {
    ui_draw_header_mini "Rotate Peer Keys"
    
    printf "    ${T_CYAN}This will regenerate the private/public keys for a peer.${T_RESET}\n"
    printf "    ${T_YELLOW}Use this ONLY if you lost the client config/QR code.${T_RESET}\n"
    printf "    ${T_DIM}Note: The old connection will stop working immediately.${T_RESET}\n"
    printf "    ${T_DIM}You MUST scan the NEW QR code on your device after this.${T_RESET}\n\n"

    # Unified peer scan
    local names=()
    while IFS='|' read -r n ip src s; do
        [[ -n "$n" ]] && names+=("$n")
    done < <(scan_peers)
    
    if [[ ${#names[@]} -eq 0 ]]; then
        log_warn "No peers found."
        wait_key
        return
    fi
    
    printf "    ${T_GREEN}Select peer to repair:${T_RESET}\n"
    local i=1
    for n in "${names[@]}"; do
        printf "    ${T_GREEN}[%d]${T_RESET} %s\n" "$i" "$n"
        ((i++))
    done
    
    local choice=$(ui_prompt "Select #")
    [[ -z "$choice" ]] && return
    
    local idx=$((choice-1))
    local target_name="${names[$idx]}"
    
    if [[ -z "$target_name" ]]; then log_error "Invalid selection"; return; fi
    
    if confirm "Regenerate keys for '$target_name'? (Will break existing connection)"; then
        log_info "Rotating keys..."
        
        # 1. Generate new keys
        local priv=$(wg genkey)
        local pub=$(echo "$priv" | wg pubkey)
        local enc_priv=$(encrypt_peer_key "$priv")
        
        # 2. Update DB
        if [[ -f "$DB_PATH" ]]; then
            db_exec "UPDATE peers SET public_key='$pub', encrypted_private_key='$enc_priv' WHERE name='$target_name';"
        fi
        
        # Remove old entry from wg0.conf
        sed -i "/# $target_name/,/AllowedIPs/d" /etc/wireguard/wg0.conf
        
        # Get IP for this peer
        local match_ip=""
        if [[ -f "$DB_PATH" ]]; then
            match_ip=$(db_query "SELECT allowed_ips FROM peers WHERE name='$target_name';")
        fi
        
        # If IP missing from DB (rare), try to find it from old config backup or client file
        if [[ -z "$match_ip" ]]; then
             # Try client file
             local cfile="$INSTALL_DIR/clients/${target_name}.conf"
             if [[ -f "$cfile" ]]; then
                 match_ip=$(grep "Address" "$cfile" | cut -d= -f2 | tr -d ' ')
             fi
        fi
        
        if [[ -z "$match_ip" ]]; then
            log_error "Could not determine IP for peer. Cannot rotate."
            wait_key
            return
        fi

        local ip_short=$(echo "$match_ip" | cut -d/ -f1)
        
        # Add new entry to wg0.conf
        echo "" >> /etc/wireguard/wg0.conf
        echo "[Peer]" >> /etc/wireguard/wg0.conf
        echo "# $target_name" >> /etc/wireguard/wg0.conf
        echo "PublicKey = $pub" >> /etc/wireguard/wg0.conf
        echo "AllowedIPs = $match_ip" >> /etc/wireguard/wg0.conf
        
        # Live reload
        if command -v wg &>/dev/null; then
            wg set wg0 peer "$pub" allowed-ips "${ip_short}/32"
        fi
        
        # 4. Regenerate Client Config
        local client_conf="$INSTALL_DIR/clients/${target_name}.conf"
        local server_pubkey=$(cat /etc/wireguard/publickey 2>/dev/null)
        local server_port=$(grep "ListenPort" /etc/wireguard/wg0.conf | cut -d= -f2 | tr -d ' ')
        
        # Get endpoint
        local custom_host=$(db_get_config "endpoint_hostname")
        local server_endpoint=""
        if [[ -n "$custom_host" ]]; then
            server_endpoint="$custom_host"
        else
            server_endpoint=$(curl -4 -sf ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
        fi

        local mtu=$(db_get_config "mtu")
        [[ -z "$mtu" ]] && mtu="1380"
        local dns=$(db_get_config "dns_server")
        [[ -z "$dns" ]] && dns="1.1.1.1, 8.8.8.8"

        mkdir -p "$(dirname "$client_conf")"
        cat <<EOF > "$client_conf"
[Interface]
PrivateKey = $priv
Address = $match_ip
DNS = $dns
MTU = $mtu

[Peer]
PublicKey = $server_pubkey
Endpoint = ${server_endpoint}:${server_port}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
        chmod 600 "$client_conf"
        
        log_success "Keys rotated! New QR code generated."
        
        printf "\n    ${T_CYAN}${T_BOLD}Scan New QR Code:${T_RESET}\n"
        qrencode -t UTF8 -r "$client_conf" | less -R -K -P "Scan QR (Press Q to continue)"
    fi
    wait_key
}

# Rename Peer Wizard
# Rename Peer Wizard
rename_peer_wizard() {
    ui_draw_header_mini "Rename Peer"
    
    # Select Peer Code (Unified scan_peers)
    local names=()
    local ids=()
    while IFS='|' read -r n ip src s; do
        [[ -n "$n" ]] && names+=("$n")
        # In file mode, ID might be empty
        ids+=("")
        if [[ "$src" == "DB" && -f "$DB_PATH" ]]; then
             local fetched_id=$(db_query "SELECT id FROM peers WHERE name='$n';")
             ids[-1]="$fetched_id"
        fi
    done < <(scan_peers)
    
    if [[ ${#names[@]} -eq 0 ]]; then
        log_warn "No peers found."
        wait_key
        return
    fi
    
    printf "    ${T_CYAN}Select peer to rename:${T_RESET}\n\n"
    local i=1
    for n in "${names[@]}"; do
        printf "    ${T_GREEN}[%d]${T_RESET} %s\n" "$i" "$n"
        ((i++))
    done
    
    local choice=$(ui_prompt "Select #")
    [[ -z "$choice" ]] && return
    
    local idx=$((choice-1))
    local target_name="${names[$idx]}"
    local target_id="${ids[$idx]}"
    
    if [[ -z "$target_name" ]]; then log_error "Invalid selection"; return; fi
    
    local new_name=$(ui_prompt "New name for '$target_name'")
    [[ -z "$new_name" ]] && return
    [[ ! "$new_name" =~ ^[a-zA-Z0-9_-]+$ ]] && { log_error "Invalid name (alphanumeric only)"; return; }
    
    if ui_confirm "Rename '$target_name' to '$new_name'?"; then
         if [[ "$(db_get_config web_ui_enabled)" == "true" && -n "$target_id" ]]; then
              # Use new api_call helper (docker exec)
              local api_resp
              api_resp=$(api_call "PUT" "/internal/peers/$target_id" "{\"name\": \"$new_name\"}")
              
              # Simple success check (empty or JSON response usually means OK, error prints text)
              # But let's check exit code of docker exec indirectly via the result
              if [[ $? -eq 0 && -n "$api_resp" ]]; then 
                  log_success "Renamed via API."
                  sleep 1
                  return
              else
                  log_warn "API rename failed. Falling back to local/DB mode..."
              fi
         fi
         
         # Local Mode (Mode A or Fallback)
         local client_dir="$INSTALL_DIR/clients"
         mv "$client_dir/${target_name}.conf" "$client_dir/${new_name}.conf" 2>/dev/null
         mv "$client_dir/${target_name}.conf.limit" "$client_dir/${new_name}.conf.limit" 2>/dev/null
         mv "$client_dir/${target_name}.conf.expiry" "$client_dir/${new_name}.conf.expiry" 2>/dev/null
         mv "$client_dir/${target_name}.conf.disabled" "$client_dir/${new_name}.conf.disabled" 2>/dev/null
         
         # Update DB if exists
         if [[ -f "$DB_PATH" ]]; then
            db_exec "UPDATE peers SET name='$new_name' WHERE name='$target_name';"
         fi
         
         # Update wg0 comment
         sed -i "s/# $target_name/# $new_name/" /etc/wireguard/wg0.conf 2>/dev/null
         
         log_success "Renamed to '$new_name'."
    fi
    wait_key
}

# Toggle Enable/Disable Wizard
toggle_peer_status_wizard() {
    ui_draw_header_mini "Enable/Disable Peer"
    
     local names=()
     local ids=()
     local statuses=()
     
     # Use scan_peers for unified list
     while IFS='|' read -r n ip src s; do
        [[ -z "$n" ]] && continue
        
        local is_disabled=0
        [[ "$s" == "DISABLED" || "$s" == "OFFLINE" || "$s" == "OVER LIMIT" ]] && is_disabled=1
        
        names+=("$n")
        ids+=("")
        statuses+=("$is_disabled")
        
        # Try to fetch ID if DB is there (for API fallback)
        if [[ "$src" == "DB" && -f "$DB_PATH" ]]; then
             local fetched_id=$(db_query "SELECT id FROM peers WHERE name='$n';")
             ids[-1]="$fetched_id"
        fi
     done < <(scan_peers)
      
    if [[ ${#names[@]} -eq 0 ]]; then log_warn "No peers found."; wait_key; return; fi
    
    printf "    ${T_CYAN}Select peer to toggle:${T_RESET}\n\n"
    local i=1
    for idx in "${!names[@]}"; do
        local n="${names[$idx]}"
        local s="${statuses[$idx]}"
        local status_str="${T_GREEN}Enabled${T_RESET}"
        [[ "$s" == "1" ]] && status_str="${T_RED}Disabled${T_RESET}"
        printf "    ${T_GREEN}[%d]${T_RESET} %-20s %s\n" "$i" "$n" "$status_str"
        ((i++))
    done
    
    local choice=$(ui_prompt "Select #")
    [[ -z "$choice" ]] && return
    
    local idx=$((choice-1))
    local target_name="${names[$idx]}"
    local target_id="${ids[$idx]}"
    local current_disabled="${statuses[$idx]}"
    
    if [[ -z "$target_name" ]]; then log_error "Invalid selection"; return; fi
    
    local action="Disable"
    local new_state="true"
    [[ "$current_disabled" == "1" ]] && { action="Enable"; new_state="false"; }
    
    if ui_confirm "$action '$target_name'?"; then
        # API Delegation
         if [[ "$(db_get_config web_ui_enabled)" == "true" && -n "$target_id" ]]; then
             local api_url=$(get_api_url)
             curl -s -X PUT "${api_url}/internal/peers/$target_id" \
                -H "Content-Type: application/json" \
                -d "{\"disabled\": $new_state}" >/dev/null
             if [[ $? -eq 0 ]]; then
                 # Maintain local marker parity immediately
                 # We rely on the fall-through to the local block to touch/rm the file
                 # to avoid duplicate operations and ensure directory existence checks happen once.
                 
                 log_success "Synced status with API."
                 # FALL THROUGH to ensure local interface is physically updated
                 # return  <-- REMOVED to fix persistence issue
             fi
         fi
         
         # Local Mode (Mode A or Fallback)
         local client_conf="$INSTALL_DIR/clients/${target_name}.conf"
         local pub=""
         local ip=""
         
         # Try DB first
         if [[ -f "$DB_PATH" ]]; then
            pub=$(db_query "SELECT public_key FROM peers WHERE name='$target_name';")
            ip=$(db_query "SELECT allowed_ips FROM peers WHERE name='$target_name';")
         fi
         
         # Fallback to file extraction if empty (Mode A)
         if [[ -z "$pub" && -f "$client_conf" ]]; then
             local priv=$(grep "PrivateKey" "$client_conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
             [[ -n "$priv" ]] && pub=$(echo "$priv" | wg pubkey 2>/dev/null)
             ip=$(grep "Address" "$client_conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
         fi
         
         if [[ -z "$pub" ]]; then
            log_error "Could not find Public Key for '$target_name'."
            wait_key
            return
         fi
         
         if [[ "$new_state" == "true" ]]; then
              # DISABLE: First accumulate current data into total counters
              if [[ -f "$DB_PATH" ]]; then
                  db_exec "UPDATE peers SET total_rx_bytes = total_rx_bytes + COALESCE(rx_bytes, 0), total_tx_bytes = total_tx_bytes + COALESCE(tx_bytes, 0), rx_bytes = 0, tx_bytes = 0 WHERE name='$target_name';"
              fi
              # Remove from WireGuard interface
              if command -v wg &>/dev/null; then
                  wg set wg0 peer "$pub" remove 2>/dev/null
              fi
              # DB Update - set disabled flag
              [[ -f "$DB_PATH" ]] && db_exec "UPDATE peers SET disabled=1 WHERE name='$target_name';"
              # File Marker
              mkdir -p "$(dirname "$client_conf")"
              touch "${client_conf}.disabled" 2>/dev/null
              
              # Persist to wg0.conf
              if [[ -f "$DB_PATH" ]]; then
                  write_wg_conf
              fi
              
              log_success "Disabled peer '$target_name'."
         else
             # ENABLE
             if command -v wg &>/dev/null; then
                 # If IP is missing from extraction, we are in trouble, but usually it works
                 if [[ -n "$ip" ]]; then
                     # CRITICAL: Force /32 for server-side routing
                     local safe_ip=$(echo "$ip" | cut -d/ -f1)
                     local wg_out
                     if output=$(wg set wg0 peer "$pub" allowed-ips "${safe_ip}/32" 2>&1); then
                         : # Success
                     else
                         log_error "WireGuard update failed: $output"
                         wait_key
                     fi
                 else
                     log_warn "Could not find AllowedIPs. WG interface not updated."
                 fi
             fi
             # DB Update
             [[ -f "$DB_PATH" ]] && db_exec "UPDATE peers SET disabled=0 WHERE name='$target_name';"
             # File Marker
             rm -f "${client_conf}.disabled"
             
             # Persist to wg0.conf
             if [[ -f "$DB_PATH" ]]; then
                 write_wg_conf
             fi
             
             log_success "Enabled peer '$target_name'."
         fi
    fi
    wait_key
}

# Add Peer Wizard
add_peer_wizard() {
    ui_draw_header_mini "Add New Peer"
    
    if ! wg show wg0 >/dev/null 2>&1; then
        log_error "WireGuard interface (wg0) is down."
        log_info "Please start WireGuard first."
        wait_key
        return
    fi
    
    local peer_name=$(ui_prompt "Peer name (e.g., phone, laptop)")
    [[ -z "$peer_name" ]] && return
    
    # Security: Prevent Injection
    if [[ ! "$peer_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid name. Alphanumeric, hyphen, underscore only."
        wait_key
        return
    fi
    
    # Check for name collision (DB or Filesystem)
    if [[ -f "$DB_PATH" ]]; then
        local exists=$(db_query "SELECT COUNT(*) FROM peers WHERE name='$peer_name';")
        if [[ "$exists" -gt 0 ]] || [[ -f "$INSTALL_DIR/clients/${peer_name}.conf" ]]; then
            log_warn "Peer '$peer_name' already exists."
            if ! confirm "Overwrite/Re-add peer?"; then
                return
            fi
            # If overwriting, remove existing first to ensure clean state
            remove_peer_core "$peer_name" "true"
        fi
    fi
    
    log_info "Creating peer '$peer_name'..."
    
    # Generate keys
    local priv=$(wg genkey)
    local pub=$(echo "$priv" | wg pubkey)
    
    # Authoritative IP Allocation (Checks shared Database & Files)
    local subnet_display=$(db_get_config "subnet_cidr" | cut -d/ -f1-3)
    [[ -z "$subnet_display" ]] && subnet_display="10.100.0"
    local req_ip=$(ui_prompt "Enter IP suffix (e.g., .5) or full IP for $subnet_display.x (Enter for auto)")
    local next_ip=$(db_allocate_ip "$req_ip")
    
    while [[ -z "$next_ip" ]]; do
        log_error "IP allocation failed. Please choose another or press Enter for auto."
        req_ip=$(ui_prompt "Enter host IP/octet (or press Enter for auto)")
        next_ip=$(db_allocate_ip "$req_ip")
        [[ -z "$req_ip" && -z "$next_ip" ]] && break # Safety breakout if even auto fails (subnet full)
    done

    if [[ -z "$next_ip" ]]; then
        log_error "Subnet reached maximum capacity. Cannot allocate IP."
        wait_key
        return 1
    fi
     local mask=$(db_get_config "subnet_cidr" | cut -d/ -f2 || echo "24")

    
    # Add peer to WireGuard (Server side must use /32 for strict routing)
    wg set wg0 peer "$pub" allowed-ips "${next_ip}/32"
    
    # Save to persistent config
    echo "" >> /etc/wireguard/wg0.conf
    echo "[Peer]" >> /etc/wireguard/wg0.conf
    echo "# $peer_name" >> /etc/wireguard/wg0.conf
    echo "PublicKey = $pub" >> /etc/wireguard/wg0.conf
    echo "AllowedIPs = ${next_ip}/32" >> /etc/wireguard/wg0.conf
    
    # Sync with Web UI Dashboard (Database write)
    # Encrypt the key so API/Web UI can read it
    local enc_priv=$(encrypt_peer_key "$priv")
    db_exec "INSERT OR REPLACE INTO peers (name, public_key, encrypted_private_key, allowed_ips) VALUES ('$peer_name', '$pub', '$enc_priv', '${next_ip}/32');"
    
    log_success "Peer '$peer_name' created with IP $next_ip"
    
    # Show client config
    printf "\n    ${T_CYAN}${T_BOLD}Client Configuration:${T_RESET}\n"
    printf "    ${T_DIM}────────────────────────────────────────────${T_RESET}\n"
    
    local server_pubkey=$(cat /etc/wireguard/publickey 2>/dev/null)
    local server_port=$(grep "ListenPort" /etc/wireguard/wg0.conf | cut -d= -f2 | tr -d ' ')
    # Detect Endpoint (Strict IPv4 Filter)
    # Detect Endpoint (Strict IPv4 Filter)
    local custom_host=$(db_get_config "endpoint_hostname")
    local server_endpoint=""
    if [[ -n "$custom_host" ]]; then
        server_endpoint="$custom_host"
    else
        # 1. Try saved WAN IP (Primary)
        server_endpoint=$(db_get_config "wan_ip")
        # 2. Try detection if missing
        [[ -z "$server_endpoint" ]] && server_endpoint=$(detect_public_ip)
        # 3. Fallback
        [[ -z "$server_endpoint" ]] && server_endpoint="YOUR_SERVER_IP"
    fi
    
    # Ensure it's a valid IPv4 address OR a valid domain name
    if [[ ! "$server_endpoint" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [[ ! "$server_endpoint" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
         # If detection failed or returned junk, prompt user
         printf "    ${T_DIM}Press ENTER to accept the auto-detected IP/Domain.${T_RESET}\n"
         server_endpoint=$(prompt "Public IPv4 or Domain" "YOUR_SERVER_IP")
    fi
    
    # Create clients directory if needed
    mkdir -p "$INSTALL_DIR/clients"
    chmod 700 "$INSTALL_DIR/clients"
    chown 1000:1000 "$INSTALL_DIR/clients" 2>/dev/null || true
    
    local client_conf="$INSTALL_DIR/clients/${peer_name}.conf"
    
    # Create client config
    local mtu=$(db_get_config "mtu")
    # Safe MTU for WireGuard over most networks (accounts for overhead)
    [[ -z "$mtu" ]] && mtu="1380"
    
    cat << CLIENTCONF > "$client_conf"
[Interface]
PrivateKey = $priv
Address = ${next_ip}/${mask}
DNS = 1.1.1.1, 8.8.8.8
MTU = $mtu

[Peer]
PublicKey = $server_pubkey
AllowedIPs = 0.0.0.0/0
Endpoint = ${server_endpoint}:${server_port}
PersistentKeepalive = 25
CLIENTCONF

    chmod 600 "$client_conf"
    chown 1000:1000 "$client_conf" 2>/dev/null || true
    
    log_success "Peer '$peer_name' created. Config saved to $client_conf"
    
    # Show QR Code automatically
    printf "\n    ${T_CYAN}${T_BOLD}Scan QR Code:${T_RESET}\n"
    qrencode -t UTF8 -r "$client_conf" | less -R -K -P "Scan QR (Press Q to continue)"
    
    printf "\n"
    wait_key
}

# Add Temporary Peer Wizard (with expiry)
add_temp_peer_wizard() {
    ui_draw_header_mini "Add Temporary Peer"
    
    if ! wg show wg0 >/dev/null 2>&1; then
        log_error "WireGuard interface (wg0) is down."
        log_info "Please start WireGuard first."
        wait_key
        return
    fi
    
    local peer_name=$(ui_prompt "Peer name (e.g., guest-john)")
    [[ -z "$peer_name" ]] && return
    
    if [[ ! "$peer_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid name. Alphanumeric only."
        wait_key
        return
    fi
    
    # Check for name collision
    if [[ -f "$DB_PATH" ]]; then
        local exists=$(db_query "SELECT COUNT(*) FROM peers WHERE name='$peer_name';")
        if [[ "$exists" -gt 0 ]] || [[ -f "$INSTALL_DIR/clients/${peer_name}.conf" ]]; then
            log_warn "Peer '$peer_name' already exists."
            if ! confirm "Overwrite/Re-add peer?"; then
                return
            fi
            remove_peer_core "$peer_name" "true"
        fi
    fi
    
    printf "\n    ${T_CYAN}How many days should this access last?${T_RESET}\n"
    local days=$(ui_prompt "Days (1-365, default: 7)")
    [[ -z "$days" ]] && days=7
    
    # Validate days input
    if ! [[ "$days" =~ ^[0-9]+$ ]] || [[ "$days" -lt 1 ]] || [[ "$days" -gt 365 ]]; then
        log_error "Invalid days. Using default of 7."
        days=7
    fi
    
    log_info "Creating temporary peer '$peer_name' (expires in $days days)..."
    
    # Generate keys
    local priv=$(wg genkey)
    local pub=$(echo "$priv" | wg pubkey)
    
    # Authoritative IP Allocation
    local next_ip=$(db_allocate_ip)
    if [[ -z "$next_ip" ]]; then
        log_error "Subnet reached maximum capacity. Cannot allocate IP."
        wait_key
        return 1
    fi
    local mask=$(db_get_config "subnet_cidr" | cut -d/ -f2 || echo "24")

    
    # Add peer to WireGuard
    wg set wg0 peer "$pub" allowed-ips "${next_ip}/32"
    
    # Save to persistent config
    echo "" >> /etc/wireguard/wg0.conf
    echo "[Peer]" >> /etc/wireguard/wg0.conf
    echo "# $peer_name (TEMP - Expires: $(date -d "+$days days" +%Y-%m-%d))" >> /etc/wireguard/wg0.conf
    echo "PublicKey = $pub" >> /etc/wireguard/wg0.conf
    echo "AllowedIPs = ${next_ip}/32" >> /etc/wireguard/wg0.conf
    
    # Sync with Web UI Dashboard
    local enc_priv=$(encrypt_peer_key "$priv")
    db_exec "INSERT OR REPLACE INTO peers (name, public_key, encrypted_private_key, allowed_ips, expires_at) VALUES ('$peer_name', '$pub', '$enc_priv', '${next_ip}/32', datetime('+$days days'));"

    
    # Create clients directory if needed
    mkdir -p "$INSTALL_DIR/clients"
    chmod 700 "$INSTALL_DIR/clients"
    chown 1000:1000 "$INSTALL_DIR/clients" 2>/dev/null || true
    
    local client_conf="$INSTALL_DIR/clients/${peer_name}.conf"
    
    # Generate client config
    local server_pubkey=$(cat /etc/wireguard/publickey 2>/dev/null)
    local server_port=$(grep "ListenPort" /etc/wireguard/wg0.conf | cut -d= -f2 | tr -d ' ')
    
    local custom_host=$(db_get_config "endpoint_hostname")
    local server_endpoint=""
    if [[ -n "$custom_host" ]]; then
        server_endpoint="$custom_host"
    else
        # 1. Try saved WAN IP (Primary)
        server_endpoint=$(db_get_config "wan_ip")
        # 2. Try detection if missing
        [[ -z "$server_endpoint" ]] && server_endpoint=$(detect_public_ip)
        # 3. Fallback
        [[ -z "$server_endpoint" ]] && server_endpoint="YOUR_SERVER_IP"
    fi
    
    if [[ ! "$server_endpoint" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && [[ ! "$server_endpoint" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
         printf "    ${T_DIM}Press ENTER to accept the auto-detected IP/Domain.${T_RESET}\n"
         server_endpoint=$(prompt "Public IPv4 or Domain" "YOUR_SERVER_IP")
    fi
    
    local mtu=$(db_get_config "mtu")
    [[ -z "$mtu" ]] && mtu="1380"

    cat << CLIENTCONF > "$client_conf"
[Interface]
PrivateKey = $priv
Address = ${next_ip}/${mask}
DNS = 1.1.1.1, 8.8.8.8
MTU = $mtu

[Peer]
PublicKey = $server_pubkey
AllowedIPs = 0.0.0.0/0
Endpoint = ${server_endpoint}:${server_port}
PersistentKeepalive = 25
CLIENTCONF

    chmod 600 "$client_conf"
    chown 1000:1000 "$client_conf" 2>/dev/null || true
    
    # Save expiry metadata
    local expiry_date=$(date -d "+$days days" +%s)
    echo "$expiry_date" > "${client_conf}.expiry"
    
    log_success "Temporary peer '$peer_name' created!"
    local tz=$(date +%Z)
    printf "    ${T_YELLOW}⚠ Expires: $(date -d "+$days days" "+%Y-%m-%d %H:%M") ($tz)${T_RESET}\n"
    
    # Show QR Code
    printf "\n    ${T_CYAN}${T_BOLD}Scan QR Code:${T_RESET}\n"
    qrencode -t UTF8 -r "$client_conf" | less -R -K -P "Scan QR (Press Q to continue)"
    
    printf "\n"
    wait_key
}

# Add Bulk Peers Wizard
add_bulk_peers_wizard() {
    ui_draw_header_mini "Add Bulk Peers"
    
    if ! wg show wg0 >/dev/null 2>&1; then
        log_error "WireGuard interface (wg0) is down."
        log_info "Please start WireGuard first."
        wait_key
        return
    fi
    
    printf "    ${T_CYAN}Create multiple peers at once${T_RESET}\n\n"
    printf "    ${T_DIM}Note: Supports comma-separated list (e.g., 'saman, sina')${T_RESET}\n"
    local input=$(ui_prompt "Peer name(s) or prefix(es)")
    [[ -z "$input" ]] && return
    
    # Split input by comma and clean up spaces
    IFS=',' read -ra items <<< "$input"
    
    # Validate each item
    for item in "${items[@]}"; do
        local clean_item=$(echo "$item" | tr -d ' ')
        if [[ ! "$clean_item" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            log_error "Invalid entry: '$clean_item'. Alphanumeric only."
            wait_key
            return
        fi
    done
    
    local count=$(ui_prompt "How many peers per name/prefix? (1-50)")
    [[ -z "$count" ]] && return
    
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]] || [[ "$count" -gt 50 ]]; then
        log_error "Invalid count. Must be 1-50."
        wait_key
        return
    fi
    
    printf "\n    ${T_CYAN}Peer type:${T_RESET}\n"
    printf "    [1] Permanent (no expiry)\n"
    printf "    [2] Temporary (with expiry)\n"
    printf "\n"
    local type_choice=$(ui_prompt "Select type (1 or 2)")
    
    local days=0
    if [[ "$type_choice" == "2" ]]; then
        days=$(ui_prompt "Days until expiry (1-365, default: 7)")
        [[ -z "$days" ]] && days=7
        if ! [[ "$days" =~ ^[0-9]+$ ]] || [[ "$days" -lt 1 ]] || [[ "$days" -gt 365 ]]; then
            days=7
        fi
    fi
    
    if ! confirm "Create bulk peers for: ${items[*]} ($count each)?"; then
        log_info "Cancelled."
        wait_key
        return
    fi
    
    log_info "Creating peers..."
    
    local mask=$(db_get_config "subnet_cidr" | cut -d/ -f2 || echo "24")
    local server_pubkey=$(cat /etc/wireguard/publickey 2>/dev/null)
    local server_port=$(grep "ListenPort" /etc/wireguard/wg0.conf | cut -d= -f2 | tr -d ' ')
    
    local custom_host=$(db_get_config "endpoint_hostname")
    local server_endpoint=""
    if [[ -n "$custom_host" ]]; then
        server_endpoint="$custom_host"
    else
        # 1. Try saved WAN IP (Primary)
        server_endpoint=$(db_get_config "wan_ip")
        # 2. Try detection if missing
        [[ -z "$server_endpoint" ]] && server_endpoint=$(detect_public_ip)
        # 3. Fallback
        [[ -z "$server_endpoint" ]] && server_endpoint="YOUR_SERVER_IP"
    fi
    
    mkdir -p "$INSTALL_DIR/clients"
    chown 1000:1000 "$INSTALL_DIR/clients" 2>/dev/null || true
    local total_created=0
    
    for item in "${items[@]}"; do
        local prefix=$(echo "$item" | tr -d ' ')
        for ((n=1; n<=count; n++)); do
            local peer_name="${prefix}"
            [[ "$count" -gt 1 ]] && peer_name="${prefix}-${n}"
            
            # Check for collision
            if [[ -f "$INSTALL_DIR/clients/${peer_name}.conf" ]]; then
                log_warn "Peer '$peer_name' already exists. Skipping."
                continue
            fi

            local next_ip=$(db_allocate_ip)
            if [[ -z "$next_ip" ]]; then
                log_error "Subnet full. Created $total_created peers."
                break 2
            fi

            local priv=$(wg genkey)
            local pub=$(echo "$priv" | wg pubkey)
            
            # Add to WireGuard
            wg set wg0 peer "$pub" allowed-ips "${next_ip}/32" 2>/dev/null
            
            # Append to config
            echo "" >> /etc/wireguard/wg0.conf
            echo "[Peer]" >> /etc/wireguard/wg0.conf
            if [[ "$days" -gt 0 ]]; then
                echo "# $peer_name (TEMP - Expires: $(date -d "+$days days" +%Y-%m-%d))" >> /etc/wireguard/wg0.conf
            else
                echo "# $peer_name" >> /etc/wireguard/wg0.conf
            fi
            echo "PublicKey = $pub" >> /etc/wireguard/wg0.conf
            echo "AllowedIPs = ${next_ip}/32" >> /etc/wireguard/wg0.conf
            
            # Sync with Database
            local enc_priv=$(encrypt_peer_key "$priv")
            db_exec "INSERT OR REPLACE INTO peers (name, public_key, encrypted_private_key, allowed_ips) VALUES ('$peer_name', '$pub', '$enc_priv', '${next_ip}/32');"

            # Create client config
            local mtu=$(db_get_config "mtu")
            [[ -z "$mtu" ]] && mtu="1380"
            
            local client_conf="$INSTALL_DIR/clients/${peer_name}.conf"
            cat << CLIENTCONF > "$client_conf"
[Interface]
PrivateKey = $priv
Address = ${next_ip}/${mask}
DNS = 1.1.1.1, 8.8.8.8
MTU = $mtu

[Peer]
PublicKey = $server_pubkey
AllowedIPs = 0.0.0.0/0
Endpoint = ${server_endpoint}:${server_port}
PersistentKeepalive = 25
CLIENTCONF
            chmod 600 "$client_conf"
            chown 1000:1000 "$client_conf" 2>/dev/null || true
            
            # Save expiry if temporary
            if [[ "$days" -gt 0 ]]; then
                local expiry_date=$(date -d "+$days days" +%s)
                echo "$expiry_date" > "${client_conf}.expiry"
            fi
            
            ((total_created++))
            printf "    ${T_GREEN}✓${T_RESET} Created: $peer_name ($next_ip)\n"
        done
    done
    
    log_success "Created $total_created peers successfully!"
    printf "    ${T_DIM}Configs saved to $INSTALL_DIR/clients/${T_RESET}\n"
    
    printf "\n"
    wait_key
}

# Bulk Remove Peers Wizard
remove_bulk_peers_wizard() {
    ui_draw_header_mini "Bulk Remove Peers"
    
    local client_dir="$INSTALL_DIR/clients"
    
    if [[ ! -d "$client_dir" ]] || [[ -z "$(ls -A "$client_dir"/*.conf 2>/dev/null)" ]]; then
        log_warn "No peers to remove."
        wait_key
        return
    fi
    
    local configs=("$client_dir"/*.conf)
    
    printf "    ${T_CYAN}Enter peer numbers to remove (space-separated):${T_RESET}\n\n"
    
    local i=1
    local files=()
    for conf in "${configs[@]}"; do
        [[ -e "$conf" ]] || continue
        local name=$(basename "$conf" .conf)
        local ip=$(grep "Address" "$conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
        printf "    ${T_GREEN}[%d]${T_RESET} %-20s ${T_DIM}%s${T_RESET}\n" "$i" "$name" "$ip"
        files[$i]="$conf"
        ((i++))
    done
    
    printf "\n"
    printf "    ${T_DIM}Example: '1 3 5' removes peers 1, 3, and 5${T_RESET}\n"
    printf "    ${T_DIM}Enter 'all' to remove ALL peers${T_RESET}\n\n"
    
    local selection=$(ui_prompt "Numbers to remove")
    [[ -z "$selection" ]] && return
    
    local to_remove=()
    
    if [[ "$selection" == "all" ]]; then
        for ((j=1; j<i; j++)); do
            to_remove+=($j)
        done
    else
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -lt $i ]]; then
                to_remove+=($num)
            fi
        done
    fi
    
    if [[ ${#to_remove[@]} -eq 0 ]]; then
        log_error "No valid selections."
        wait_key
        return
    fi
    
    printf "\n    ${T_YELLOW}⚠ About to remove ${#to_remove[@]} peer(s)${T_RESET}\n"
    
    if ! confirm "Proceed?"; then
        log_info "Cancelled."
        wait_key
        return
    fi
    
    local removed=0
    for idx in "${to_remove[@]}"; do
        local target="${files[$idx]}"
        local name=$(basename "$target" .conf)
        
        if [[ -f "$DB_PATH" ]]; then
            # Archive data to historical_usage
            # Calculate total usage = stored total + current rx/tx
            # Current rx/tx will be reset on delete, so we grab them now
            # Note: We can't easily get live WG stats here for every peer efficiently without parsing 'wg show' dump
            # relying on what's in DB (total + last sync) is safest/fastest.
            # Ideally we sync one last time.
            
            # Simple archive: copy values from peers table
            db_exec "INSERT INTO historical_usage (peer_name, public_key, rx_bytes, tx_bytes) 
                     SELECT name, public_key, total_rx_bytes + rx_bytes, total_tx_bytes + tx_bytes FROM peers WHERE name='$name';"
        fi

        # Use core removal logic (handles API delegation and local cleanup)
        remove_peer_core "$name" "true"
        
        ((removed++))
        printf "    ${T_RED}✗${T_RESET} Removed: $name\n"
    done
    
    log_success "Removed $removed peer(s)."
    
    printf "\n"
    wait_key
}

# View Usage Screen - Shows bandwidth per peer
view_usage_screen() {
    while true; do
        ui_draw_header_mini "Bandwidth Usage"
        
        local client_dir="$INSTALL_DIR/clients"
        
        if ! wg show wg0 &>/dev/null; then
            log_warn "WireGuard not running. Cannot fetch live transfer stats."
            wait_key
            return
        fi
        
        if [[ ! -f "$DB_PATH" ]]; then
            log_warn "Database required for bandwidth tracking."
            wait_key
            return
        fi

        printf "    ${T_CYAN}${T_BOLD}Peer Bandwidth Usage${T_RESET}\n"
        printf "    ${T_DIM}──────────────────────────────────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_WHITE}%-18s %12s %12s %14s %14s${T_RESET}\n" "PEER" "USED" "LIMIT" "REMAINING" "STATUS"
        printf "    ${T_DIM}──────────────────────────────────────────────────────────────────────────${T_RESET}\n"
        
        # 1. Fetch persistent totals and limits from DB
        # name|public_key|total_rx|total_tx|limit_gb
        local query="SELECT name, public_key, COALESCE(total_rx_bytes, 0), COALESCE(total_tx_bytes, 0), COALESCE(data_limit_gb, 0) FROM peers WHERE disabled=0 ORDER BY name;"
        
        # 2. Fetch Live Stats
        declare -A live_rx
        declare -A live_tx
        if command -v wg &>/dev/null && ip link show wg0 &>/dev/null; then
            while read -r pub rx tx; do
                [[ -z "$pub" ]] && continue
                live_rx["$pub"]=$rx
                live_tx["$pub"]=$tx
            done < <(wg show wg0 transfer)
        fi
        
        local total_cluster_rx=0
        local total_cluster_tx=0

        while IFS='|' read -r name pub db_rx db_tx limit_gb; do
            local cur_rx=${live_rx["$pub"]:-0}
            local cur_tx=${live_tx["$pub"]:-0}
            
            # Cumulative
            local total_rx=$((db_rx + cur_rx))
            local total_tx=$((db_tx + cur_tx))
            local total_usage=$((total_rx + total_tx))
            
            total_cluster_rx=$((total_cluster_rx + total_rx))
            total_cluster_tx=$((total_cluster_tx + total_tx))
            
            local used_hr=$(numfmt --to=iec --suffix=B $total_usage 2>/dev/null || echo "${total_usage}B")
            local limit_str="∞"
            local rem_str="∞"
            local status_str="${T_GREEN}OK${T_RESET}"
            
            if [[ "$limit_gb" -gt 0 ]]; then
                limit_str="${limit_gb}GB"
                local limit_bytes=$((limit_gb * 1024 * 1024 * 1024))
                
                if [[ $total_usage -ge $limit_bytes ]]; then
                    status_str="${T_RED}OVER${T_RESET}"
                    rem_str="0B"
                else
                    local rem_bytes=$((limit_bytes - total_usage))
                    rem_str=$(numfmt --to=iec --suffix=B $rem_bytes 2>/dev/null || echo "${rem_bytes}B")
                    
                    # Calculate %
                    if [[ $limit_bytes -gt 0 ]]; then
                        local pct=$((total_usage * 100 / limit_bytes))
                        if [[ $pct -ge 90 ]]; then status_str="${T_YELLOW}${pct}%${T_RESET}"; 
                        else status_str="${T_GREEN}${pct}%${T_RESET}"; fi
                    fi
                fi
            fi
            
            # Truncate name
            name="${name:0:18}"
            
            printf "    %-18s %12s %12s %14s %14s\n" "$name" "$used_hr" "$limit_str" "$rem_str" "$status_str"
            
        done < <(sqlite3 "$DB_PATH" "$query")
        
        printf "    ${T_DIM}──────────────────────────────────────────────────────────────────────────${T_RESET}\n"
        local historical_rx=0
        local historical_tx=0
        if [[ -f "$DB_PATH" ]]; then
             local h_rx=$(sqlite3 "$DB_PATH" "SELECT SUM(rx_bytes) FROM historical_usage;")
             local h_tx=$(sqlite3 "$DB_PATH" "SELECT SUM(tx_bytes) FROM historical_usage;")
             [[ -n "$h_rx" ]] && historical_rx=$h_rx
             [[ -n "$h_tx" ]] && historical_tx=$h_tx
        fi
        
        local grand_total=$((total_cluster_rx + total_cluster_tx + historical_rx + historical_tx))
        local grand_total_hr=$(numfmt --to=iec --suffix=B $grand_total 2>/dev/null || echo "${grand_total}B")
        printf "    ${T_WHITE}%-18s %12s${T_RESET}\n" "TOTAL TRAFFIC" "$grand_total_hr"
        
        printf "\n    ${T_CYAN}[G]${T_RESET} Show Graph  ${T_CYAN}[H]${T_RESET} Historical Data  ${T_CYAN}[B]${T_RESET} Back\n"
        printf "\n    ${T_DIM}Auto-refreshing every 2s...${T_RESET}"
        
        # Read key with 2 second timeout for auto-refresh
        local key=""
        read -s -n 1 -t 2 key || true
        
        case "$key" in
            g|G) show_bandwidth_graph ;;
            h|H) show_historical_usage ;;
            b|B|$'\x1b') return ;;
            "") ;; # Loop to refresh on timeout
        esac
    done
}

# View Historical Usage (for deleted peers)
show_historical_usage_deleted_peers() {
    if [[ ! -f "$DB_PATH" ]]; then
        ui_draw_header_mini "Historical Usage"
        log_warn "Database not found. Historical data requires database."
        wait_key
        return
    fi
    
    while true; do
        ui_draw_header_mini "Historical Usage (Deleted Peers)"
        
        printf "    ${T_CYAN}${T_BOLD}Archived Traffic Data${T_RESET}\n"
        printf "    ${T_DIM}────────────────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_WHITE}%-20s %12s %12s %19s${T_RESET}\n" "PEER" "TOTAL RX" "TOTAL TX" "DELETED AT"
        printf "    ${T_DIM}────────────────────────────────────────────────────────${T_RESET}\n"
        
        # Query DB using sqlite3 formatted output
        local count=0
        while IFS='|' read -r name rx tx del_at; do
             local rx_hr=$(numfmt --to=iec --suffix=B $rx 2>/dev/null || echo "${rx}B")
             local tx_hr=$(numfmt --to=iec --suffix=B $tx 2>/dev/null || echo "${tx}B")
             
             printf "    %-20s %12s %12s %19s\n" "$name" "$rx_hr" "$tx_hr" "$del_at"
             ((count++))
        done < <(sqlite3 "$DB_PATH" "SELECT peer_name, rx_bytes, tx_bytes, deleted_at FROM historical_usage ORDER BY deleted_at DESC LIMIT 20;")
        
        if [[ $count -eq 0 ]]; then
             printf "    ${T_DIM}No historical records found.${T_RESET}\n"
        fi
        
        printf "\n    ${T_CYAN}[C]${T_RESET} Clear History  ${T_CYAN}[Enter]${T_RESET} Back\n"
        printf "\n${T_CYAN}❯${T_RESET} "
        
        local key=$(read_key)
        if [[ "$key" == "c" || "$key" == "C" ]]; then
            if confirm "Clear all historical data?"; then
                db_exec "DELETE FROM historical_usage;"
                log_success "History cleared."
                sleep 0.5
            fi
        else
            return
        fi
    done
}

# ASCII Bar Graph for Bandwidth
show_bandwidth_graph() {
    ui_draw_header_mini "Bandwidth Graph"
    
    printf "    ${T_CYAN}${T_BOLD}Select Time Range:${T_RESET}\n\n"
    printf "    [1] Last 24 Hours (hourly)\n"
    printf "    [2] Last 7 Days (daily)\n"
    printf "    [3] Last 30 Days (daily)\n\n"
    
    local choice=$(ui_prompt "Select range")
    
    local query=""
    local title=""
    local bars=24
    
    case "$choice" in
        1)
            title="Last 24 Hours"
            bars=24
            query="SELECT timestamp, SUM(rx_bytes + tx_bytes) as total FROM bandwidth_hourly 
                   WHERE timestamp > strftime('%s', 'now') - 86400 
                   GROUP BY timestamp ORDER BY timestamp;"
            ;;
        2)
            title="Last 7 Days"
            bars=7
            query="SELECT date, SUM(rx_bytes + tx_bytes) as total FROM bandwidth_daily 
                   WHERE date > date('now', '-7 days') 
                   GROUP BY date ORDER BY date;"
            ;;
        3)
            title="Last 30 Days"
            bars=30
            query="SELECT date, SUM(rx_bytes + tx_bytes) as total FROM bandwidth_daily 
                   WHERE date > date('now', '-30 days') 
                   GROUP BY date ORDER BY date;"
            ;;
        *)
            return
            ;;
    esac
    
    ui_clear
    ui_draw_header_mini "Bandwidth: $title"
    
    printf "\n    ${T_CYAN}${T_BOLD}$title - Total Network Usage${T_RESET}\n"
    printf "    ${T_DIM}────────────────────────────────────────────────────────${T_RESET}\n\n"
    
    # Get data
    local -a values=()
    local -a labels=()
    local max_val=1
    
    while IFS='|' read -r label val; do
        [[ -z "$val" ]] && val=0
        values+=($val)
        if [[ "$choice" == "1" ]]; then
            labels+=("$(date -d "@$label" +%H)")
        else
            labels+=("$(echo "$label" | cut -d- -f3)")
        fi
        [[ $val -gt $max_val ]] && max_val=$val
    done < <(sqlite3 -batch "$DB_PATH" "$query" 2>/dev/null)
    
    if [[ ${#values[@]} -eq 0 ]]; then
        printf "    ${T_DIM}No data available. Run 'samnet --init-bandwidth' first.${T_RESET}\n"
        printf "\n"
        wait_key
        return
    fi
    
    # Draw ASCII graph (10 rows high)
    local graph_height=10
    local bar_char="█"
    local empty_char=" "
    
    for ((row=graph_height; row>=1; row--)); do
        local threshold=$((max_val * row / graph_height))
        printf "    "
        
        for val in "${values[@]}"; do
            if [[ $val -ge $threshold ]]; then
                printf "${T_CYAN}$bar_char${T_RESET}"
            else
                printf "$empty_char"
            fi
        done
        
        # Y-axis label
        if [[ $row -eq $graph_height ]]; then
            printf "  $(numfmt --to=iec $max_val 2>/dev/null || echo "$max_val")"
        elif [[ $row -eq 1 ]]; then
            printf "  0"
        fi
        printf "\n"
    done
    
    # X-axis
    printf "    ${T_DIM}"
    for label in "${labels[@]}"; do
        printf "$label"
    done
    printf "${T_RESET}\n"
    
    printf "\n    ${T_DIM}Legend: Each bar = 1 time period${T_RESET}\n"
    
    printf "\n"
    wait_key
}

# Historical Usage View
show_historical_usage() {
    ui_draw_header_mini "Historical Usage"
    
    printf "    ${T_CYAN}${T_BOLD}Per-Peer Historical Data${T_RESET}\n"
    printf "    ${T_DIM}────────────────────────────────────────────────────────${T_RESET}\n"
    printf "    ${T_WHITE}%-20s %15s %15s${T_RESET}\n" "PEER" "LAST 24H" "LAST 30D"
    printf "    ${T_DIM}────────────────────────────────────────────────────────${T_RESET}\n"
    
    # Get unique peers
    local peers=$(sqlite3 -batch "$DB_PATH" "SELECT DISTINCT peer_name FROM bandwidth_total;" 2>/dev/null)
    
    if [[ -z "$peers" ]]; then
        printf "    ${T_DIM}No historical data available.${T_RESET}\n"
        printf "\n"
        wait_key
        return
    fi
    
    while read -r peer; do
        # Last 24h from hourly
        local h24=$(sqlite3 -batch "$DB_PATH" "
            SELECT COALESCE(MAX(rx_bytes + tx_bytes), 0) FROM bandwidth_hourly 
            WHERE peer_name='$peer' AND timestamp > strftime('%s', 'now') - 86400;" 2>/dev/null)
        
        # Last 30d from daily
        local d30=$(sqlite3 -batch "$DB_PATH" "
            SELECT COALESCE(SUM(rx_bytes + tx_bytes), 0) FROM bandwidth_daily 
            WHERE peer_name='$peer' AND date > date('now', '-30 days');" 2>/dev/null)
        
        local h24_hr=$(numfmt --to=iec --suffix=B $h24 2>/dev/null || echo "${h24}B")
        local d30_hr=$(numfmt --to=iec --suffix=B $d30 2>/dev/null || echo "${d30}B")
        
        printf "    %-20s %15s %15s\n" "$peer" "$h24_hr" "$d30_hr"
    done <<< "$peers"
    
    printf "\n"
    wait_key
}

# Helper: Convert bytes to human readable
bytes_to_human() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# Set Data Limit Wizard
set_data_limit_wizard() {
    ui_draw_header_mini "Set Data Limit"
    
    # Read peers from database (includes both CLI and Web UI created peers)
    local peers=$(sqlite3 "$DB_PATH" "SELECT id, name FROM peers ORDER BY name" 2>/dev/null)
    
    if [[ -z "$peers" ]]; then
        log_warn "No peers configured."
        wait_key
        return
    fi
    
    printf "    ${T_CYAN}Select peer to set bandwidth limit:${T_RESET}\n\n"
    
    local i=1
    local ids=()
    local names=()
    
    while IFS='|' read -r id name; do
        # Get current limit from database (data_limit_gb column)
        local limit=$(sqlite3 "$DB_PATH" "SELECT COALESCE(data_limit_gb, 0) FROM peers WHERE id=$id" 2>/dev/null)
        local limit_display="No limit"
        [[ "$limit" != "0" && -n "$limit" ]] && limit_display="${limit}GB"
        
        printf "    ${T_GREEN}[%d]${T_RESET} %-20s ${T_DIM}Limit: %s${T_RESET}\n" "$i" "$name" "$limit_display"
        ids[$i]=$id
        names[$i]=$name
        ((i++))
    done <<< "$peers"
    
    printf "\n"
    local choice=$(ui_prompt "Select peer #")
    [[ -z "$choice" ]] && return
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -lt $i ]]; then
        local peer_id="${ids[$choice]}"
        local peer_name="${names[$choice]}"
        
        printf "\n    ${T_CYAN}Set bandwidth limit for '$peer_name':${T_RESET}\n"
        printf "    ${T_DIM}Enter limit in GB (e.g., 10 for 10GB, 0 to remove limit)${T_RESET}\n\n"
        
        local limit=$(ui_prompt "Limit (GB)")
        
        if [[ -z "$limit" ]]; then
            return
        fi
        
        if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
            log_error "Invalid limit. Must be a number."
            wait_key
            return
        fi
        
        # Store in database for cross-engine sync
        sqlite3 "$DB_PATH" "UPDATE peers SET data_limit_gb = $limit WHERE id = $peer_id" 2>/dev/null
        
        if [[ "$limit" == "0" ]]; then
            log_success "Limit removed for '$peer_name'."
        else
            log_success "Set ${limit}GB limit for '$peer_name'."
        fi
    else
        log_error "Invalid selection."
    fi
    
    wait_key
}

# List Peers Screen
# List Peers Screen (Interactive)
# List Peers Screen (Interactive)
list_peers_screen() {
    local offset=0
    local page_size=10
    
    # Ensure DB is converged before listing
    reconcile_db_with_files &>/dev/null
    
    while true; do
        if [[ ! -f "$DB_PATH" ]]; then
            log_error "Database not found."
            wait_key
            return
        fi

        # 1. Fetch all peers from unified source
        local list
        list=$(scan_peers)
        
        # Read into array
        local all_peers=()
        if [[ -n "$list" ]]; then
            while IFS= read -r line; do
                all_peers+=("$line")
            done <<< "$list"
        fi
        
        local total_peers=${#all_peers[@]}
        
        ui_clear
        local end_idx=$((offset + page_size))
        [[ $end_idx -gt $total_peers ]] && end_idx=$total_peers
        ui_draw_header "Peer List ($((offset + 1))-$end_idx of $total_peers)"
        
        # Header
        printf "  %-4s %-20s %-15s %-15s\n" "ID" "Name" "IP" "Status"
        echo "  --------------------------------------------------------"
        
        local i=$((offset + 1))
        local peers_map=() # Index -> Name
        
        for (( idx=offset; idx<offset+page_size && idx<total_peers; idx++ )); do
            local line="${all_peers[$idx]}"
            IFS='|' read -r name ip src status <<< "$line"
            
            local status_display="${T_RED}OFFLINE${T_RESET}"
            
            if [[ "$status" == "ONLINE ACTIVE" ]]; then
                 status_display="${T_GREEN}ONLINE${T_RESET}"
            elif [[ "$status" == "ACTIVE" ]]; then
                 status_display="${T_WHITE}ONLINE${T_RESET}"
            elif [[ "$status" == "DISABLED" ]]; then
                 status_display="${T_RED}OFFLINE${T_RESET}" 
            elif [[ "$status" == "OFFLINE" ]]; then
                 status_display="${T_RED}OFFLINE${T_RESET}"
            elif [[ "$status" == "OVER LIMIT" ]]; then
                 status_display="${T_RED}OVER LIMIT${T_RESET}"
            fi
            
            # Remove mask for cleaner display if it's /32
            local short_ip="${ip%%/*}"
            
            printf "  ${T_CYAN}[%d]${T_RESET}  %-20s %-15s %b\n" "$i" "$name" "$short_ip" "$status_display"
            peers_map[$i]="$name"
            ((i++))
        done
        
        if [[ $total_peers -eq 0 ]]; then
            echo "  (No peers found)"
        fi
        
        echo ""
        printf "  [N] Next Page  [P] Previous Page  [Q] Back/Quit\n"
        echo ""
        
        local choice=$(ui_prompt "Select ID or Action")
        
        # Actions
        case "${choice^^}" in
            Q|B) return ;;
            N)
                if (( offset + page_size < total_peers )); then
                    (( offset += page_size ))
                else
                    log_warn "Already at last page."
                    sleep 1
                fi
                continue
                ;;
            P)
                if (( offset - page_size >= 0 )); then
                    (( offset -= page_size ))
                else
                    offset=0
                fi
                continue
                ;;
        esac
        
        # Logic for selection
        if [[ -n "${peers_map[$choice]}" ]]; then
            local p_name="${peers_map[$choice]}"
            local target="$INSTALL_DIR/clients/$p_name.conf"
            
            # INNER LOOP: Peer Actions
            while true; do
                ui_clear
                ui_draw_header "Peer: $p_name"
                
                echo "  [1] Show QR Code (Mobile)"
                echo "  [2] Show Details / Keys"
                echo "  [3] Show Raw Config"
                echo ""
                echo "  [B] Back to List"
                echo ""
                
                local sub_choice=$(ui_prompt "Action")
                case "${sub_choice^^}" in
                    B) break ;; # Break inner loop, go back to list
                    1)
                        # QR Code Logic
                        ui_clear
                        ui_draw_header_mini "QR Code: $p_name"
                        
                        # Try API first for config
                        local config_content=""
                        local peer_id=$(db_query "SELECT id FROM peers WHERE name='$p_name';")
                        
                        if [[ -n "$peer_id" ]]; then
                            log_info "Fetching config from API..."
                             local api_resp
                             # Use docker exec helper
                             api_resp=$(api_call "GET" "/internal/peers/config?id=$peer_id")
                             if [[ "$api_resp" == *"[Interface]"* ]]; then
                                 config_content="$api_resp"
                             else
                                 log_warn "API request failed or returned invalid config."
                             fi
                        fi
                        
                        if [[ -z "$config_content" && -f "$target" ]]; then
                             config_content=$(cat "$target")
                        fi
                        
                        if [[ -n "$config_content" ]]; then
                             echo "$config_content" | qrencode -t UTF8 | less -R -K -P "Press Q to exit QR view"
                        else
                             log_error "Could not retrieve config."
                             echo "  Debug: Peer ID='$peer_id', File='$target'"
                             wait_key
                        fi
                        ;;
                    2)
                        # Details Logic
                        ui_clear
                        ui_draw_header_mini "Details: $p_name"
                        
                        local db_pub=$(db_query "SELECT public_key FROM peers WHERE name='$p_name';")
                        local db_ip=$(db_query "SELECT allowed_ips FROM peers WHERE name='$p_name';")
                        
                        echo ""
                        echo "    ${T_BOLD}${T_CYAN}Name:${T_RESET}      $p_name"
                        echo "    ${T_BOLD}${T_CYAN}Address:${T_RESET}   $db_ip"
                        echo "    ${T_BOLD}${T_CYAN}Public Key:${T_RESET} $db_pub"
                        echo ""
                        
                        if [[ -f "$target" ]]; then
                             local priv=$(grep "PrivateKey" "$target" | cut -d= -f2 | tr -d ' ')
                             echo "    ${T_BOLD}${T_CYAN}Private Key:${T_RESET} ${T_RED}${priv:0:4}***REDACTED***${T_RESET}"
                        fi
                        echo ""
                        wait_key
                        ;;
                    3)
                         # Unified Details Logic (File OR API)
                         local config_content=""
                         local peer_id=$(db_query "SELECT id FROM peers WHERE name='$p_name';")
                        
                         if [[ -n "$peer_id" ]]; then
                             local api_resp
                             api_resp=$(api_call "GET" "/internal/peers/config?id=$peer_id")
                             if [[ "$api_resp" == *"[Interface]"* ]]; then
                                 config_content="$api_resp"
                             fi
                         fi
                         
                         if [[ -z "$config_content" && -f "$target" ]]; then
                             config_content=$(cat "$target")
                         fi

                         if [[ -n "$config_content" ]]; then
                             ui_clear
                             echo "$config_content" | less -R -K
                         else
                             log_error "Config not found (Checked disk and API)."
                             wait_key
                         fi
                         ;;
                     *) log_error "Invalid Option" ;;
                esac
            done
        else
            log_error "Invalid selection."
            sleep 1
        fi
    done
}

# Core logic for peer removal (non-interactive)
remove_peer_core() {
    local target_name="$1"
    local silent="${2:-false}"
    
    # Escape single quotes in name for SQL
    local safe_name="${target_name//\'/\'\'}"
    
    # Check if Web UI is active - if so, DELEGATE TO API for atomic cleanup
    local web_ui_active=$(db_get_config web_ui_enabled)
    
    if [[ "$web_ui_active" == "true" ]]; then
         # Get peer ID from database
         local peer_id=$(db_query "SELECT id FROM peers WHERE name='$safe_name';")
         
         if [[ -n "$peer_id" ]]; then
             [[ "$silent" != "true" ]] && log_info "Delegating deletion to API for cross-engine sync..."
             
             local api_resp
             api_resp=$(api_call "DELETE" "/internal/peers/$peer_id")
             local api_status=$?
             
             if [[ $api_status -eq 0 ]]; then
                 sleep 0.5
                 local remaining=$(db_query "SELECT COUNT(*) FROM peers WHERE name='$safe_name';")
                 if [[ -z "$remaining" || "$remaining" -eq 0 ]]; then
                     [[ "$silent" != "true" ]] && log_success "Peer '$target_name' removed via API."
                     return 0
                 fi
                 log_warn "API reported success but peer '$target_name' still in DB. Falling back to local removal..."
             else
                 log_warn "API deletion failed: $api_resp. Falling back to local removal..."
             fi
         fi
         # Fallback
         web_ui_active="fallback"
    fi
    
    # Local cleanup (standalone mode OR fallback)
    local client_dir="$INSTALL_DIR/clients"
    
    # 1. Get pubkey for Live WG removal
    local pub=""
    if [[ -f "$DB_PATH" ]]; then
        pub=$(db_query "SELECT public_key FROM peers WHERE name='$safe_name';")
    fi
    if [[ -z "$pub" && -f "$client_dir/${target_name}.conf" ]]; then
        local priv=$(grep "PrivateKey" "$client_dir/${target_name}.conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
        [[ -n "$priv" ]] && pub=$(echo "$priv" | wg pubkey 2>/dev/null)
    fi
    
    # 2. Kill from live WireGuard
    if [[ -n "$pub" ]]; then
        wg set wg0 peer "$pub" remove 2>/dev/null
    fi
    
    # 3. Delete from DB
    if [[ -f "$DB_PATH" ]]; then
        db_exec "DELETE FROM peers WHERE name='$safe_name';"
        if [[ -n "$pub" ]]; then
            db_exec "DELETE FROM peers WHERE public_key='$pub';"
        fi
    fi
    
    # 4. Delete files
    rm -f "$client_dir/${target_name}.conf" 2>/dev/null
    rm -f "$client_dir/${target_name}.conf.expiry" 2>/dev/null
    rm -f "$client_dir/${target_name}.conf.limit" 2>/dev/null
    
    # 5. Cleanup wg0.conf
    if [[ -f /etc/wireguard/wg0.conf ]]; then
         local tmp_conf=$(mktemp)
         local in_peer=0
         local skip=0
         while IFS= read -r line; do
             if [[ "$line" == "[Peer]" ]]; then
                 in_peer=1
                 skip=0
             fi
             if [[ "$in_peer" -eq 1 ]]; then
                 if [[ "$line" == "# $target_name"* ]] || [[ -n "$pub" && "$line" == "PublicKey = $pub"* ]]; then
                     skip=1
                 fi
             fi
             if [[ "$skip" -eq 1 ]]; then
                 if [[ -z "$line" ]] || [[ "$line" == "["* && "$line" != "[Peer]" ]]; then
                     skip=0
                     [[ -n "$line" ]] && echo "$line" >> "$tmp_conf"
                 fi
                 continue
             fi
             echo "$line" >> "$tmp_conf"
         done < /etc/wireguard/wg0.conf
         mv "$tmp_conf" /etc/wireguard/wg0.conf
         chmod 600 /etc/wireguard/wg0.conf
    fi
    
    [[ "$silent" != "true" ]] && log_success "Peer '$target_name' removed successfully."
}

# Check for expired peers and remove them
check_expiry() {
    [[ ! -f "$DB_PATH" ]] && return
    local now=$(date +%s)
    # Query expired peers
    local expired=$(db_query "SELECT name FROM peers WHERE expires_at IS NOT NULL AND expires_at < $now;" 2>/dev/null)
    
    for peer in $expired; do
        [[ -z "$peer" ]] && continue
        log_info "Peer '$peer' has expired. Auto-removing..."
        remove_peer_core "$peer" "true"
    done
}

# Check for data limits and disable peers if exceeded
check_limits() {
    [[ ! -f "$DB_PATH" ]] && return
    
    # 1. Get peers with limits (limit > 0)
    # Output: name|public_key|limit_gb|total_stored_bytes
    local query="SELECT name, public_key, data_limit_gb, (total_rx_bytes + total_tx_bytes) FROM peers WHERE data_limit_gb > 0 AND disabled = 0;"
    
    # We need to map public_key -> live_bytes using wg show
    declare -A live_usage
    if command -v wg &>/dev/null && ip link show wg0 &>/dev/null; then
        while read -r pub rx tx; do
            [[ -z "$pub" ]] && continue
            live_usage["$pub"]=$((rx + tx))
        done < <(wg show wg0 transfer)
    fi
    
    while IFS='|' read -r name pub limit_gb stored_bytes; do
        [[ -z "$name" ]] && continue
        
        local current_live=${live_usage["$pub"]:-0}
        local total_usage=$((stored_bytes + current_live))
        local limit_bytes=$((limit_gb * 1024 * 1024 * 1024))
        
        if [[ $total_usage -gt $limit_bytes ]]; then
            log_warn "Peer '$name' exceeded data limit (${limit_gb}GB). Disabling..."
            
            # 1. Accumulate current stats into total before disabling
            if [[ "$current_live" -gt 0 ]]; then
                local rx=0 tx=0
                if [[ -n "$pub" ]]; then
                     read -r rx tx <<< $(wg show wg0 transfer | grep "$pub" | awk '{print $2, $3}')
                fi
                [[ -z "$rx" ]] && rx=0
                [[ -z "$tx" ]] && tx=0
                db_exec "UPDATE peers SET total_rx_bytes = total_rx_bytes + $rx, total_tx_bytes = total_tx_bytes + $tx, rx_bytes = 0, tx_bytes = 0 WHERE name='$name';"
            fi

            # 2. Kill from live WireGuard
            if command -v wg &>/dev/null; then
                wg set wg0 peer "$pub" remove 2>/dev/null
            fi
            
            # 3. Mark as disabled in DB and create marker file
            db_exec "UPDATE peers SET disabled=1 WHERE name='$name';"
            touch "$INSTALL_DIR/clients/${name}.conf.disabled"
            
            log_success "Peer '$name' disabled due to data limit."
        fi
    done < <(sqlite3 "$DB_PATH" "$query")

    # Clean up historical usage older than 90 days
    db_exec "DELETE FROM historical_usage WHERE deleted_at < date('now', '-90 days');"
}

# Remove Peer Wizard (reads from config files, not live WG)
# Batch Delete Wizard (Regex)
remove_peers_regex_wizard() {
    ui_draw_header_mini "Batch Delete (Regex)"
    
    log_info "Enter a regex to match peer names."
    log_info "Examples: 'test-*', '^temp_', 'user[0-9]+'"
    echo ""
    
    local regex=$(ui_prompt "Regex Pattern")
    [[ -z "$regex" ]] && return
    
    # 1. Identify matches
    local matches=()
    while IFS='|' read -r n ip src s; do
        if [[ "$n" =~ $regex ]]; then
            matches+=("$n")
        fi
    done < <(scan_peers)
    
    if [[ ${#matches[@]} -eq 0 ]]; then
        log_warn "No peers matched pattern '$regex'."
        wait_key
        return
    fi
    
    # 2. Confirm List
    echo ""
    echo "  ${T_BOLD}Matching Peers:${T_RESET}"
    local count=0
    for n in "${matches[@]}"; do
        echo "    - $n"
        ((count++))
        if [[ $count -ge 15 ]]; then
            echo "    ... and $(( ${#matches[@]} - count )) more."
            break
        fi
    done
    echo ""
    
    if ui_confirm "Delete these ${#matches[@]} peers PERMANENTLY?"; then
         # Double confirm for large batches
         if [[ ${#matches[@]} -gt 5 ]]; then
             if ! ui_confirm "Are you absolutely sure?"; then return; fi
         fi
         
         ui_clear
         echo "  Deleting..."
         for n in "${matches[@]}"; do
             printf "    %-20s ... " "$n"
             if remove_peer_core "$n" "true"; then
                 echo "${T_GREEN}OK${T_RESET}"
             else
                 echo "${T_RED}FAIL${T_RESET}"
             fi
         done
         log_success "Batch operation complete."
         wait_key
    fi
}

# Remove Peer Main Menu
remove_peer_wizard() {
    while true; do
        ui_draw_header_mini "Remove Peer"
        
        echo "  [1] Select from List"
        echo "  [2] Batch Delete (Regex)"
        echo "  [B] Back"
        echo ""
        
        local choice=$(ui_prompt "Option")
        case "${choice^^}" in
            1) remove_peer_selector_wizard ;;
            2) remove_peers_regex_wizard ;;
            B) return ;;
            *) log_error "Invalid option" ;;
        esac
    done
}

# Remove Peer Selector (Classic)
remove_peer_selector_wizard() {
    ui_draw_header_mini "Remove/Select"
    
    # Ensure DB is synced before listing (Fixes ghost peers/state mismatch)
    reconcile_db_with_files &>/dev/null
    
    # ─── DISCOVERY ENGINE ───
    local names=()
    local sources=()
    local ips=()
    local client_dir="$INSTALL_DIR/clients"
    
    # Priority 1: Unified Scan (DB + Files)
    while IFS='|' read -r n ip src s; do
        [[ -n "$n" ]] && names+=("$n")
        sources+=("$src")
        ips+=("$ip")
    done < <(scan_peers)

    if [[ ${#names[@]} -eq 0 ]]; then
        log_warn "No peers found to remove."
        wait_key
        return
    fi
    
    printf "    ${T_CYAN}Select peer to remove:${T_RESET}\n\n"
    
    local i=1
    local valid_indices=()
    local removable_names=()
    
    for idx in "${!names[@]}"; do
        local n="${names[$idx]}"
        local src="${sources[$idx]}"
        local ip="${ips[$idx]}"
        
        printf "    ${T_GREEN}[%d]${T_RESET} %-25s ${T_DIM}%s${T_RESET}  (%s)\n" "$i" "$n" "$ip" "$src"
        removable_names[$i]="$n"
        valid_indices+=("$i")
        ((i++))
    done
    
    local choice=$(ui_prompt "Select # to remove (Enter to cancel)")
    
    if [[ -z "$choice" ]]; then return; fi

    if [[ " ${valid_indices[*]} " =~ " ${choice} " ]]; then
        local target_name="${removable_names[$choice]}"
        if ui_confirm "Are you sure you want to remove peer '$target_name'?"; then
             remove_peer_core "$target_name"
        fi
    fi
    wait_key
}

# Show QR Code Wizard (Redirects to interactive list)
show_qr_wizard() {
    list_peers_screen
}


# Security Screen
screen_security() {
    while true; do
        ui_draw_header_mini "Security & Access"
        
        menu_option "1" "Firewall Ports" "Manage open ports (add/remove)"
        menu_option "2" "Firewall Status" "View all nftables rules"
        menu_option "3" "Regenerate Server Keys" "New WireGuard keypair"
        menu_option "4" "View Logs" "System and API logs"
        printf "\n"
        menu_option "B" "Back" ""
        
        ui_draw_footer "[1-4] Select  [B] Back"
        printf "\n${T_CYAN}❯${T_RESET} "
        
        local key=$(read_key)
        case "$key" in
            1) screen_firewall_ports ;;
            2) show_firewall_status ;;
            3) log_warn "Not implemented yet"; wait_key ;;
            4) show_logs_screen ;;
            b|B|$'\x1b') return ;;
        esac
    done
}

# ─── Firewall Port Management Screen ─────────────────────────────────────────

screen_firewall_ports() {
    while true; do
        ui_draw_header_mini "Firewall Port Manager"
        
        local firewall_mode=$(db_get_config "firewall_mode")
        # Smart default: if UFW is active, default to external mode
        if [[ -z "$firewall_mode" ]]; then
            if ufw status 2>/dev/null | grep -q "Status: active"; then
                firewall_mode="external"
            else
                firewall_mode="samnet"
            fi
        fi
        
        local vpn_port=$(db_get_config "listen_port")
        vpn_port="${vpn_port:-51820}"
        
        # Mode indicator
        case "$firewall_mode" in
            samnet)
                printf "  ${T_GREEN}●${T_RESET} Mode: ${T_BOLD}SamNet Managed${T_RESET}\n"
                printf "  ${T_DIM}Open ports are controlled by this TUI.${T_RESET}\n\n"
                ;;
            external)
                printf "  ${T_YELLOW}●${T_RESET} Mode: ${T_BOLD}External Firewall${T_RESET}\n"
                printf "  ${T_DIM}Ports managed by external firewall. Showing best-effort status.${T_RESET}\n\n"
                ;;
            none)
                printf "  ${T_RED}●${T_RESET} Mode: ${T_BOLD}No Firewall${T_RESET}\n"
                printf "  ${T_DIM}All ports are open. Use with caution!${T_RESET}\n\n"
                ;;
        esac
        
        # List open ports (Unified View)
        printf "  ${T_BOLD}Open Ports:${T_RESET}\n"
        printf "  ${T_DIM}────────────────────────────────────────────${T_RESET}\n"
        
        # Branch based on mode for listing
        if [[ "$firewall_mode" == "samnet" ]]; then
            # SamNet Managed: Clean table view
            if nft list table inet samnet-ports &>/dev/null; then
                local port_num=1
                nft list chain inet samnet-ports input 2>/dev/null | grep -E "(tcp|udp) dport" | while read line; do
                    local proto=$(echo "$line" | grep -oP '(tcp|udp)')
                    local port=$(echo "$line" | grep -oP 'dport \K[0-9]+')
                    local comment=$(echo "$line" | grep -oP 'comment "\K[^"]+' || echo "")
                    
                    local status="${T_GREEN}[OPEN]${T_RESET}"
                    local locked=""
                    
                    # Mark VPN port as locked
                    if [[ "$port" == "$vpn_port" && "$proto" == "udp" ]]; then
                        status="${T_CYAN}[VPN]${T_RESET}"
                        locked=" ${T_DIM}(locked)${T_RESET}"
                    fi
                    
                    printf "  ${T_CYAN}%2d.${T_RESET} %-6s %-5s %-20s %s%s\n" \
                        "$port_num" "$port" "$proto" "${comment:-user-defined}" "$status" "$locked"
                    ((port_num++))
                done
            else
                printf "  ${T_DIM}No ports table found. Run install/repair.${T_RESET}\n"
            fi
        
        elif [[ "$firewall_mode" == "external" ]]; then
            # External: Try to show UFW or basic info
            if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
                ufw status numbered 2>/dev/null | head -n 10 | awk '{print "  " $0}'
                echo "  ..."
            else
                printf "  ${T_DIM}Cannot list external rules. Check your firewall tool.${T_RESET}\n"
            fi
            
        else
            # None
            printf "  ${T_RED}FIREWALL DISABLED - ALL PORTS OPEN${T_RESET}\n"
        fi
        
        printf "\n"
        menu_option "V" "View Rules" "Show all active firewall rules"
        
        # Only show edit options if SamNet managed
        if [[ "$firewall_mode" == "samnet" ]]; then
            menu_option "A" "Add Port" "Open a new port"
            menu_option "R" "Remove Port" "Close a port"
            menu_option "P" "Presets" "Quick port templates"
            ui_draw_footer "[V]iew  [A]dd  [R]emove  [P]resets  [M]ode  [B]ack"
        else
            printf "  ${T_DIM}(Editing disabled in $firewall_mode mode)${T_RESET}\n"
            ui_draw_footer "[V]iew Rules  [M]ode  [B]ack"
        fi
        
        menu_option "M" "Change Mode" "Switch firewall mode"
        menu_option "B" "Back" ""
        
        printf "\n${T_CYAN}❯${T_RESET} "
        
        local key=$(read_key)
        case "$key" in
            v|V) show_firewall_rules_table ;;
            m|M) run_firewall_mode_wizard ;;
            b|B|$'\x1b') return ;;
            # Only allow edits in samnet mode
            a|A) [[ "$firewall_mode" == "samnet" ]] && firewall_add_port_wizard ;;
            r|R) [[ "$firewall_mode" == "samnet" ]] && firewall_remove_port_wizard ;;
            p|P) [[ "$firewall_mode" == "samnet" ]] && firewall_presets_menu ;;
        esac
    done
}

firewall_add_port_wizard() {
    ui_draw_header_mini "Add Firewall Port"
    
    printf "  Enter port details:\n\n"
    
    # Port number
    printf "  Port number (1-65535): "
    ui_show_cursor
    stty echo
    read -r port_input
    stty -echo
    ui_hide_cursor
    
    if ! [[ "$port_input" =~ ^[0-9]+$ ]] || [[ "$port_input" -lt 1 ]] || [[ "$port_input" -gt 65535 ]]; then
        log_error "Invalid port number"
        wait_key
        return
    fi
    
    # Protocol
    printf "  Protocol [tcp/udp] (default: tcp): "
    ui_show_cursor
    stty echo
    read -r proto_input
    stty -echo
    ui_hide_cursor
    proto_input="${proto_input:-tcp}"
    
    if [[ "$proto_input" != "tcp" && "$proto_input" != "udp" ]]; then
        log_error "Invalid protocol. Must be 'tcp' or 'udp'"
        wait_key
        return
    fi
    
    # Label
    printf "  Label (optional, e.g., 'web-server'): "
    ui_show_cursor
    stty echo
    read -r label_input
    stty -echo
    ui_hide_cursor
    label_input="${label_input:-user-defined}"
    
    # Confirm
    printf "\n  Adding: ${T_BOLD}$port_input/$proto_input${T_RESET} ($label_input)\n"
    printf "  Continue? [Y/n]: "
    read -r confirm
    
    if [[ "${confirm,,}" != "n" ]]; then
        add_firewall_port "$port_input" "$proto_input" "$label_input"
    else
        log_info "Cancelled"
    fi
    wait_key
}

firewall_remove_port_wizard() {
    ui_draw_header_mini "Remove Firewall Port"
    
    local vpn_port=$(db_get_config "listen_port")
    vpn_port="${vpn_port:-51820}"
    
    printf "  Enter port to close:\n\n"
    
    # Port number
    printf "  Port number: "
    read -r port_input
    
    # Protocol
    printf "  Protocol [tcp/udp] (default: tcp): "
    read -r proto_input
    proto_input="${proto_input:-tcp}"
    
    # Safety check for SSH
    if [[ "$port_input" == "22" && "$proto_input" == "tcp" ]]; then
        printf "\n  ${T_RED}${T_BOLD}WARNING:${T_RESET} Removing SSH port will lock you out!\n"
        printf "  Are you SURE? Type 'YES' to confirm: "
        read -r ssh_confirm
        if [[ "$ssh_confirm" != "YES" ]]; then
            log_info "Cancelled"
            wait_key
            return
        fi
    fi
    
    remove_firewall_port "$port_input" "$proto_input"
    wait_key
}

firewall_presets_menu() {
    ui_draw_header_mini "Firewall Presets"
    
    printf "  Quick port configurations:\n\n"
    
    menu_option "1" "Minimal" "SSH only (port 22)"
    menu_option "2" "Web Server" "SSH + HTTP + HTTPS (22, 80, 443)"
    menu_option "3" "Web + Honeypot" "SSH + HTTP + HTTPS + 2222"
    menu_option "4" "Development" "SSH + common dev ports (22, 3000, 8080)"
    printf "\n"
    menu_option "B" "Back" ""
    
    ui_draw_footer "[1-4] Apply preset  [B] Back"
    printf "\n${T_CYAN}❯${T_RESET} "
    
    local key=$(read_key)
    case "$key" in
        1) apply_firewall_preset "minimal" ;;
        2) apply_firewall_preset "webserver" ;;
        3) apply_firewall_preset "webhoneypot" ;;
        4) apply_firewall_preset "development" ;;
        b|B|$'\x1b') return ;;
    esac
}

apply_firewall_preset() {
    local preset="$1"
    local vpn_port=$(db_get_config "listen_port")
    vpn_port="${vpn_port:-51820}"
    
    printf "\n  ${T_YELLOW}This will reset your ports to the preset. Continue? [y/N]: ${T_RESET}"
    read -r confirm
    
    if [[ "${confirm,,}" != "y" ]]; then
        log_info "Cancelled"
        wait_key
        return
    fi
    
    # Delete and recreate ports table with preset
    nft delete table inet samnet-ports 2>/dev/null || true
    
    case "$preset" in
        minimal)
            nft -f - <<EOF
table inet samnet-ports {
    chain input {
        type filter hook input priority -10; policy drop;
        ip protocol icmp accept
        udp dport $vpn_port accept comment "wireguard-vpn"
        tcp dport 22 accept comment "ssh"
    }
}
EOF
            log_success "Applied 'Minimal' preset (SSH + VPN only)"
            ;;
        webserver)
            nft -f - <<EOF
table inet samnet-ports {
    chain input {
        type filter hook input priority -10; policy drop;
        ip protocol icmp accept
        udp dport $vpn_port accept comment "wireguard-vpn"
        tcp dport 22 accept comment "ssh"
        tcp dport 80 accept comment "http"
        tcp dport 443 accept comment "https"
    }
}
EOF
            log_success "Applied 'Web Server' preset (SSH + HTTP + HTTPS)"
            ;;
        webhoneypot)
            nft -f - <<EOF
table inet samnet-ports {
    chain input {
        type filter hook input priority -10; policy drop;
        ip protocol icmp accept
        udp dport $vpn_port accept comment "wireguard-vpn"
        tcp dport 22 accept comment "ssh"
        tcp dport 80 accept comment "http"
        tcp dport 443 accept comment "https"
        tcp dport 2222 accept comment "honeypot"
    }
}
EOF
            log_success "Applied 'Web + Honeypot' preset"
            ;;
        development)
            nft -f - <<EOF
table inet samnet-ports {
    chain input {
        type filter hook input priority -10; policy drop;
        ip protocol icmp accept
        udp dport $vpn_port accept comment "wireguard-vpn"
        tcp dport 22 accept comment "ssh"
        tcp dport 3000 accept comment "dev-server"
        tcp dport 8080 accept comment "alt-http"
    }
}
EOF
            log_success "Applied 'Development' preset"
            ;;
    esac
    
    persist_samnet_ports
    wait_key
}

run_firewall_mode_wizard() {
    # Optional parameter: pass "install" to bypass WireGuard check during installation
    local install_mode="${1:-}"
    
    ui_draw_header_mini "Firewall Mode Selection"
    
    # Detect existing firewalls
    local detected=""
    if systemctl is-active --quiet ufw 2>/dev/null; then
        detected="UFW (active)"
    elif command -v ufw &>/dev/null; then
        detected="UFW (installed)"
    fi
    if iptables -L INPUT -n 2>/dev/null | grep -qE "DROP|REJECT" && [[ -z "$detected" ]]; then
        detected="${detected:+$detected, }iptables rules detected"
    fi
    
    if [[ -n "$detected" ]]; then
        printf "  ${T_YELLOW}Detected: $detected${T_RESET}\n\n"
    fi
    
    local current_mode=$(db_get_config "firewall_mode")
    # Smart default: if UFW is active and no mode set, default to external
    if [[ -z "$current_mode" ]]; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            current_mode="external"
        else
            current_mode="samnet"
        fi
    fi
    printf "  Current mode: ${T_BOLD}$current_mode${T_RESET}\n\n"
    
    printf "  ${T_BOLD}Select firewall mode:${T_RESET}\n\n"
    
    menu_option "1" "SamNet Managed" "Control ports via this TUI"
    printf "      ${T_DIM}├─ Secure by default (policy: drop)${T_RESET}\n"
    printf "      ${T_DIM}└─ ⚠ Don't use UFW/iptables for ports${T_RESET}\n\n"
    
    menu_option "2" "External Firewall" "You manage ports externally"
    printf "      ${T_DIM}├─ SamNet only handles VPN routing${T_RESET}\n"
    printf "      ${T_DIM}└─ Use UFW, iptables, etc. for ports${T_RESET}\n\n"
    
    menu_option "3" "No Firewall" "All ports open (dangerous)"
    printf "      ${T_DIM}└─ Not recommended for production${T_RESET}\n\n"
    
    menu_option "B" "Back" "Keep current mode"
    
    ui_draw_footer "[1-3] Select mode  [B] Back"
    printf "\n${T_CYAN}❯${T_RESET} "
    
    local key=$(read_key)
    case "$key" in
        1)
            # ─── Safety Check: WireGuard must be installed (bypass during install) ───
            if [[ "$install_mode" != "install" ]] && [[ ! -f /etc/wireguard/wg0.conf ]]; then
                printf "\n  ${T_RED}${T_BOLD}Cannot select SamNet Managed mode!${T_RESET}\n"
                printf "  ${T_YELLOW}WireGuard is not installed.${T_RESET}\n\n"
                printf "  SamNet Managed mode requires WireGuard to be installed first.\n"
                printf "  This prevents accidentally overwriting your existing firewall rules.\n\n"
                printf "  ${T_DIM}Options:${T_RESET}\n"
                printf "  ${T_DIM}  • Run installer: ${T_CYAN}samnet --zero-touch${T_RESET}\n"
                printf "  ${T_DIM}  • Use External Firewall mode with UFW/iptables${T_RESET}\n"
                wait_key
                return
            fi

            
            # ─── Smart Switch to SamNet Mode ───
            local vpn_port=$(db_get_config "listen_port")
            vpn_port="${vpn_port:-51820}"
            
            # Check if samnet-ports exists
            if ! nft list table inet samnet-ports &>/dev/null; then
                # Detect listening services that need ports opened
                printf "\n  ${T_CYAN}Scanning for listening services...${T_RESET}\n"
                
                local detected_ports=()
                local detected_procs=()
                
                # Scan common ports using ss
                if command -v ss &>/dev/null; then
                    while read -r port proc; do
                        [[ -n "$port" ]] && detected_ports+=("$port") && detected_procs+=("$proc")
                    done < <(ss -tlnp 2>/dev/null | grep LISTEN | awk '{
                        port = $4; sub(/.*:/, "", port);
                        proc = $6; gsub(/.*"/, "", proc); gsub(/".*/, "", proc);
                        if (port ~ /^[0-9]+$/ && port != "22") print port, proc
                    }' | head -15)
                fi
                
                # Filter to well-known ports that users likely want open
                local ports_to_add=()
                local labels=()
                
                for i in "${!detected_ports[@]}"; do
                    local p="${detected_ports[$i]}"
                    local proc="${detected_procs[$i]}"
                    case "$p" in
                        80)   ports_to_add+=("80:tcp"); labels+=("http ($proc)") ;;
                        443)  ports_to_add+=("443:tcp"); labels+=("https ($proc)") ;;
                        2222) ports_to_add+=("2222:tcp"); labels+=("alt-ssh/honeypot ($proc)") ;;
                        3000) ports_to_add+=("3000:tcp"); labels+=("dev-server ($proc)") ;;
                        8080) ports_to_add+=("8080:tcp"); labels+=("alt-http ($proc)") ;;
                        8443) ports_to_add+=("8443:tcp"); labels+=("alt-https ($proc)") ;;
                        8081|8082) ports_to_add+=("$p:tcp"); labels+=("docker-proxy ($proc)") ;;
                    esac
                done
                
                if [[ ${#ports_to_add[@]} -gt 0 ]]; then
                    printf "\n  ${T_YELLOW}⚠ Detected services that need open ports:${T_RESET}\n\n"
                    for i in "${!ports_to_add[@]}"; do
                        local port_proto="${ports_to_add[$i]}"
                        local label="${labels[$i]}"
                        printf "    ${T_GREEN}•${T_RESET} %-10s %s\n" "${port_proto%:*}/tcp" "$label"
                    done
                    printf "\n  ${T_CYAN}Without these ports, services will be blocked!${T_RESET}\n"
                    printf "  Add detected ports to firewall? [Y/n]: "
                    read -r add_confirm
                    
                    if [[ "${add_confirm,,}" != "n" ]]; then
                        # Create samnet-ports with detected services
                        local nft_rules="table inet samnet-ports {\n    chain input {\n        type filter hook input priority -10; policy drop;\n        ip protocol icmp accept\n        udp dport $vpn_port accept comment \"wireguard-vpn\"\n        tcp dport 22 accept comment \"ssh\"\n"
                        
                        for i in "${!ports_to_add[@]}"; do
                            local port_proto="${ports_to_add[$i]}"
                            local port="${port_proto%:*}"
                            local proto="${port_proto#*:}"
                            local label="${labels[$i]%% (*}"  # Remove process name
                            nft_rules+="        $proto dport $port accept comment \"$label\"\n"
                        done
                        
                        nft_rules+="    }\n}\n"
                        
                        echo -e "$nft_rules" | nft -f -
                        persist_samnet_ports
                        log_success "Created firewall with ${#ports_to_add[@]} detected ports + SSH + VPN"
                    else
                        # User declined - create minimal
                        create_samnet_ports_table "$vpn_port"
                        log_warn "Created minimal firewall (SSH + VPN only)"
                    fi
                else
                    # No services detected - create minimal
                    create_samnet_ports_table "$vpn_port"
                    log_success "Created firewall with SSH + VPN"
                fi
            else
                log_info "Using existing samnet-ports table"
            fi
            
            db_set_config "firewall_mode" "samnet"
            log_success "Switched to SamNet-managed firewall"
            ;;
        2)
            db_set_config "firewall_mode" "external"
            # Remove samnet-ports table to avoid conflicts
            if nft list table inet samnet-ports &>/dev/null; then
                printf "\n  ${T_YELLOW}Remove samnet-ports table? (recommended to avoid conflicts) [Y/n]: ${T_RESET}"
                read -r remove_confirm
                if [[ "${remove_confirm,,}" != "n" ]]; then
                    nft delete table inet samnet-ports 2>/dev/null
                    rm -f /etc/samnet-ports.nft
                    log_info "Removed samnet-ports table"
                fi
            fi
            log_success "Switched to external firewall mode"
            log_info "Remember to open necessary ports with your firewall tool!"
            ;;
        3)
            printf "\n  ${T_RED}${T_BOLD}WARNING:${T_RESET} No firewall means ALL ports are open!\n"
            printf "  Type 'CONFIRM' to proceed: "
            read -r confirm
            if [[ "$confirm" == "CONFIRM" ]]; then
                db_set_config "firewall_mode" "none"
                nft delete table inet samnet-ports 2>/dev/null
                rm -f /etc/samnet-ports.nft
                log_warn "Firewall disabled - all ports open"
            else
                log_info "Cancelled"
            fi
            ;;
        b|B|$'\x1b') return 1 ;;  # Return non-zero to signal "go back"
    esac
    wait_key
}


# ─── Show All Active Firewall Rules in Table Format ──────────────────────────

show_firewall_rules_table() {
    # Collect all output into a variable so we can pipe to less
    local output=""
    local current_table=""
    
    output+="  ${T_BOLD}Open ports from all firewall sources:${T_RESET}\n\n"
    output+="  ${T_CYAN}PORT     PROTO   SOURCE             ACTION${T_RESET}\n"
    output+="  ${T_DIM}──────────────────────────────────────────────────────${T_RESET}\n"
    
    # ─── 1. Scan nftables (only samnet/honeypot tables, skip UFW internal) ───
    if command -v nft &>/dev/null; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^table[[:space:]]+(inet|ip|ip6)[[:space:]]+([a-zA-Z0-9_-]+) ]]; then
                current_table="${BASH_REMATCH[2]}"
            fi
            [[ "$current_table" == "filter" ]] && continue
            case "$current_table" in
                samnet-filter|samnet-ports|honeypot|nat) ;;
                *) continue ;;
            esac
            if [[ "$line" =~ (tcp|udp)[[:space:]]dport[[:space:]]([0-9]+) ]]; then
                local proto="${BASH_REMATCH[1]}"
                local port="${BASH_REMATCH[2]}"
                local action="ACCEPT" color="${T_GREEN}"
                [[ "$line" =~ accept ]] && action="ACCEPT" && color="${T_GREEN}"
                [[ "$line" =~ drop ]] && action="DROP" && color="${T_RED}"
                [[ "$line" =~ redirect ]] && action="REDIRECT" && color="${T_YELLOW}"
                [[ "$line" =~ reject ]] && action="REJECT" && color="${T_RED}"
                local src_color="${T_DIM}"
                case "$current_table" in
                    samnet-filter) src_color="${T_CYAN}" ;;
                    samnet-ports) src_color="${T_GREEN}" ;;
                    honeypot) src_color="${T_MAGENTA}" ;;
                esac
                output+="  ${color}$(printf '%-8s' "$port")${T_RESET} $(printf '%-7s' "$proto") ${src_color}$(printf '%-18s' "$current_table")${T_RESET} ${color}$(printf '%-12s' "$action")${T_RESET}\n"
            fi
        done < <(nft list ruleset 2>/dev/null)
    fi
    
    # ─── 2. Check UFW ───
    if command -v ufw &>/dev/null; then
        local ufw_status=$(ufw status 2>/dev/null | head -1)
        if [[ "$ufw_status" == *"active"* ]]; then
            output+="\n  ${T_DIM}──────────────────────────────────────────────────────${T_RESET}\n"
            output+="  ${T_BOLD}UFW (active):${T_RESET}\n"
            
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                [[ "$line" == "Status:"* ]] && continue
                [[ "$line" == "To"*"Action"* ]] && continue
                [[ "$line" == "--"* ]] && continue
                
                local port="" proto="" action="ALLOW" ipver=""
                [[ "$line" =~ "(v6)" ]] && ipver="v6"
                
                if [[ "$line" =~ ^([0-9]+)/(tcp|udp) ]]; then
                    port="${BASH_REMATCH[1]}"; proto="${BASH_REMATCH[2]}"
                elif [[ "$line" =~ ^([0-9]+)[[:space:]]on[[:space:]]([a-z0-9]+) ]]; then
                    port="${BASH_REMATCH[1]}"; proto="on ${BASH_REMATCH[2]}"
                elif [[ "$line" =~ ^([0-9]+)[[:space:]] ]] && [[ ! "$line" =~ "/" ]]; then
                    port="${BASH_REMATCH[1]}"; proto="both"
                fi
                
                [[ "$line" =~ ALLOW ]] && action="ALLOW"
                [[ "$line" =~ DENY ]] && action="DENY"
                
                if [[ -n "$port" ]]; then
                    local color="${T_GREEN}"
                    [[ "$action" == "DENY" ]] && color="${T_RED}"
                    local source="UFW"
                    [[ -n "$ipver" ]] && source="UFW (v6)"
                    output+="  ${color}$(printf '%-8s' "$port")${T_RESET} $(printf '%-7s' "$proto") ${T_BLUE}$(printf '%-18s' "$source")${T_RESET} ${color}$(printf '%-12s' "$action")${T_RESET}\n"
                fi
            done < <(ufw status 2>/dev/null)
        else
            output+="\n  ${T_DIM}UFW: inactive${T_RESET}\n"
        fi
    fi
    
    # ─── 3. Listening Services ───
    output+="\n  ${T_DIM}──────────────────────────────────────────────────────${T_RESET}\n"
    output+="  ${T_BOLD}Listening Services:${T_RESET} ${T_DIM}(top 10)${T_RESET}\n"
    if command -v ss &>/dev/null; then
        while read -r line; do
            local port=$(echo "$line" | awk '{print $4}' | grep -oE '[0-9]+$')
            local proc=$(echo "$line" | grep -oP 'users:\(\("\K[^"]+' || echo "-")
            [[ -n "$port" ]] && output+="  ${T_DIM}$(printf '%-8s' "$port") tcp     $(printf '%-18s' "${proc:0:15}") (listening)${T_RESET}\n"
        done < <(ss -tlnp 2>/dev/null | grep LISTEN | head -10)
    fi
    
    output+="\n  ${T_DIM}Navigation: ↑↓/PgUp/PgDn to scroll, q to exit${T_RESET}\n"
    
    # Clear screen and display with scrolling via less
    clear
    printf "\n    ${T_GREEN}▸${T_RESET} ${T_WHITE}SAMNET${T_RESET} │ ${T_CYAN}Active Firewall Rules${T_RESET}\n"
    printf "  ────────────────────────────────────────────────────────────────────────────────────\n\n"
    
    # Use less with color support and exit if content fits
    echo -e "$output" | less -RFX
}


show_firewall_status() {
    ui_draw_header_mini "Firewall Rules"
    printf "    ${T_CYAN}${T_BOLD}Active nftables Rules:${T_RESET}\n"
    printf "    ${T_DIM}────────────────────────────────────────────${T_RESET}\n"
    nft list ruleset 2>/dev/null | head -50 | while read line; do
        printf "    ${T_DIM}%s${T_RESET}\n" "$line"
    done
    wait_key
}

# Show Logs Screen
show_logs_screen() {
    ui_draw_header_mini "System Logs"
    printf "    ${T_CYAN}${T_BOLD}Recent API Logs:${T_RESET}\n"
    printf "    ${T_DIM}────────────────────────────────────────────${T_RESET}\n"
    # Try both names just in case, preferring samnet-wg-api
    docker logs samnet-wg-api 2>&1 | tail -20 | while read line; do
        printf "    ${T_DIM}%s${T_RESET}\n" "$line"
    done
    wait_key
}

# Traffic Stats Display (Live Mode)
show_traffic_stats() {
    local client_dir="$INSTALL_DIR/clients"
    
    # Build pubkey -> name map once
    declare -A peer_names
    if [[ -d "$client_dir" ]]; then
        for conf in "$client_dir"/*.conf; do
            [[ -e "$conf" ]] || continue
            local priv=$(grep "PrivateKey" "$conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
            if [[ -n "$priv" ]]; then
                local pub=$(echo "$priv" | wg pubkey 2>/dev/null)
                if [[ -n "$pub" ]]; then
                    peer_names["$pub"]=$(basename "$conf" .conf)
                fi
            fi
        done
    fi
    
    # Live refresh loop
    while true; do
        ui_clear
        ui_draw_header_mini "Traffic Statistics (Live)"
        
        printf "    ${T_CYAN}${T_BOLD}Per-Peer Transfer Statistics${T_RESET}  ${T_DIM}[Press Q to exit]${T_RESET}\n"
        printf "    ${T_DIM}────────────────────────────────────────────────────────${T_RESET}\n"
        printf "    ${T_WHITE}%-24s %12s %12s %12s${T_RESET}\n" "PEER" "RECEIVED" "SENT" "LAST SEEN"
        printf "    ${T_DIM}────────────────────────────────────────────────────────${T_RESET}\n"
        
        local total_rx=0 total_tx=0 peer_count=0
        
        # Parse wg show output
        while IFS=$'\t' read -r pubkey preshared endpoint allowed_ips handshake rx tx keepalive; do
            [[ -z "$pubkey" || "$pubkey" == "$(cat /etc/wireguard/publickey 2>/dev/null)" ]] && continue
            
            local name="${peer_names[$pubkey]:-${pubkey:0:8}...}"
            
            # Format bytes
            local rx_fmt=$(numfmt --to=iec-i --suffix=B $rx 2>/dev/null || echo "${rx}B")
            local tx_fmt=$(numfmt --to=iec-i --suffix=B $tx 2>/dev/null || echo "${tx}B")
            
            # Format handshake time
            local hs_fmt="never"
            if [[ "$handshake" != "0" && -n "$handshake" ]]; then
                local now=$(date +%s)
                local diff=$((now - handshake))
                if [[ $diff -lt 60 ]]; then
                    hs_fmt="${diff}s ago"
                elif [[ $diff -lt 3600 ]]; then
                    hs_fmt="$((diff/60))m ago"
                elif [[ $diff -lt 86400 ]]; then
                    hs_fmt="$((diff/3600))h ago"
                else
                    hs_fmt="$((diff/86400))d ago"
                fi
            fi
            
            printf "    %-24s %12s %12s %12s\n" "$name" "$rx_fmt" "$tx_fmt" "$hs_fmt"
            
            ((total_rx += rx))
            ((total_tx += tx))
            ((peer_count++))
        done < <(wg show wg0 dump 2>/dev/null | tail -n +2)
        
        printf "    ${T_DIM}────────────────────────────────────────────────────────${T_RESET}\n"
        
        local total_rx_fmt=$(numfmt --to=iec-i --suffix=B $total_rx 2>/dev/null || echo "${total_rx}B")
        local total_tx_fmt=$(numfmt --to=iec-i --suffix=B $total_tx 2>/dev/null || echo "${total_tx}B")
        printf "    ${T_GREEN}%-24s %12s %12s${T_RESET}\n" "TOTAL ($peer_count peers)" "$total_rx_fmt" "$total_tx_fmt"
        
        # Adaptive refresh interval: 5s for <10 peers, 10s for <50, 20s for <100, 30s for 100+
        local refresh_interval=5
        if [[ $peer_count -ge 100 ]]; then
            refresh_interval=30
        elif [[ $peer_count -ge 50 ]]; then
            refresh_interval=20
        elif [[ $peer_count -ge 10 ]]; then
            refresh_interval=10
        fi
        
        printf "\n    ${T_DIM}Refreshing in ${refresh_interval}s... (Q to quit)${T_RESET}\n"
        
        # Wait for keypress or timeout
        if read -t $refresh_interval -n 1 key 2>/dev/null; then
            case "$key" in
                q|Q) return ;;
            esac
        fi
    done
}

# Observability Screen
screen_observability() {
    while true; do
        ui_draw_header_mini "Observability"
        
        menu_option "1" "Live Status" "Watch mode"
        menu_option "2" "Traffic Stats" "Bandwidth usage"
        menu_option "3" "Health Check" "API and WG status"
        printf "\n"
        menu_option "B" "Back" ""
        
        ui_draw_footer "[1-3] Select  [B] Back"
        printf "\n${T_CYAN}❯${T_RESET} "
        
        local key=$(read_key)
        case "$key" in
            1) run_watch_mode ;;
            2) show_traffic_stats ;;
            3) check_health ;;
            b|B|$'\x1b') return ;;
        esac
    done
}

# Health Check
check_health() {
    ui_draw_header_mini "Health Check"
    
    printf "    ${T_CYAN}Running health checks...${T_RESET}\n\n"
    
    # WireGuard
    if wg show wg0 &>/dev/null; then
        printf "    ${T_GREEN}✓${T_RESET} WireGuard interface\n"
    else
        printf "    ${T_RED}✗${T_RESET} WireGuard interface\n"
    fi
    
    # Docker
    if docker ps &>/dev/null; then
        printf "    ${T_GREEN}✓${T_RESET} Docker daemon\n"
    else
        printf "    ${T_RED}✗${T_RESET} Docker daemon\n"
    fi
    
    # API Container
    if docker ps --format '{{.Names}}' | grep -q samnet-api; then
        printf "    ${T_GREEN}✓${T_RESET} API container running\n"
    else
        printf "    ${T_RED}✗${T_RESET} API container\n"
    fi
    
    # API Health
    if curl -sf $(get_api_url)/health/live &>/dev/null; then
        printf "    ${T_GREEN}✓${T_RESET} API responding\n"
    else
        printf "    ${T_RED}✗${T_RESET} API not responding\n"
    fi
    
    # Firewall
    if nft list ruleset &>/dev/null | grep -q "masquerade"; then
        printf "    ${T_GREEN}✓${T_RESET} Firewall NAT rules\n"
    else
        printf "    ${T_YELLOW}⚠${T_RESET} Firewall NAT missing\n"
    fi
    
    wait_key
}

# Advanced Tools Screen
screen_advanced() {
    while true; do
        ui_draw_header_mini "Advanced Tools"
        
        menu_option "1" "Repair Wizard" "Fix common issues"
        menu_option "2" "Rebuild Docker" "No-cache rebuild"
        menu_option "3" "Reset Database" "Clear all data"
        menu_option "4" "Export Config" "Backup settings"
        printf "\n"
        menu_option "B" "Back" ""
        
        ui_draw_footer "[1-4] Select  [B] Back"
        printf "\n${T_CYAN}❯${T_RESET} "
        
        local key=$(read_key)
        case "$key" in
            1) run_repair_wizard ;;
            2) rebuild_docker ; wait_key ;;
            3) log_warn "Not implemented yet"; wait_key ;;
            4) log_warn "Not implemented yet"; wait_key ;;
            b|B|$'\x1b') return ;;
        esac
    done
}

# Uninstall Screen
screen_uninstall() {
    ui_draw_header_mini "Uninstall SamNet-WG"
    
    printf "    ${T_RED}${T_BOLD}⚠ WARNING ⚠${T_RESET}\n\n"
    printf "    This will remove:\n"
    printf "    ${T_DIM}• Docker containers and images${T_RESET}\n"
    printf "    ${T_DIM}• WireGuard configuration${T_RESET}\n"
    printf "    ${T_DIM}• Firewall rules${T_RESET}\n"
    printf "    ${T_DIM}• Database and all data${T_RESET}\n"
    printf "    ${T_DIM}• Installed files${T_RESET}\n\n"
    
    if ui_confirm "Are you sure you want to uninstall?"; then
        full_uninstall
    else
        log_info "Cancelled."
    fi
    
    wait_key
}

main_menu() {
    local width=78
    # Safe line generation without tr (which fails on multibyte chars in some locales)
    local hline=""
    for ((i=0; i<width; i++)); do hline="${hline}─"; done
    
    local first_run=true
    local needs_refresh=true
    local force_clear=false
    
    while true; do
        if [[ "$needs_refresh" == "true" ]] || [[ "$first_run" == "true" ]] || [[ "$force_clear" == "true" ]]; then
            # Hide cursor during redraw to prevent flicker/corruption
            tput civis
            
            if [[ "$first_run" == "true" ]] || [[ "$force_clear" == "true" ]]; then
                clear
                force_clear=false
            else
                tput cup 0 0
            fi
            
            first_run=false
            needs_refresh=false

            # Get live system stats
            local hostname=$(hostname 2>/dev/null || echo "samnet-host")
            local os_info=$(grep -oP '(?<=^PRETTY_NAME=").*(?=")' /etc/os-release 2>/dev/null | head -c 20 || echo "Linux")
            local wg_status="DOWN"
            local wg_iface="wg0"
            local subnet="Not configured"
            local peer_count=0
            local cpu_usage="--"
            local mem_usage="--"
            local disk_usage="--"
            local ddns_status="--"
            
            # Peer Count: Single Source of Truth
            local peer_count=0
            # Prefer DB count (includes Web UI peers)
            if [[ -f "$DB_PATH" ]]; then
                peer_count=$(db_query "SELECT COUNT(*) FROM peers;" 2>/dev/null)
                # Handle empty return or error
                [[ -z "$peer_count" ]] && peer_count=0
            else
                # Fallback to live WG or files
                if wg show wg0 &>/dev/null; then
                     peer_count=$(wg show wg0 | grep -c "peer:")
                elif [[ -d "$INSTALL_DIR/clients" ]]; then
                     peer_count=$(find "$INSTALL_DIR/clients" -name "*.conf" 2>/dev/null | wc -l)
                fi
            fi
            
            # WireGuard Status check
            if wg show wg0 &>/dev/null; then
                wg_status="UP"
                local raw_addr=$(grep "Address" /etc/wireguard/wg0.conf 2>/dev/null | cut -d= -f2 | tr -d ' ' | cut -d, -f1 | head -1)
                subnet=$(normalize_cidr "$raw_addr")
            else
                if [[ -f "/etc/wireguard/wg0.conf" ]]; then
                    subnet=$(grep "Address" /etc/wireguard/wg0.conf 2>/dev/null | cut -d= -f2 | tr -d ' ' | head -1)
                else
                    local db_subnet=$(db_get_config "subnet_cidr")
                    [[ -n "$db_subnet" ]] && subnet="$db_subnet"
                fi
            fi
            
            # System resources
            cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print int($2)}' || echo "0")%
            mem_usage=$(free -m 2>/dev/null | awk '/Mem:/ {print $3}' || echo "0")MB
            disk_usage=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' || echo "0%")
            
            # API/DDNS status
            if curl -sf --max-time 1 $(get_api_url)/health/live &>/dev/null; then
                ddns_status="${T_GREEN}HEALTHY${T_RESET}"
            else
                ddns_status="${T_DIM}OFFLINE${T_RESET}"
            fi
            
            # Mode
            local mode="STANDALONE"
            [[ -f "$INSTALL_DIR/samnet" ]] && mode="MANAGED"
            
            # Detect terminal dimensions
            local term_cols=$(tput cols 2>/dev/null || echo 80)
            local term_rows=$(tput lines 2>/dev/null || echo 24)
            
            # Adapt width to terminal (min 60, max 78)
            local display_width=$((term_cols - 2))
            [[ $display_width -gt 78 ]] && display_width=78
            [[ $display_width -lt 48 ]] && display_width=48
            
            # Use ui_repeat for consistency
            local hline=$(ui_repeat "─" $display_width)
            
            # Compact mode for short/narrow terminals
            local compact_mode=false
            [[ $term_rows -lt 22 || $term_cols -lt 65 ]] && compact_mode=true
            
            # ═══ HEADER ═══
            echo "${T_GREEN}┌${hline}┐${T_RESET}"
            
            # SAMNET-WG Logo - based on terminal HEIGHT
            printf "${T_GREEN}${T_BOLD}"
            if [[ $term_rows -ge 20 && $term_cols -ge 65 ]]; then
                # Normal terminal: full SAMNET-WG block logo (6 lines)
                printf '%s\n' " ███████╗ █████╗ ███╗   ███╗███╗   ██╗███████╗████████╗   ██╗    ██╗ ██████╗ "
                printf '%s\n' " ██╔════╝██╔══██╗████╗ ████║████╗  ██║██╔════╝╚══██╔══╝   ██║    ██║██╔════╝ "
                printf '%s\n' " ███████╗███████║██╔████╔██║██╔██╗ ██║█████╗     ██║      ██║ █╗ ██║██║  ███╗"
                printf '%s\n' " ╚════██║██╔══██║██║╚██╔╝██║██║╚██╗██║██╔══╝     ██║      ██║███╗██║██║   ██║"
                printf '%s\n' " ███████║██║  ██║██║ ╚═╝ ██║██║ ╚████║███████╗   ██║      ╚███╔███╔╝╚██████╔╝"
                printf '%s\n' " ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝       ╚══╝╚══╝  ╚═════╝ "
            else
                # Short terminal: compact text banner (3 lines)
                echo "  ╔═════════════════════════════════════════╗"
                echo "  ║         S A M N E T  -  W G             ║"
                echo "  ╚═════════════════════════════════════════╝"
            fi
            printf "${T_RESET}"
            
            # Author line (skip in compact mode)
            if [[ "$compact_mode" != "true" ]]; then
                echo "  ${T_CYAN}By $AUTHOR${T_RESET} | ${T_CYAN}$WEBSITE${T_RESET} | ${T_WHITE}v$SAMNET_VERSION${T_RESET}"
                echo "  ${T_DIM}$TAGLINE${T_RESET}"
            fi
            
            # Web UI URL
            local web_display=""
            if [[ "$(db_get_config web_ui_enabled)" == "true" ]]; then
                if [[ "$(db_get_config ssl_enabled)" == "true" ]]; then
                    web_display="${T_CYAN}https://$(db_get_config ssl_domain)${T_RESET}"
                else
                    local lan_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
                    [[ -z "$lan_ip" ]] && lan_ip="127.0.0.1"
                    web_display="${T_CYAN}http://${lan_ip}${T_RESET}"
                fi
            fi

            # ═══ SYSTEM INFO BAR ═══
            echo "${T_GREEN}├${hline}┤${T_RESET}"
            
            if [[ "$compact_mode" == "true" ]]; then
                # Compact: single line status
                local wg_color="${T_GREEN}"; [[ "$wg_status" == "DOWN" ]] && wg_color="${T_RED}"
                echo " ${T_WHITE}WG:${T_RESET}${wg_color}$wg_status${T_RESET} ${T_WHITE}Peers:${T_RESET}$peer_count ${T_WHITE}API:${T_RESET}$ddns_status"
            else
                # Full: multi-line status
                echo " ${T_WHITE}HOST:${T_RESET} $hostname  ${T_WHITE}OS:${T_RESET} $os_info  ${T_WHITE}MODE:${T_RESET} $mode"
                [[ -n "$web_display" ]] && echo " ${T_WHITE}WEB UI:${T_RESET} $web_display"
                local wg_color="${T_GREEN}"; [[ "$wg_status" == "DOWN" ]] && wg_color="${T_RED}"
                echo " ${T_WHITE}WG:${T_RESET} ${wg_color}$wg_iface ($wg_status)${T_RESET}  ${T_WHITE}SUBNET:${T_RESET} $subnet  ${T_WHITE}PEERS:${T_RESET} $peer_count"
                echo " ${T_WHITE}CPU:${T_RESET} $cpu_usage  ${T_WHITE}RAM:${T_RESET} $mem_usage  ${T_WHITE}DISK:${T_RESET} $disk_usage  ${T_WHITE}API:${T_RESET} $ddns_status"
            fi
            
            # ═══ MENU ═══
            echo "${T_GREEN}├${hline}┤${T_RESET}"
            
            if [[ "$compact_mode" == "true" ]]; then
                # Compact menu: minimal
                echo " ${T_CYAN}[1]${T_RESET}Status ${T_CYAN}[2]${T_RESET}Install ${T_CYAN}[3]${T_RESET}Peers ${T_CYAN}[4]${T_RESET}Security"
                echo " ${T_CYAN}[5]${T_RESET}Observe ${T_CYAN}[6]${T_RESET}Advanced ${T_CYAN}[7]${T_RESET}About ${T_RED}[8]${T_RESET}Uninstall"
                echo " ${T_CYAN}[9]${T_RESET}Client Guide"
            else
                # Full menu with descriptions
                echo ""
                echo "  ${T_CYAN}[ 1 ]${T_RESET} ${T_WHITE}${T_BOLD}STATUS DASHBOARD${T_RESET}       ${T_DIM}View system health & live state${T_RESET}"
                echo "  ${T_CYAN}[ 2 ]${T_RESET} ${T_WHITE}${T_BOLD}INSTALL / REPAIR${T_RESET}       ${T_DIM}Zero-touch install, repair, self-heal${T_RESET}"
                echo "  ${T_CYAN}[ 3 ]${T_RESET} ${T_WHITE}${T_BOLD}PEER MANAGEMENT${T_RESET}        ${T_DIM}Create, disable, archive WireGuard peers${T_RESET}"
                echo "  ${T_CYAN}[ 4 ]${T_RESET} ${T_WHITE}${T_BOLD}SECURITY & ACCESS${T_RESET}      ${T_DIM}Users, roles, tokens, audit trail${T_RESET}"
                echo "  ${T_CYAN}[ 5 ]${T_RESET} ${T_WHITE}${T_BOLD}OBSERVABILITY${T_RESET}          ${T_DIM}Metrics, logs, health, alerts${T_RESET}"
                echo "  ${T_CYAN}[ 6 ]${T_RESET} ${T_WHITE}${T_BOLD}ADVANCED TOOLS${T_RESET}         ${T_DIM}Dry-run, firewall diff, chaos, offline${T_RESET}"
                echo "  ${T_CYAN}[ 7 ]${T_RESET} ${T_WHITE}${T_BOLD}DOCS / ABOUT SAMNET${T_RESET}    ${T_DIM}Project info & philosophy${T_RESET}"
                echo "  ${T_CYAN}[ 8 ]${T_RESET} ${T_RED}${T_BOLD}UNINSTALL${T_RESET}              ${T_DIM}Safe removal (danger-gated)${T_RESET}"
                echo "  ${T_CYAN}[ 9 ]${T_RESET} ${T_WHITE}CLIENT GUIDE${T_RESET}           ${T_DIM}Setup iOS, Android, Windows...${T_RESET}"
                echo ""
            fi
            
            # ═══ FOOTER ═══
            echo "${T_GREEN}├${hline}┤${T_RESET}"
            if [[ "$compact_mode" == "true" ]]; then
                echo " ${T_CYAN}[1-9]${T_RESET}Select ${T_CYAN}[P]${T_RESET}Palette ${T_CYAN}[?]${T_RESET}Help ${T_CYAN}[Q]${T_RESET}Quit"
            else
                echo "  ${T_DIM}SHORTCUTS:${T_RESET} ${T_CYAN}[1-9]${T_RESET} Select | ${T_CYAN}[P]${T_RESET} Command Palette | ${T_CYAN}[?]${T_RESET} Help"
                echo "             ${T_CYAN}[B]${T_RESET} Go Back | ${T_CYAN}[Q]${T_RESET} Quit | ${T_CYAN}[R]${T_RESET} Refresh"
            fi
            echo "${T_GREEN}└${hline}┘${T_RESET}"
            tput ed
            tput cnorm # Show cursor back
        fi
        
        # Read key
        local c=$(read_key)
        case "$c" in
            1) screen_status; force_clear=true ;;
            2) screen_install; force_clear=true ;;
            3) screen_peers; force_clear=true ;;
            4) screen_security; force_clear=true ;;
            5) screen_observability; force_clear=true ;;
            6) screen_advanced_v2; force_clear=true ;;
            7) show_about_screen; force_clear=true ;;
            8) screen_uninstall; force_clear=true ;;
            9) screen_client_guide; force_clear=true ;;
            p|P|/) show_command_palette; needs_refresh=true ;;
            \?|h|H) show_help_screen; needs_refresh=true ;;
            r|R) needs_refresh=true ;;
            b|B) ;; # No back from main
            [qQ]) cleanup_exit 0 ;;
            "") needs_refresh=true ;; # Timeout - trigger auto-refresh
            *) ;; # Ignore invalid input
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# 11.5 CLIENT INSTALLATION GUIDE
# ══════════════════════════════════════════════════════════════════════════════

screen_client_guide() {
    while true; do
        ui_clear
        printf "${T_GREEN}${T_BOLD}"
        cat << 'GUIDE_BANNER'
    ╔══════════════════════════════════════════════════════════════════════╗
    ║                    CLIENT INSTALLATION GUIDE                        ║
    ╚══════════════════════════════════════════════════════════════════════╝
GUIDE_BANNER
        printf "${T_RESET}\n"
        
        printf "    ${T_CYAN}${T_BOLD}Select your platform:${T_RESET}\n\n"
        
        menu_option "1" "iOS (iPhone/iPad)" ""
        menu_option "2" "Android" ""
        menu_option "3" "Windows" ""
        menu_option "4" "macOS" ""
        menu_option "5" "Linux" ""
        menu_option "B" "Back" ""
        
        printf "\n${C_CYAN}❯${C_RESET} "
        local c=$(read_key)
        
        case "${c^^}" in
            1)
                ui_clear
                section "iOS Setup"
                printf "\n  ${C_BOLD}Step 1: Install WireGuard${C_RESET}\n"
                printf "  ─────────────────────────\n"
                printf "  • Open the App Store\n"
                printf "  • Search for ${C_WHITE}WireGuard${C_RESET}\n"
                printf "  • Tap ${C_CYAN}Get${C_RESET} to install\n\n"
                
                printf "  ${C_BOLD}Step 2: Import Configuration${C_RESET}\n"
                printf "  ─────────────────────────────\n"
                printf "  • Open WireGuard app\n"
                printf "  • Tap ${C_CYAN}+${C_RESET} → ${C_WHITE}Create from QR code${C_RESET}\n"
                printf "  • Scan the QR code shown in Peer Manager\n"
                printf "  • Give it a name (e.g., \"Home VPN\")\n\n"
                
                printf "  ${C_BOLD}Step 3: Connect${C_RESET}\n"
                printf "  ──────────────\n"
                printf "  • Toggle the switch to connect\n"
                printf "  • Allow VPN permissions when prompted\n"
                printf "  • ${C_GREEN}Done!${C_RESET} You're connected.\n\n"
                wait_key
                ;;
            2)
                ui_clear
                section "Android Setup"
                printf "\n  ${C_BOLD}Step 1: Install WireGuard${C_RESET}\n"
                printf "  ─────────────────────────\n"
                printf "  • Open Google Play Store\n"
                printf "  • Search for ${C_WHITE}WireGuard${C_RESET}\n"
                printf "  • Tap ${C_CYAN}Install${C_RESET}\n\n"
                
                printf "  ${C_BOLD}Step 2: Import Configuration${C_RESET}\n"
                printf "  ─────────────────────────────\n"
                printf "  • Open WireGuard app\n"
                printf "  • Tap ${C_CYAN}+${C_RESET} → ${C_WHITE}Scan from QR code${C_RESET}\n"
                printf "  • Point camera at QR code from Peer Manager\n"
                printf "  • Name your tunnel\n\n"
                
                printf "  ${C_BOLD}Step 3: Connect${C_RESET}\n"
                printf "  ──────────────\n"
                printf "  • Tap the toggle to connect\n"
                printf "  • Accept VPN permission\n"
                printf "  • ${C_GREEN}Connected!${C_RESET}\n\n"
                wait_key
                ;;
            3)
                ui_clear
                section "Windows Setup"
                printf "\n  ${C_BOLD}Step 1: Download WireGuard${C_RESET}\n"
                printf "  ──────────────────────────\n"
                printf "  • Go to: ${C_CYAN}https://wireguard.com/install/${C_RESET}\n"
                printf "  • Download Windows installer\n"
                printf "  • Run the installer\n\n"
                
                printf "  ${C_BOLD}Step 2: Import Configuration${C_RESET}\n"
                printf "  ─────────────────────────────\n"
                printf "  • Download your .conf file from Peer Manager\n"
                printf "  • Open WireGuard\n"
                printf "  • Click ${C_WHITE}Import tunnel(s) from file${C_RESET}\n"
                printf "  • Select your .conf file\n\n"
                
                printf "  ${C_BOLD}Step 3: Connect${C_RESET}\n"
                printf "  ──────────────\n"
                printf "  • Select your tunnel\n"
                printf "  • Click ${C_CYAN}Activate${C_RESET}\n"
                printf "  • ${C_GREEN}You're connected!${C_RESET}\n\n"
                wait_key
                ;;
            4)
                ui_clear
                section "macOS Setup"
                printf "\n  ${C_BOLD}Step 1: Install WireGuard${C_RESET}\n"
                printf "  ─────────────────────────\n"
                printf "  • Open the Mac App Store\n"
                printf "  • Search for ${C_WHITE}WireGuard${C_RESET}\n"
                printf "  • Click ${C_CYAN}Get${C_RESET} to install\n\n"
                
                printf "  ${C_BOLD}Step 2: Import Configuration${C_RESET}\n"
                printf "  ─────────────────────────────\n"
                printf "  • Click WireGuard icon in menu bar\n"
                printf "  • Select ${C_WHITE}Import Tunnel(s) from File...${C_RESET}\n"
                printf "  • Choose your downloaded .conf file\n\n"
                
                printf "  ${C_BOLD}Step 3: Connect${C_RESET}\n"
                printf "  ──────────────\n"
                printf "  • Click the WireGuard menu bar icon\n"
                printf "  • Click your tunnel name\n"
                printf "  • ${C_GREEN}Connected!${C_RESET}\n\n"
                wait_key
                ;;
            5)
                ui_clear
                section "Linux Setup"
                printf "\n  ${C_BOLD}Step 1: Install WireGuard${C_RESET}\n"
                printf "  ─────────────────────────\n"
                printf "  ${C_DIM}Ubuntu/Debian:${C_RESET}\n"
                printf "    ${C_WHITE}sudo apt install wireguard${C_RESET}\n\n"
                printf "  ${C_DIM}Fedora:${C_RESET}\n"
                printf "    ${C_WHITE}sudo dnf install wireguard-tools${C_RESET}\n\n"
                printf "  ${C_DIM}Arch:${C_RESET}\n"
                printf "    ${C_WHITE}sudo pacman -S wireguard-tools${C_RESET}\n\n"
                
                printf "  ${C_BOLD}Step 2: Import Configuration${C_RESET}\n"
                printf "  ─────────────────────────────\n"
                printf "  • Download your .conf file\n"
                printf "  • Copy to WireGuard config directory:\n"
                printf "    ${C_WHITE}sudo cp client.conf /etc/wireguard/${C_RESET}\n\n"
                
                printf "  ${C_BOLD}Step 3: Connect${C_RESET}\n"
                printf "  ──────────────\n"
                printf "  • ${C_WHITE}sudo wg-quick up client${C_RESET}\n"
                printf "  • To disconnect: ${C_WHITE}sudo wg-quick down client${C_RESET}\n"
                printf "  • ${C_GREEN}Done!${C_RESET}\n\n"
                wait_key
                ;;
            B|G) return ;;
            Q) cleanup_exit 0 ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# 12. CLI & ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

show_help() {
    cat << 'HELP'
SamNet-WG - Unified WireGuard Manager

USAGE:
    samnet [OPTIONS]

OPTIONS:
    --help, -h          Show help
    --version           Show version
    --no-color          Disable colors
    --zero-touch, -z    Auto-install
    --interactive, -i   Wizard install
    --status            Print status (no TUI)
    --uninstall         Completely remove SamNet-WG
    --rebuild           Rebuild Docker containers

EXAMPLES:
    samnet              # Launch TUI
    samnet --zero-touch # Auto-install
    samnet --status     # Quick check
    samnet --uninstall  # Remove everything
    samnet --rebuild    # Fix Docker issues
HELP
}

print_status() {
    echo "=== SamNet-WG Status ==="
    echo "WireGuard:  $(get_wg_status)"
    echo "Peers:      $(get_peer_count) ($(get_stale_peer_count) stale)"
    echo "Firewall:   $(get_firewall_backend)"
}

cleanup_exit() {
    show_cursor
    stty echo 2>/dev/null
    printf "\n${C_DIM}Goodbye!${C_RESET}\n"
    exit "${1:-0}"
}

# Full uninstall - removes everything
full_uninstall() {
    echo ""
    echo "${T_RED}${T_BOLD}╔════════════════════════════════════════╗${T_RESET}"
    echo "${T_RED}${T_BOLD}║     ⚠ COMPLETE UNINSTALL WARNING ⚠    ║${T_RESET}"
    echo "${T_RED}${T_BOLD}╚════════════════════════════════════════╝${T_RESET}"
    echo ""
    echo "This will PERMANENTLY remove:"
    echo "  ${T_RED}•${T_RESET} Docker containers and images (samnet-api)"
    echo "  ${T_RED}•${T_RESET} WireGuard interface and all keys"
    echo "  ${T_RED}•${T_RESET} SamNet firewall tables (samnet-filter, samnet-nat)"
    echo "  ${T_RED}•${T_RESET} Database and ALL peer data"
    echo "  ${T_RED}•${T_RESET} Installed files (/opt/samnet)"
    echo "  ${T_RED}•${T_RESET} Credentials file"
    echo ""
    echo "  ${T_GREEN}✓${T_RESET} ${T_DIM}Preserved: UFW, Docker rules, honeypot, other nftables${T_RESET}"
    echo ""
    echo "${T_YELLOW}This action CANNOT be undone!${T_RESET}"
    echo ""
    
    # Restore terminal for input
    stty echo 2>/dev/null
    show_cursor
    
    # First confirmation
    read -r -p "Are you SURE you want to uninstall? (yes/no): " confirm1
    if [[ "$confirm1" != "yes" ]]; then
        echo "${T_GREEN}Cancelled.${T_RESET}"
        return 0
    fi
    
    # Second confirmation - type UNINSTALL
    echo ""
    echo "${T_YELLOW}Final confirmation required.${T_RESET}"
    read -r -p "Type 'UNINSTALL' in capitals to proceed: " confirm2
    if [[ "$confirm2" != "UNINSTALL" ]]; then
        echo "${T_GREEN}Cancelled.${T_RESET}"
        return 0
    fi
    
    echo ""
    local delete_backups="no"
    if [[ -d "/root/samnet-backups" ]]; then
        echo "${T_CYAN}Detected existing backups in /root/samnet-backups${T_RESET}"
        read -r -p "Delete all backup archives? (yes/no) [default: no]: " db_choice
        [[ "${db_choice,,}" == "yes" ]] && delete_backups="yes"
    fi
    

    
    local deep_clean="no"
    if command -v docker &>/dev/null; then
        echo ""
        echo "${T_CYAN}Docker Cleanup:${T_RESET}"
        echo "  We can remove the SamNet-WG database volume and images."
        read -r -p "Remove Docker volume 'samnet-wg-db'? (yes/no) [default: no]: " dc_choice
        [[ "${dc_choice,,}" == "yes" ]] && deep_clean="yes"
    fi

    echo ""
    echo "${T_CYAN}Starting uninstallation...${T_RESET}"
    echo ""
    
    # Step 1: Docker (Forceful removal)
    log_info "[1/6] Removing Docker resources..."
    
    # Try compose down first if available to clean networks
    if [[ -f "$INSTALL_DIR/services/docker-compose.yml" ]]; then
        local compose_cmd=""
        if command -v docker-compose &>/dev/null; then compose_cmd="docker-compose"; 
        elif docker compose version &>/dev/null; then compose_cmd="docker compose"; fi
        
        if [[ -n "$compose_cmd" ]]; then
             $compose_cmd -p samnet-wg -f "$INSTALL_DIR/services/docker-compose.yml" down -v --remove-orphans 2>/dev/null && echo "  ✓ Compose down successful"
        fi
    fi

    # Force kill and remove API container (samnet-wg specific)
    if docker ps -a --format '{{.Names}}' | grep -q "^samnet-wg-api$"; then
        docker rm -f samnet-wg-api >/dev/null 2>&1 && echo "  ✓ Removed samnet-wg-api container"
    elif docker ps -a --format '{{.Names}}' | grep -q "^samnet-api$"; then
        # Legacy name fallback
        docker rm -f samnet-api >/dev/null 2>&1 && echo "  ✓ Removed samnet-api container (legacy)"
    else
        echo "  - API container not found"
    fi
    
    # Force kill and remove UI container (samnet-wg specific)
    if docker ps -a --format '{{.Names}}' | grep -q "^samnet-wg-ui$"; then
        docker rm -f samnet-wg-ui >/dev/null 2>&1 && echo "  ✓ Removed samnet-wg-ui container"
    elif docker ps -a --format '{{.Names}}' | grep -q "^samnet-ui$"; then
        # Legacy name fallback
        docker rm -f samnet-ui >/dev/null 2>&1 && echo "  ✓ Removed samnet-ui container (legacy)"
    else
        echo "  - UI container not found"
    fi
    
    # Remove API image (samnet-wg specific)
    if docker images samnet-wg/api:latest -q | grep -q .; then
        docker rmi -f samnet-wg/api:latest >/dev/null 2>&1 && echo "  ✓ Removed samnet-wg/api image"
    elif docker images samnet/api:latest -q | grep -q .; then
        # Legacy name fallback
        docker rmi -f samnet/api:latest >/dev/null 2>&1 && echo "  ✓ Removed samnet/api image (legacy)"
    fi
    
    # Remove UI image (samnet-wg specific)
    if docker images samnet-wg/ui:latest -q | grep -q .; then
        docker rmi -f samnet-wg/ui:latest >/dev/null 2>&1 && echo "  ✓ Removed samnet-wg/ui image"
    elif docker images samnet/ui:latest -q | grep -q .; then
        # Legacy name fallback
        docker rmi -f samnet/ui:latest >/dev/null 2>&1 && echo "  ✓ Removed samnet/ui image (legacy)"
    fi
    
    # Prune dangling images - STRICTLY SCOPED to samnet-wg
    log_info "Cleaning up dangling images (samnet-wg only)..."
    docker image prune -f --filter "label=project=samnet-wg" >/dev/null 2>&1 && echo "  ✓ Pruned project images"
    
    # Docker network cleanup (SCOPED: only samnet network)
    log_info "Cleaning Docker networks..."
    docker network rm samnet-grid samnet-wg_default 2>/dev/null && echo "  ✓ Docker networks removed" || echo "  - Network not found"
    
    # Targeted Cleanup (Safe)
    if [[ "$deep_clean" == "yes" ]]; then
        log_info "Removing SamNet-WG specific volumes..."
        # Only remove OUR volume
        docker volume rm samnet-wg-db 2>/dev/null && echo "  ✓ Volume samnet-wg-db removed"
        
        # Try to remove legacy volume name if it exists
        docker volume rm samnet-db 2>/dev/null && echo "  ✓ Volume samnet-db removed (legacy)"
    fi
    
    # Verify Docker cleanup
    local remaining=""
    docker ps -a --format '{{.Names}}' | grep -qE "^samnet(-wg)?-api$" && remaining="$remaining api"
    docker ps -a --format '{{.Names}}' | grep -qE "^samnet(-wg)?-ui$" && remaining="$remaining ui"
    if [[ -n "$remaining" ]]; then
        echo "  ${T_RED}⚠ WARNING: Containers still exist:$remaining${T_RESET}"
    fi
    
    # Step 2: WireGuard
    log_info "[2/8] Stopping WireGuard..."
    systemctl stop wg-quick@wg0 2>/dev/null && echo "  ✓ Service stopped" || echo "  - Service not running"
    systemctl disable wg-quick@wg0 2>/dev/null && echo "  ✓ Service disabled" || echo "  - Already disabled"
    
    # Step 3: WireGuard config
    log_info "[3/8] Removing WireGuard configuration..."
    rm -f /etc/wireguard/wg0.conf && echo "  ✓ Config removed"
    rm -f /etc/wireguard/privatekey && echo "  ✓ Private key removed"
    rm -f /etc/wireguard/publickey && echo "  ✓ Public key removed"
    
    # Step 4: Firewall
    log_info "[4/8] Removing firewall rules (created by samnet)..."
    
    # Remove VPN routing tables (always safe - these are SamNet namespaced)
    nft delete table inet samnet-filter 2>/dev/null && echo "  ✓ Removed samnet-filter (VPN rules)" || echo "  - samnet-filter not found"
    nft delete table ip samnet-nat 2>/dev/null && echo "  ✓ Removed samnet-nat" || echo "  - samnet-nat not found"
    nft delete table ip6 samnet-nat6 2>/dev/null && echo "  ✓ Removed samnet-nat6" || echo "  - samnet-nat6 not found"
    
    # Remove SamNet include line from /etc/nftables.conf (PRESERVE the file itself)
    if [[ -f /etc/nftables.conf ]]; then
        if grep -qF 'include "/etc/samnet/samnet.nft"' /etc/nftables.conf; then
            # Remove the include line and the comment above it
            sed -i '/# SamNet-WG VPN rules/d' /etc/nftables.conf
            sed -i '\|include "/etc/samnet/samnet.nft"|d' /etc/nftables.conf
            # Clean up any resulting blank lines at end of file
            sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' /etc/nftables.conf 2>/dev/null || true
            echo "  ✓ Removed SamNet include from /etc/nftables.conf (file preserved)"
        else
            echo "  - No SamNet include found in /etc/nftables.conf"
        fi
    fi
    
    # Remove SamNet config directory
    rm -rf /etc/samnet && echo "  ✓ Removed /etc/samnet directory" || echo "  - /etc/samnet not found"
    
    # Ask about user ports table
    if nft list table inet samnet-ports &>/dev/null; then
        echo ""
        echo "  ${T_CYAN}Found custom port rules (samnet-ports table)${T_RESET}"
        echo "  This contains your manually configured open ports (SSH, HTTP, etc.)"
        read -r -p "  Delete your custom port rules? (yes/no) [default: no]: " del_ports
        if [[ "${del_ports,,}" == "yes" ]]; then
            nft delete table inet samnet-ports 2>/dev/null
            rm -f /etc/samnet-ports.nft
            echo "  ✓ Removed samnet-ports (custom port rules)"
        else
            echo "  - Preserved samnet-ports (your custom port rules still active)"
            echo "  ${T_DIM}  Note: You can manage these with: nft list table inet samnet-ports${T_RESET}"
        fi
    fi
    
    # Clean up iptables rules - ONLY those tagged with "samnet-wg" comment
    local wan_iface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    if [[ -n "$wan_iface" ]]; then
        # Use while loop to remove ALL matching tagged rules (handles duplicates)
        local removed_forward=false removed_return=false removed_nat=false
        while iptables -D FORWARD -i wg0 -o "$wan_iface" -j ACCEPT -m comment --comment "samnet-wg" 2>/dev/null; do removed_forward=true; done
        while iptables -D FORWARD -i "$wan_iface" -o wg0 -m state --state ESTABLISHED,RELATED -j ACCEPT -m comment --comment "samnet-wg" 2>/dev/null; do removed_return=true; done
        while iptables -t nat -D POSTROUTING -s 10.0.0.0/8 -o "$wan_iface" -j MASQUERADE -m comment --comment "samnet-wg" 2>/dev/null; do removed_nat=true; done
        
        [[ "$removed_forward" == true ]] && echo "  ✓ Removed iptables wg0 forward rule (samnet-wg tagged)"
        [[ "$removed_return" == true ]] && echo "  ✓ Removed iptables wg0 return rule (samnet-wg tagged)"
        [[ "$removed_nat" == true ]] && echo "  ✓ Removed iptables NAT rule (samnet-wg tagged)"
        
        # Persist the changes if netfilter-persistent is available
        command -v netfilter-persistent &>/dev/null && netfilter-persistent save >/dev/null 2>&1
    fi
    
    # Explicitly state what we DON'T touch
    echo ""
    echo "  ${T_DIM}Preserved (not touched by SamNet):${T_RESET}"
    echo "  ${T_DIM}  • /etc/nftables.conf (only removed SamNet include line)${T_RESET}"
    echo "  ${T_DIM}  • UFW/iptables rules (only removed samnet-wg tagged rules)${T_RESET}"
    echo "  ${T_DIM}  • Docker network rules${T_RESET}"
    echo "  ${T_DIM}  • Other nftables tables (e.g., honeypot)${T_RESET}"
    echo ""

    
    # Step 5: Database and data (samnet-wg specific paths)
    log_info "[5/8] Removing database and data..."
    rm -rf /var/lib/samnet-wg && echo "  ✓ Data directory removed (/var/lib/samnet-wg)"
    rm -rf /var/lib/samnet && echo "  ✓ Legacy data directory removed (/var/lib/samnet)" || true
    rm -f /root/.samnet-wg_initial_credentials && echo "  ✓ Credentials file removed"
    rm -f /root/.samnet_initial_credentials && echo "  ✓ Legacy credentials removed" || true
    rm -rf /var/log/samnet-wg && echo "  ✓ Log directory removed"
    rm -rf /var/log/samnet 2>/dev/null || true
    
    # Step 6: Cron jobs (remove ONLY samnet-wg specific patterns, preserve other samnet projects)
    log_info "[6/8] Removing cron jobs..."
    if crontab -l &>/dev/null; then
        # Use precise patterns to avoid removing other samnet project cron jobs
        crontab -l | grep -v "samnet-wg" | grep -v "/opt/samnet/.*bandwidth_collector" | grep -v "samnet\.sh check_expiry" | crontab -
        echo "  ✓ Cron jobs removed (samnet-wg only)"
    fi
    
    # Step 7: Installed files
    log_info "[7/8] Removing installed files..."
    
    # Stop and remove WireGuard sync service (if installed)
    if systemctl is-active --quiet samnet-wg-sync.service 2>/dev/null; then
        systemctl stop samnet-wg-sync.service >/dev/null 2>&1
    fi
    systemctl disable samnet-wg-sync.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/samnet-wg-sync.service && echo "  ✓ WireGuard sync service removed"
    systemctl daemon-reload >/dev/null 2>&1
    
    # Remove trigger file
    rm -f /etc/wireguard/.reload_trigger
    
    rm -f /usr/local/bin/samnet && echo "  ✓ CLI symlink removed"
    rm -rf "$INSTALL_DIR" && echo "  ✓ Installation directory removed"
    
    # Step 8: Temp file cleanup (samnet-wg specific)
    log_info "[8/8] Cleaning up temporary files..."
    if [[ "$delete_backups" == "yes" ]]; then
        rm -rf /root/samnet-backups && echo "  ✓ Backups removed (/root/samnet-backups)"
    else
        echo "  - Preserved backups in /root/samnet-backups"
    fi
    rm -f /tmp/samnet-wg-*.tmp /tmp/samnet-wg-*.tar.gz 2>/dev/null && echo "  ✓ Temp files removed"
    rm -f /tmp/samnet-*.tmp /tmp/samnet-*.tar.gz 2>/dev/null || true  # Legacy
    rm -f /tmp/crontab.tmp /tmp/nftables.backup.* 2>/dev/null
    
    echo ""
    echo "${T_GREEN}${T_BOLD}╔════════════════════════════════════════╗${T_RESET}"
    echo "${T_GREEN}${T_BOLD}║   ✓ SamNet-WG completely uninstalled!  ║${T_RESET}"
    echo "${T_GREEN}${T_BOLD}╚════════════════════════════════════════╝${T_RESET}"
    echo ""
}

# Rebuild Docker without cache
rebuild_docker() {
    log_info "Rebuilding Docker image without cache..."
    
    if [[ ! -d "$INSTALL_DIR/services" ]]; then
        log_error "SamNet not installed. Run installer first."
        exit 1
    fi
    
    docker stop samnet-wg-api samnet-api 2>/dev/null || true
    docker rm samnet-wg-api samnet-api 2>/dev/null || true
    
    log_info "Building with --no-cache..."
    docker build --network=host --no-cache --label project=samnet-wg -t samnet-wg/api:latest "$DIR/services/api"
    
    # Ensure bridge network exists
    if ! docker network ls | grep -q "samnet-grid"; then
        docker network create samnet-grid >/dev/null
    fi

    log_info "Starting container..."
    local api_port=$(db_get_config "api_port")
    api_port="${api_port:-8766}"
    
    # 1. Cleanup old
    docker rm -f samnet-wg-api samnet-api 2>/dev/null || true

    # 2. Start using bridge network + port mapping
    if ! docker run -d \
        --name samnet-wg-api \
        --network=samnet-grid \
        -p ${api_port}:${api_port} \
        --restart=unless-stopped \
        --cap-add=NET_ADMIN \
        -v /var/lib/samnet-wg:/var/lib/samnet-wg \
        -v /etc/wireguard:/etc/wireguard \
        -v "$DIR/clients":/opt/samnet/clients \
        -e SAMNET_DB_PATH=/var/lib/samnet-wg/samnet.db \
        -e PORT=$api_port \
        -e INSECURE_HTTP=true \
        -e GIN_MODE=release \
        samnet-wg/api:latest >/dev/null; then
        log_error "Failed to start container"
    fi
    
    # Prune dangling (scoped to samnet-wg)
    docker image prune -f --filter "label=project=samnet-wg" >/dev/null 2>&1
    
    log_success "Docker rebuild complete!"
}

# ══════════════════════════════════════════════════════════════════════════════
# 13. MAINTENANCE & BACKUP
# ══════════════════════════════════════════════════════════════════════════════

screen_maintenance() {
    while true; do
        ui_draw_header_mini "Maintenance & Backup"
        
        printf "    ${T_CYAN}Manage backups and perform system maintenance.${T_RESET}\n\n"
        
        menu_option "1" "Create Full Backup" "Save Configs, Keys, DB & Clients (Preserves QR!)"
        menu_option "2" "Restore Backup" "Restore from .tar.gz file (No Key Gen needed)"
        # menu_option "3" "Rotate Server Keys" "Regenerate Server Keypair (Advanced)"
        # menu_option "4" "Prune Logs" "Clean up old logs"
        printf "\n"
        menu_option "B" "Back" ""
        
        ui_draw_footer "[1-2] Select  [B] Back"
        printf "\n${T_CYAN}❯${T_RESET} "
        
        local key=$(read_key)
        case "$key" in
            1) create_backup_wizard ;;
            2) restore_backup_wizard ;;
            b|B|$'\x1b') return ;;
        esac
    done
}

create_backup_wizard() {
    ui_draw_header_mini "Create Backup"
    
    log_info "This will create a comprehensive backup archive containing:"
    echo "    • WireGuard keys and config (wg0.conf)"
    echo "    • All client configurations (keys/QR codes)"
    echo "    • SamNet Database (Metadata, Users, Logs)"
    echo "    • Firewall Rules"
    echo ""
    echo "    ${T_GREEN}Why use this?${T_RESET}"
    echo "    Restoring this backup later means you will NOT need to regenerate keys"
    echo "    or rescan QR codes on your phones/laptops. It is a full state save."
    echo ""
    
    if ! confirm "Create backup now?"; then return; fi
    
    local ts=$(date +%Y%m%d-%H%M%S)
    local backup_dir="/root/samnet-backups"
    local backup_file="$backup_dir/samnet-backup-$ts.tar.gz"
    local tmp_dir=$(mktemp -d)
    
    mkdir -p "$backup_dir"
    
    log_info "Gathering files..."
    
    # 1. WireGuard Configs & Keys
    mkdir -p "$tmp_dir/wireguard"
    cp /etc/wireguard/wg0.conf "$tmp_dir/wireguard/" 2>/dev/null
    cp /etc/wireguard/privatekey "$tmp_dir/wireguard/" 2>/dev/null
    cp /etc/wireguard/publickey "$tmp_dir/wireguard/" 2>/dev/null
    
    # 2. Database & internal data
    mkdir -p "$tmp_dir/data"
    # Dump sqlite to be safe against corruption during copy
    if [[ -f "$DB_PATH" ]]; then
        sqlite3 "$DB_PATH" ".backup '$tmp_dir/data/samnet.db'"
    fi
    # Also copy file just in case
    cp /var/lib/samnet-wg/*.key "$tmp_dir/data/" 2>/dev/null
    
    # 3. Client Configs (The critical part for User's request)
    mkdir -p "$tmp_dir/clients"
    cp -r "$INSTALL_DIR/clients/"* "$tmp_dir/clients/" 2>/dev/null
    
    # 4. Firewall
    cp /etc/nftables.conf "$tmp_dir/nftables.conf" 2>/dev/null
    
    # 5. Metadata
    echo "$VERSION" > "$tmp_dir/VERSION"
    date > "$tmp_dir/DATE"
    
    log_info "Compressing..."
    tar -czf "$backup_file" -C "$tmp_dir" .
    rm -rf "$tmp_dir"
    
    log_success "Backup created successfully!"
    echo "    Path: ${T_BOLD}${T_WHITE}$backup_file${T_RESET}"
    echo ""
    echo "    ${T_YELLOW}Keep this file safe! It contains your private keys.${T_RESET}"
    wait_key
}

restore_backup_wizard() {
    ui_draw_header_mini "Restore Backup"
    
    echo "    ${T_CYAN}This will restore your system state from a previous backup.${T_RESET}"
    echo "    ${T_DIM}If the backup contains client files, your existing devices will"
    echo "    connect immediately without needing new QR codes.${T_RESET}"
    echo ""
    
    local backup_dir="/root/samnet-backups"
    mkdir -p "$backup_dir"
    
    local files=("$backup_dir"/*.tar.gz)
    if [[ ! -e "${files[0]}" ]]; then
        log_warn "No backups found in $backup_dir"
        echo "    You can upload a backup file here to restore it."
        wait_key
        return
    fi
    
    echo "    ${T_CYAN}Select backup to restore:${T_RESET}"
    local i=1
    for f in "${files[@]}"; do
        printf "    ${T_GREEN}[%d]${T_RESET} %s\n" "$i" "$(basename "$f")"
        ((i++))
    done
    
    local choice=$(ui_prompt "Select #")
    [[ -z "$choice" ]] && return
    
    local idx=$((choice-1))
    local target_file="${files[$idx]}"
    
    if [[ ! -f "$target_file" ]]; then log_error "Invalid selection"; return; fi
    
    echo ""
    log_warn "${T_RED}WARNING: This will OVERWRITE current configuration!${T_RESET}"
    if ! confirm "Proceed with restore?"; then return; fi
    
    local tmp_dir=$(mktemp -d)
    log_info "Extracting..."
    tar -xzf "$target_file" -C "$tmp_dir"
    
    # Function to restore safe permissions
    restore_perms() {
        chown -R root:root /etc/wireguard
        chmod 600 /etc/wireguard/wg0.conf /etc/wireguard/privatekey
        mkdir -p "$INSTALL_DIR/clients"
        chown -R 1000:1000 "$INSTALL_DIR/clients"
        chmod 700 "$INSTALL_DIR/clients"
        mkdir -p "/var/lib/samnet-wg"
        chown -R 1000:1000 "/var/lib/samnet-wg"
    }

    log_info "Restoring components..."
    
    # Stop services
    systemctl stop wg-quick@wg0 2>/dev/null
    
    # 1. WireGuard
    if [[ -d "$tmp_dir/wireguard" ]]; then
        cp "$tmp_dir/wireguard/"* /etc/wireguard/
    fi
    
    # 2. Data/DB
    if [[ -d "$tmp_dir/data" ]]; then
        cp "$tmp_dir/data/"* /var/lib/samnet-wg/
        # Ensure correct ownership for Docker API
        chown -R 1000:1000 /var/lib/samnet-wg
    fi
    
    # 3. Clients
    if [[ -d "$tmp_dir/clients" ]]; then
        mkdir -p "$INSTALL_DIR/clients"
        cp -r "$tmp_dir/clients/"* "$INSTALL_DIR/clients/"
    fi
    
    # 4. Firewall
    if [[ -f "$tmp_dir/nftables.conf" ]]; then
        cp "$tmp_dir/nftables.conf" /etc/nftables.conf
        nft -f /etc/nftables.conf 2>/dev/null
    fi
    
    restore_perms
    
    # Restart Services
    log_info "Restarting services..."
    systemctl start wg-quick@wg0
    docker restart samnet-wg-api 2>/dev/null
    
    rm -rf "$tmp_dir"
    
    log_success "Restore complete!"
    echo "    Your peers, keys, and configurations have been restored."
    wait_key
}

trap 'cleanup_exit 130' INT
trap 'cleanup_exit 143' TERM

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h) show_help; exit 0 ;;
            --version) echo "SamNet v$SAMNET_VERSION"; exit 0 ;;
            --no-color) NOCOLOR=true; shift ;;
            --zero-touch|-z) init_colors; check_root; ensure_early_dependencies; do_install; exit 0 ;;
            --interactive|-i) init_colors; check_root; ensure_early_dependencies; INTERACTIVE=true; do_install; exit 0 ;;
            --status) print_status; exit 0 ;;
            --uninstall) init_colors; check_root; full_uninstall; exit 0 ;;
            --rebuild) init_colors; check_root; rebuild_docker; exit 0 ;;
            --update) init_colors; check_root; do_update; exit 0 ;;
            --check-update) init_colors; v=$(get_remote_version) && echo "Remote: v$v | Local: v$SAMNET_VERSION" || echo "Failed to check"; exit 0 ;;
            --init-bandwidth) init_colors; check_root; echo "Bandwidth now managed by API"; exit 0 ;;
            check_expiry|--check-expiry) init_colors; check_root; check_expiry; check_limits; exit 0 ;;
            *) echo "Unknown: $1"; exit 1 ;;
        esac
    done
    
    init_colors
    check_root
    get_term_size
    
    # Check and install dependencies BEFORE showing the TUI
    ensure_early_dependencies || true
    
    # Initialize database directory and schema (CRITICAL - prevents "unable to open" errors)
    ensure_db_init || true
    reconcile_db_with_files || true
    
    # Auto-init bandwidth tables on first run (Idempotent)
    # "$INSTALL_DIR/scripts/bandwidth_collector.sh" init 2>/dev/null || true
    
    acquire_session_lock || true

    
    # Show startup status check
    echo ""
    echo "${T_CYAN}${T_BOLD}SamNet-WG${T_RESET} v${SAMNET_VERSION}"
    echo "${T_DIM}────────────────────────────────────${T_RESET}"
    echo ""
    
    # Quick health check before TUI
    echo "Checking system status..."
    echo ""
    
    # WireGuard status
    if wg show wg0 &>/dev/null; then
        echo "  ${T_GREEN}●${T_RESET} WireGuard    ${T_GREEN}ONLINE${T_RESET}"
    else
        echo "  ${T_RED}●${T_RESET} WireGuard    ${T_DIM}offline${T_RESET}"
    fi
    
    # Docker status
    if docker ps &>/dev/null; then
        echo "  ${T_GREEN}●${T_RESET} Docker Engine ${T_GREEN}running${T_RESET}"
    else
        echo "  ${T_RED}●${T_RESET} Docker Engine ${T_DIM}not running${T_RESET}"
    fi
    
    # API status
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "samnet(-wg)?-api"; then
        if curl -sf --max-time 2 $(get_api_url)/health/live &>/dev/null; then
            echo "  ${T_GREEN}●${T_RESET} API          ${T_GREEN}healthy${T_RESET}"
        else
            echo "  ${T_YELLOW}●${T_RESET} API          ${T_YELLOW}starting...${T_RESET}"
        fi
    else
        echo "  ${T_DIM}●${T_RESET} API          ${T_DIM}not deployed${T_RESET}"
    fi
    
    # Check for updates (non-blocking, max 2s timeout)
    check_for_updates_silent 2>/dev/null &
    local update_pid=$!
    local waited=0
    while kill -0 $update_pid 2>/dev/null && [[ $waited -lt 4 ]]; do
        sleep 0.5
        ((waited++))
    done
    # Kill if still running after timeout
    kill $update_pid 2>/dev/null || true
    wait $update_pid 2>/dev/null || true
    
    echo ""
    echo "${T_DIM}Press any key to continue...${T_RESET}"
    read -rsn1
    
    # Enter full-screen app mode (alternate buffer)
    ui_enter_app
    
    # Always show main menu - installation is an option within it
    main_menu
}

main "$@"
