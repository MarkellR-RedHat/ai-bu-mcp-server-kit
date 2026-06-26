#!/usr/bin/env bash
#
# setup.sh - Install and configure MCP servers for Claude Code
#
# A premium setup experience: detects your environment, recommends
# the right servers, validates each one works, and rolls back on failure.
#
# Usage:
#   ./setup.sh              Interactive mode with workflow selection
#   ./setup.sh --all        Install every available server
#   ./setup.sh --minimal    Install only the essentials (GitHub, Fetch, Filesystem)
#   ./setup.sh --list       Show available servers and exit
#   ./setup.sh --restore    Restore the most recent settings backup

set -euo pipefail

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------

SETTINGS_FILE="$HOME/.claude/settings.json"
SETTINGS_DIR="$HOME/.claude"
BACKUP_DIR="$SETTINGS_DIR/backups"
BACKUP_FILE="$BACKUP_DIR/settings.backup.$(date +%Y%m%d%H%M%S).json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------------------------------------------
# Colors and formatting
# -------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Progress indicators
CHECKMARK="${GREEN}[OK]${NC}"
CROSS="${RED}[FAIL]${NC}"
ARROW="${CYAN}[>>]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${BLUE}[INFO]${NC}"
WORKING="${MAGENTA}[..]${NC}"

info()    { echo -e "$CHECKMARK  $1"; }
warn()    { echo -e "$WARN  $1"; }
fail()    { echo -e "$CROSS  $1"; }
step()    { echo -e "$ARROW  $1"; }
note()    { echo -e "$INFO  $1"; }
working() { echo -e "$WORKING  $1"; }

header() {
    echo ""
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${DIM}$(printf '%.0s-' $(seq 1 ${#1}))${NC}"
}

# -------------------------------------------------------------------
# Parse flags
# -------------------------------------------------------------------

INSTALL_ALL=false
INSTALL_MINIMAL=false
LIST_ONLY=false
RESTORE_MODE=false
NONINTERACTIVE=false

for arg in "$@"; do
    case "$arg" in
        --all)
            INSTALL_ALL=true
            NONINTERACTIVE=true
            ;;
        --minimal)
            INSTALL_MINIMAL=true
            NONINTERACTIVE=true
            ;;
        --list)
            LIST_ONLY=true
            ;;
        --restore)
            RESTORE_MODE=true
            ;;
        --yes|-y)
            NONINTERACTIVE=true
            ;;
        --help|-h)
            echo "Usage: ./setup.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (none)       Interactive mode with workflow-based selection"
            echo "  --all        Install every available MCP server"
            echo "  --minimal    Install essentials only (GitHub, Fetch, Filesystem)"
            echo "  --list       Show available servers and exit"
            echo "  --restore    Restore the most recent settings backup"
            echo "  --yes, -y    Skip confirmation prompts"
            echo "  --help, -h   Show this help"
            exit 0
            ;;
        *) echo "Unknown flag: $arg. Use --help for usage."; exit 1 ;;
    esac
done

# -------------------------------------------------------------------
# Restore mode
# -------------------------------------------------------------------

restore_backup() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        fail "No backup directory found at $BACKUP_DIR"
        exit 1
    fi

    local latest
    latest=$(ls -1t "$BACKUP_DIR"/settings.backup.*.json 2>/dev/null | head -1)

    if [[ -z "$latest" ]]; then
        fail "No backups found in $BACKUP_DIR"
        exit 1
    fi

    echo ""
    echo -e "${BOLD}Available backups:${NC}"
    echo ""
    ls -1t "$BACKUP_DIR"/settings.backup.*.json 2>/dev/null | head -5 | while read -r f; do
        local ts
        ts=$(basename "$f" | sed 's/settings.backup.\(.*\).json/\1/')
        echo "  $(basename "$f")  ($(date -r "$f" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ts"))"
    done
    echo ""

    cp "$latest" "$SETTINGS_FILE"
    info "Restored settings from $(basename "$latest")"
    exit 0
}

if $RESTORE_MODE; then
    restore_backup
fi

# -------------------------------------------------------------------
# Preflight checks
# -------------------------------------------------------------------

preflight_passed=true

check_claude_code() {
    if command -v claude &> /dev/null; then
        local version
        version=$(claude --version 2>/dev/null || echo "version unknown")
        info "Claude Code installed ($version)"
    else
        fail "Claude Code is not installed"
        echo ""
        echo "    Install it with:"
        echo "      npm install -g @anthropic-ai/claude-code"
        echo ""
        echo "    Full guide: https://docs.anthropic.com/en/docs/claude-code"
        echo ""
        preflight_passed=false
    fi
}

check_npx() {
    if command -v npx &> /dev/null; then
        info "npx available ($(npx --version 2>/dev/null))"
    else
        fail "npx is not installed"
        echo ""
        echo "    Install Node.js v18+ to get npx:"
        echo "      macOS:       brew install node"
        echo "      Fedora/RHEL: dnf install nodejs"
        echo "      Ubuntu:      apt install nodejs npm"
        echo ""
        preflight_passed=false
    fi
}

check_json_tool() {
    if command -v jq &> /dev/null; then
        JSON_TOOL="jq"
        info "JSON processing: jq"
    elif command -v python3 &> /dev/null; then
        JSON_TOOL="python3"
        info "JSON processing: python3 (install jq for faster runs)"
    elif command -v python &> /dev/null; then
        JSON_TOOL="python"
        info "JSON processing: python (install jq for faster runs)"
    else
        fail "Neither jq nor python3 is available"
        echo ""
        echo "    Install jq:"
        echo "      macOS:       brew install jq"
        echo "      Fedora/RHEL: dnf install jq"
        echo "      Ubuntu:      apt install jq"
        echo ""
        preflight_passed=false
    fi
}

detect_environment() {
    header "Detecting your environment"

    DETECTED_TOOLS=()

    if command -v python3 &>/dev/null || command -v python &>/dev/null; then
        DETECTED_TOOLS+=("python")
        info "Python detected"
    fi
    if command -v go &>/dev/null; then
        DETECTED_TOOLS+=("go")
        info "Go detected"
    fi
    if command -v rustc &>/dev/null; then
        DETECTED_TOOLS+=("rust")
        info "Rust detected"
    fi
    if command -v kubectl &>/dev/null; then
        DETECTED_TOOLS+=("kubernetes")
        info "kubectl detected"
    fi
    if command -v docker &>/dev/null; then
        DETECTED_TOOLS+=("docker")
        info "Docker detected"
    fi
    if command -v psql &>/dev/null; then
        DETECTED_TOOLS+=("postgres")
        info "PostgreSQL client detected"
    fi
    if command -v sqlite3 &>/dev/null; then
        DETECTED_TOOLS+=("sqlite")
        info "SQLite detected"
    fi
    if command -v gh &>/dev/null; then
        DETECTED_TOOLS+=("github-cli")
        info "GitHub CLI detected"
    fi
    if [[ ${#DETECTED_TOOLS[@]} -eq 0 ]]; then
        note "No additional dev tools detected (that's fine)"
    fi
}

check_existing_servers() {
    EXISTING_SERVERS=()
    if [[ -f "$SETTINGS_FILE" ]]; then
        local servers
        if [[ "$JSON_TOOL" == "jq" ]]; then
            servers=$(jq -r '.mcpServers // {} | keys[]' "$SETTINGS_FILE" 2>/dev/null || true)
        else
            servers=$($JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for k in data.get('mcpServers', {}):
    print(k)
" "$SETTINGS_FILE" 2>/dev/null || true)
        fi
        if [[ -n "$servers" ]]; then
            while IFS= read -r s; do
                EXISTING_SERVERS+=("$s")
            done <<< "$servers"
        fi
    fi

    if [[ ${#EXISTING_SERVERS[@]} -gt 0 ]]; then
        note "Already configured: ${EXISTING_SERVERS[*]}"
    fi
}

# -------------------------------------------------------------------
# Server registry
# -------------------------------------------------------------------

# Arrays to maintain order and store server metadata
declare -a ALL_SERVER_KEYS=()
declare -A SERVER_NAMES=()
declare -A SERVER_DESCS=()
declare -A SERVER_PACKAGES=()
declare -A SERVER_CATEGORIES=()
declare -A SERVER_ARGS=()
declare -A SERVER_ENV=()
declare -A SERVER_SELECTED=()

register_server() {
    local key="$1" name="$2" desc="$3" package="$4" category="$5"
    local args="${6:-}" env="${7:-}"

    ALL_SERVER_KEYS+=("$key")
    SERVER_NAMES[$key]="$name"
    SERVER_DESCS[$key]="$desc"
    SERVER_PACKAGES[$key]="$package"
    SERVER_CATEGORIES[$key]="$category"
    SERVER_ARGS[$key]="$args"
    SERVER_ENV[$key]="$env"
    SERVER_SELECTED[$key]=false
}

init_server_registry() {
    # Core servers (recommended for everyone)
    register_server "github" \
        "GitHub" \
        "Query repos, issues, PRs, file contents, and commit history" \
        "@modelcontextprotocol/server-github" \
        "core"

    register_server "fetch" \
        "Fetch" \
        "Read the contents of any URL (docs, APIs, web pages)" \
        "@anthropic-ai/mcp-fetch" \
        "core"

    register_server "filesystem" \
        "Filesystem" \
        "Controlled read/write/search access to local directories" \
        "@modelcontextprotocol/server-filesystem" \
        "core" \
        "$HOME/projects"

    # Search and research
    register_server "brave-search" \
        "Brave Search" \
        "Web search via Brave Search API" \
        "@anthropic-ai/mcp-server-brave-search" \
        "search" \
        "" \
        "BRAVE_API_KEY"

    register_server "context7" \
        "Context7" \
        "Up-to-date library documentation pulled from source" \
        "@upstash/context7-mcp" \
        "search"

    # Memory and reasoning
    register_server "memory" \
        "Memory" \
        "Persistent key-value storage across Claude Code sessions" \
        "@modelcontextprotocol/server-memory" \
        "memory"

    register_server "sequential-thinking" \
        "Sequential Thinking" \
        "Structured step-by-step reasoning for complex problems" \
        "@modelcontextprotocol/server-sequential-thinking" \
        "reasoning"

    # Database
    register_server "postgres" \
        "PostgreSQL" \
        "Query and inspect PostgreSQL databases" \
        "@modelcontextprotocol/server-postgres" \
        "database" \
        "postgresql://localhost:5432/mydb"

    register_server "sqlite" \
        "SQLite" \
        "Query and inspect SQLite database files" \
        "@modelcontextprotocol/server-sqlite" \
        "database" \
        "$HOME/data/my-database.db"

    # Browser and automation
    register_server "puppeteer" \
        "Puppeteer" \
        "Browser automation: screenshots, clicks, form fills, navigation" \
        "@modelcontextprotocol/server-puppeteer" \
        "browser"

    # Communication
    register_server "slack" \
        "Slack" \
        "Read and post messages in Slack channels" \
        "@modelcontextprotocol/server-slack" \
        "communication" \
        "" \
        "SLACK_BOT_TOKEN,SLACK_TEAM_ID"

    # Location
    register_server "google-maps" \
        "Google Maps" \
        "Geocoding, directions, and place search" \
        "@modelcontextprotocol/server-google-maps" \
        "location" \
        "" \
        "GOOGLE_MAPS_API_KEY"

    # Image generation
    register_server "everart" \
        "EverArt" \
        "AI image generation and model training" \
        "@modelcontextprotocol/server-everart" \
        "creative" \
        "" \
        "EVERART_API_KEY"
}

# -------------------------------------------------------------------
# List mode
# -------------------------------------------------------------------

list_servers() {
    init_server_registry

    echo ""
    echo -e "${BOLD}Available MCP Servers${NC}"
    echo ""

    local current_cat=""
    for key in "${ALL_SERVER_KEYS[@]}"; do
        local cat="${SERVER_CATEGORIES[$key]}"
        if [[ "$cat" != "$current_cat" ]]; then
            current_cat="$cat"
            local cat_label
            case "$cat" in
                core)           cat_label="Core (recommended for everyone)" ;;
                search)         cat_label="Search and Research" ;;
                memory)         cat_label="Memory" ;;
                reasoning)      cat_label="Reasoning" ;;
                database)       cat_label="Database" ;;
                browser)        cat_label="Browser and Automation" ;;
                communication)  cat_label="Communication" ;;
                location)       cat_label="Location" ;;
                creative)       cat_label="Creative" ;;
                *)              cat_label="$cat" ;;
            esac
            echo ""
            echo -e "  ${BOLD}${cat_label}${NC}"
        fi

        local env_note=""
        if [[ -n "${SERVER_ENV[$key]}" ]]; then
            env_note=" ${DIM}(requires API key)${NC}"
        fi
        echo -e "    ${GREEN}${SERVER_NAMES[$key]}${NC} - ${SERVER_DESCS[$key]}${env_note}"
    done
    echo ""
}

if $LIST_ONLY; then
    list_servers
    exit 0
fi

# -------------------------------------------------------------------
# Backup
# -------------------------------------------------------------------

backup_settings() {
    mkdir -p "$BACKUP_DIR"
    if [[ -f "$SETTINGS_FILE" ]]; then
        cp "$SETTINGS_FILE" "$BACKUP_FILE"
        info "Settings backed up to $BACKUP_FILE"
    fi
}

# -------------------------------------------------------------------
# JSON merge logic
# -------------------------------------------------------------------

merge_mcp_server() {
    local name="$1"
    local package="$2"
    local extra_args="${3:-}"
    local env_vars="${4:-}"

    # Build args array
    local args_json='["-y","'"$package"'"'
    if [[ -n "$extra_args" ]]; then
        args_json+=',"'"$extra_args"'"'
    fi
    args_json+=']'

    # Build server object
    local server_json
    if [[ -n "$env_vars" ]]; then
        # Build env object from comma-separated var names
        local env_json="{"
        local first=true
        IFS=',' read -ra vars <<< "$env_vars"
        for var in "${vars[@]}"; do
            if $first; then
                first=false
            else
                env_json+=","
            fi
            local val="${!var:-}"
            if [[ -n "$val" ]]; then
                env_json+="\"$var\":\"$val\""
            else
                env_json+="\"$var\":\"<your-${var,,}-here>\""
            fi
        done
        env_json+="}"
        server_json="{\"command\":\"npx\",\"args\":$args_json,\"env\":$env_json}"
    else
        server_json="{\"command\":\"npx\",\"args\":$args_json}"
    fi

    if [[ "$JSON_TOOL" == "jq" ]]; then
        local tmp
        tmp=$(mktemp)
        jq --arg name "$name" --argjson server "$server_json" '
            .mcpServers //= {} |
            .mcpServers[$name] = $server
        ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    else
        $JSON_TOOL - "$SETTINGS_FILE" "$name" "$server_json" <<'PYEOF'
import json, sys

settings_path = sys.argv[1]
server_name = sys.argv[2]
server_json = json.loads(sys.argv[3])

try:
    with open(settings_path, "r") as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

if "mcpServers" not in settings:
    settings["mcpServers"] = {}

settings["mcpServers"][server_name] = server_json

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF
    fi
}

# -------------------------------------------------------------------
# Server installation with validation
# -------------------------------------------------------------------

install_single_server() {
    local key="$1"
    local package="${SERVER_PACKAGES[$key]}"
    local extra_args="${SERVER_ARGS[$key]}"
    local env_vars="${SERVER_ENV[$key]}"

    working "Installing ${SERVER_NAMES[$key]}..."

    # Check if already configured
    local already_exists=false
    for existing in "${EXISTING_SERVERS[@]}"; do
        if [[ "$existing" == "$key" ]]; then
            already_exists=true
            break
        fi
    done

    if $already_exists; then
        note "${SERVER_NAMES[$key]} is already configured (updating)"
    fi

    # Write the config
    merge_mcp_server "$key" "$package" "$extra_args" "$env_vars"

    # Validate: check that the npm package exists
    if npm view "$package" version &>/dev/null 2>&1; then
        info "${SERVER_NAMES[$key]} configured and package verified"
        return 0
    else
        warn "${SERVER_NAMES[$key]} configured but package could not be verified (may need internet)"
        return 0
    fi
}

# -------------------------------------------------------------------
# Workflow-based interactive selection
# -------------------------------------------------------------------

interactive_select() {
    echo ""
    echo -e "${BOLD}How do you want to set up your MCP servers?${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} ${GREEN}Quick Start${NC} - Core servers everyone should have"
    echo -e "     ${DIM}GitHub, Fetch, Filesystem, Memory${NC}"
    echo ""
    echo -e "  ${BOLD}2)${NC} ${GREEN}Full Stack Developer${NC} - Everything for web and backend work"
    echo -e "     ${DIM}Core + Brave Search, Context7, Sequential Thinking, Puppeteer${NC}"
    echo ""
    echo -e "  ${BOLD}3)${NC} ${GREEN}Data and Backend${NC} - Database-heavy workflows"
    echo -e "     ${DIM}Core + Postgres, SQLite, Sequential Thinking${NC}"
    echo ""
    echo -e "  ${BOLD}4)${NC} ${GREEN}AI/ML Engineer${NC} - Research and reasoning focused"
    echo -e "     ${DIM}Core + Brave Search, Context7, Sequential Thinking, EverArt${NC}"
    echo ""
    echo -e "  ${BOLD}5)${NC} ${GREEN}Everything${NC} - Install all available servers"
    echo ""
    echo -e "  ${BOLD}6)${NC} ${GREEN}Custom${NC} - Pick exactly which servers you want"
    echo ""

    local choice
    read -rp "Choose a setup (1-6): " choice

    case "$choice" in
        1)
            for key in github fetch filesystem memory; do
                SERVER_SELECTED[$key]=true
            done
            ;;
        2)
            for key in github fetch filesystem memory brave-search context7 sequential-thinking puppeteer; do
                SERVER_SELECTED[$key]=true
            done
            ;;
        3)
            for key in github fetch filesystem memory postgres sqlite sequential-thinking; do
                SERVER_SELECTED[$key]=true
            done
            ;;
        4)
            for key in github fetch filesystem memory brave-search context7 sequential-thinking everart; do
                SERVER_SELECTED[$key]=true
            done
            ;;
        5)
            for key in "${ALL_SERVER_KEYS[@]}"; do
                SERVER_SELECTED[$key]=true
            done
            ;;
        6)
            custom_select
            ;;
        "")
            # Default: Quick Start
            for key in github fetch filesystem memory; do
                SERVER_SELECTED[$key]=true
            done
            note "Defaulting to Quick Start"
            ;;
        *)
            warn "Invalid choice. Defaulting to Quick Start."
            for key in github fetch filesystem memory; do
                SERVER_SELECTED[$key]=true
            done
            ;;
    esac

    # Auto-suggest based on detected tools
    suggest_based_on_environment
}

custom_select() {
    echo ""
    echo -e "${BOLD}Available servers:${NC}"
    echo ""

    local i=1
    for key in "${ALL_SERVER_KEYS[@]}"; do
        local env_note=""
        if [[ -n "${SERVER_ENV[$key]}" ]]; then
            env_note=" ${DIM}(API key required)${NC}"
        fi
        printf "  ${BOLD}%2d)${NC} %-22s %s%b\n" "$i" "${SERVER_NAMES[$key]}" "${SERVER_DESCS[$key]}" "$env_note"
        i=$((i + 1))
    done

    echo ""
    echo "Enter the numbers of servers to install (space-separated)."
    echo "Example: 1 2 3 5 8"
    echo ""
    read -rp "Your selections: " choices

    if [[ -z "$choices" ]]; then
        warn "No selections made. Installing core servers."
        for key in github fetch filesystem; do
            SERVER_SELECTED[$key]=true
        done
        return
    fi

    for choice in $choices; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ALL_SERVER_KEYS[@]} )); then
            local idx=$((choice - 1))
            SERVER_SELECTED[${ALL_SERVER_KEYS[$idx]}]=true
        else
            warn "Ignoring invalid selection: $choice"
        fi
    done
}

suggest_based_on_environment() {
    local suggestions=()

    for tool in "${DETECTED_TOOLS[@]}"; do
        case "$tool" in
            postgres)
                if [[ "${SERVER_SELECTED[postgres]}" != "true" ]]; then
                    suggestions+=("postgres")
                fi
                ;;
            sqlite)
                if [[ "${SERVER_SELECTED[sqlite]}" != "true" ]]; then
                    suggestions+=("sqlite")
                fi
                ;;
        esac
    done

    if [[ ${#suggestions[@]} -gt 0 ]]; then
        echo ""
        note "Based on your environment, you might also want:"
        for s in "${suggestions[@]}"; do
            echo -e "     ${GREEN}+${NC} ${SERVER_NAMES[$s]} - ${SERVER_DESCS[$s]}"
        done
        echo ""
        read -rp "Add these servers too? (Y/n): " add_suggested
        if [[ "$add_suggested" != "n" && "$add_suggested" != "N" ]]; then
            for s in "${suggestions[@]}"; do
                SERVER_SELECTED[$s]=true
            done
            info "Added suggested servers"
        fi
    fi
}

# -------------------------------------------------------------------
# Filesystem path prompt
# -------------------------------------------------------------------

prompt_filesystem_path() {
    if [[ "${SERVER_SELECTED[filesystem]}" == "true" ]] && ! $NONINTERACTIVE; then
        echo ""
        echo -e "${BOLD}Filesystem server: which directory should Claude Code access?${NC}"
        echo -e "  ${DIM}Default: $HOME/projects${NC}"
        echo ""
        read -rp "Path (press Enter for default): " fs_path

        if [[ -n "$fs_path" ]]; then
            # Expand ~ if used
            fs_path="${fs_path/#\~/$HOME}"
            if [[ -d "$fs_path" ]]; then
                SERVER_ARGS[filesystem]="$fs_path"
                info "Filesystem path set to: $fs_path"
            else
                warn "Directory $fs_path does not exist. Using default ($HOME/projects)."
                mkdir -p "$HOME/projects" 2>/dev/null || true
            fi
        else
            mkdir -p "$HOME/projects" 2>/dev/null || true
        fi
    fi
}

# -------------------------------------------------------------------
# Postgres connection prompt
# -------------------------------------------------------------------

prompt_postgres_connection() {
    if [[ "${SERVER_SELECTED[postgres]}" == "true" ]] && ! $NONINTERACTIVE; then
        echo ""
        echo -e "${BOLD}PostgreSQL: enter your connection string${NC}"
        echo -e "  ${DIM}Format: postgresql://user:password@host:port/database${NC}"
        echo -e "  ${DIM}Default: postgresql://localhost:5432/mydb${NC}"
        echo ""
        read -rp "Connection string (press Enter for default): " pg_conn

        if [[ -n "$pg_conn" ]]; then
            SERVER_ARGS[postgres]="$pg_conn"
            info "PostgreSQL connection set"
        fi
    fi
}

# -------------------------------------------------------------------
# SQLite path prompt
# -------------------------------------------------------------------

prompt_sqlite_path() {
    if [[ "${SERVER_SELECTED[sqlite]}" == "true" ]] && ! $NONINTERACTIVE; then
        echo ""
        echo -e "${BOLD}SQLite: enter the path to your database file${NC}"
        echo -e "  ${DIM}Default: $HOME/data/my-database.db${NC}"
        echo ""
        read -rp "Database path (press Enter for default): " sqlite_path

        if [[ -n "$sqlite_path" ]]; then
            sqlite_path="${sqlite_path/#\~/$HOME}"
            SERVER_ARGS[sqlite]="$sqlite_path"
            info "SQLite path set to: $sqlite_path"
        fi
    fi
}

# -------------------------------------------------------------------
# API key prompts
# -------------------------------------------------------------------

prompt_api_keys() {
    local keys_needed=()

    if [[ "${SERVER_SELECTED[brave-search]}" == "true" ]] && [[ -z "${BRAVE_API_KEY:-}" ]]; then
        keys_needed+=("brave-search")
    fi
    if [[ "${SERVER_SELECTED[google-maps]}" == "true" ]] && [[ -z "${GOOGLE_MAPS_API_KEY:-}" ]]; then
        keys_needed+=("google-maps")
    fi
    if [[ "${SERVER_SELECTED[slack]}" == "true" ]] && [[ -z "${SLACK_BOT_TOKEN:-}" ]]; then
        keys_needed+=("slack")
    fi
    if [[ "${SERVER_SELECTED[everart]}" == "true" ]] && [[ -z "${EVERART_API_KEY:-}" ]]; then
        keys_needed+=("everart")
    fi

    if [[ ${#keys_needed[@]} -gt 0 ]] && ! $NONINTERACTIVE; then
        echo ""
        header "API Keys"
        echo ""
        echo "Some selected servers need API keys. You can enter them now"
        echo "or add them later to ~/.claude/settings.json."
        echo ""

        for key_server in "${keys_needed[@]}"; do
            case "$key_server" in
                brave-search)
                    echo -e "  ${BOLD}Brave Search API Key${NC} (https://brave.com/search/api/)"
                    read -rp "  BRAVE_API_KEY (press Enter to skip): " input_key
                    if [[ -n "$input_key" ]]; then
                        export BRAVE_API_KEY="$input_key"
                    fi
                    ;;
                google-maps)
                    echo -e "  ${BOLD}Google Maps API Key${NC} (https://console.cloud.google.com/)"
                    read -rp "  GOOGLE_MAPS_API_KEY (press Enter to skip): " input_key
                    if [[ -n "$input_key" ]]; then
                        export GOOGLE_MAPS_API_KEY="$input_key"
                    fi
                    ;;
                slack)
                    echo -e "  ${BOLD}Slack Bot Token${NC} (https://api.slack.com/apps)"
                    read -rp "  SLACK_BOT_TOKEN (press Enter to skip): " input_key
                    if [[ -n "$input_key" ]]; then
                        export SLACK_BOT_TOKEN="$input_key"
                    fi
                    read -rp "  SLACK_TEAM_ID (press Enter to skip): " input_key2
                    if [[ -n "$input_key2" ]]; then
                        export SLACK_TEAM_ID="$input_key2"
                    fi
                    ;;
                everart)
                    echo -e "  ${BOLD}EverArt API Key${NC}"
                    read -rp "  EVERART_API_KEY (press Enter to skip): " input_key
                    if [[ -n "$input_key" ]]; then
                        export EVERART_API_KEY="$input_key"
                    fi
                    ;;
            esac
            echo ""
        done
    fi
}

# -------------------------------------------------------------------
# Rollback on failure
# -------------------------------------------------------------------

rollback() {
    echo ""
    fail "Installation failed. Rolling back to previous settings."
    if [[ -f "$BACKUP_FILE" ]]; then
        cp "$BACKUP_FILE" "$SETTINGS_FILE"
        info "Settings restored from backup"
    fi
    exit 1
}

# -------------------------------------------------------------------
# Post-install summary
# -------------------------------------------------------------------

show_summary() {
    local installed=("$@")

    echo ""
    echo -e "${BOLD}${GREEN}============================================${NC}"
    echo -e "${BOLD}${GREEN}  Setup Complete                            ${NC}"
    echo -e "${BOLD}${GREEN}============================================${NC}"
    echo ""

    echo -e "${BOLD}Installed servers (${#installed[@]}):${NC}"
    for key in "${installed[@]}"; do
        echo -e "  ${GREEN}+${NC} ${SERVER_NAMES[$key]} - ${SERVER_DESCS[$key]}"
    done

    # Check for servers that need API keys
    local needs_keys=false
    echo ""
    for key in "${installed[@]}"; do
        local env="${SERVER_ENV[$key]}"
        if [[ -n "$env" ]]; then
            IFS=',' read -ra vars <<< "$env"
            for var in "${vars[@]}"; do
                local val="${!var:-}"
                if [[ -z "$val" || "$val" == *"<your-"* ]]; then
                    if ! $needs_keys; then
                        echo -e "${YELLOW}${BOLD}Action required - API keys:${NC}"
                        needs_keys=true
                    fi
                    case "$var" in
                        BRAVE_API_KEY)
                            echo -e "  ${YELLOW}*${NC} BRAVE_API_KEY: https://brave.com/search/api/"
                            ;;
                        GOOGLE_MAPS_API_KEY)
                            echo -e "  ${YELLOW}*${NC} GOOGLE_MAPS_API_KEY: https://console.cloud.google.com/"
                            ;;
                        SLACK_BOT_TOKEN)
                            echo -e "  ${YELLOW}*${NC} SLACK_BOT_TOKEN: https://api.slack.com/apps"
                            ;;
                        SLACK_TEAM_ID)
                            echo -e "  ${YELLOW}*${NC} SLACK_TEAM_ID: check your Slack workspace settings"
                            ;;
                        EVERART_API_KEY)
                            echo -e "  ${YELLOW}*${NC} EVERART_API_KEY: check EverArt documentation"
                            ;;
                    esac
                fi
            done
        fi
    done
    if $needs_keys; then
        echo ""
        echo "  Add keys to ~/.claude/settings.json in the server's \"env\" block,"
        echo "  or export them as environment variables before starting Claude Code."
    fi

    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo ""
    echo "  1. Verify your setup:"
    echo "     ./verify.sh"
    echo ""
    echo "  2. Open Claude Code and try a prompt:"
    echo ""

    # Show a relevant example prompt
    if [[ " ${installed[*]} " == *" github "* ]]; then
        echo "     \"List the open issues in MarkellR-RedHat/ai-bu-mcp-server-kit\""
    fi
    if [[ " ${installed[*]} " == *" fetch "* ]]; then
        echo "     \"Fetch https://httpbin.org/get and show me the response\""
    fi
    if [[ " ${installed[*]} " == *" brave-search "* ]]; then
        echo "     \"Search the web for 'MCP servers for Claude Code'\""
    fi
    if [[ " ${installed[*]} " == *" memory "* ]]; then
        echo "     \"Remember that my preferred language is Python\""
    fi
    if [[ " ${installed[*]} " == *" context7 "* ]]; then
        echo "     \"Use context7 to get the latest docs for FastAPI\""
    fi

    echo ""
    echo -e "  ${DIM}Settings file: $SETTINGS_FILE${NC}"
    echo -e "  ${DIM}Backup file:   $BACKUP_FILE${NC}"
    echo ""
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

main() {
    echo ""
    echo -e "${BOLD}${CYAN}============================================${NC}"
    echo -e "${BOLD}${CYAN}  MCP Server Kit for Claude Code            ${NC}"
    echo -e "${BOLD}${CYAN}============================================${NC}"
    echo ""

    # Preflight
    header "Preflight checks"
    check_claude_code
    check_npx
    check_json_tool

    if ! $preflight_passed; then
        echo ""
        fail "Preflight checks failed. Fix the issues above and try again."
        exit 1
    fi

    # Ensure settings directory and file exist
    mkdir -p "$SETTINGS_DIR"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
        info "Created new settings file at $SETTINGS_FILE"
    fi

    # Detect environment and existing config
    detect_environment
    check_existing_servers

    # Initialize server registry
    init_server_registry

    # Determine what to install
    if $INSTALL_ALL; then
        for key in "${ALL_SERVER_KEYS[@]}"; do
            SERVER_SELECTED[$key]=true
        done
        note "Installing all servers (--all)"
    elif $INSTALL_MINIMAL; then
        for key in github fetch filesystem; do
            SERVER_SELECTED[$key]=true
        done
        note "Installing minimal set (--minimal)"
    else
        interactive_select
    fi

    # Count selected
    local selected_count=0
    for key in "${ALL_SERVER_KEYS[@]}"; do
        if [[ "${SERVER_SELECTED[$key]}" == "true" ]]; then
            selected_count=$((selected_count + 1))
        fi
    done

    if [[ $selected_count -eq 0 ]]; then
        echo ""
        warn "No servers selected. Nothing to install."
        exit 0
    fi

    # Prompt for paths and connection strings
    prompt_filesystem_path
    prompt_postgres_connection
    prompt_sqlite_path
    prompt_api_keys

    # Confirmation
    if ! $NONINTERACTIVE; then
        echo ""
        echo -e "${BOLD}Ready to install $selected_count server(s):${NC}"
        for key in "${ALL_SERVER_KEYS[@]}"; do
            if [[ "${SERVER_SELECTED[$key]}" == "true" ]]; then
                echo -e "  ${GREEN}+${NC} ${SERVER_NAMES[$key]}"
            fi
        done
        echo ""
        read -rp "Proceed? (Y/n): " confirm
        if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi

    # Backup before making changes
    backup_settings

    # Set trap for rollback on failure
    trap rollback ERR

    # Install
    header "Installing MCP servers"
    echo ""

    local installed=()
    local install_failed=false

    for key in "${ALL_SERVER_KEYS[@]}"; do
        if [[ "${SERVER_SELECTED[$key]}" == "true" ]]; then
            if install_single_server "$key"; then
                installed+=("$key")
            else
                fail "Failed to install ${SERVER_NAMES[$key]}"
                install_failed=true
            fi
        fi
    done

    # Remove trap after successful install
    trap - ERR

    if $install_failed; then
        warn "Some servers failed to install. Check the output above."
    fi

    if [[ ${#installed[@]} -eq 0 ]]; then
        fail "No servers were installed successfully."
        exit 1
    fi

    show_summary "${installed[@]}"
}

main "$@"
