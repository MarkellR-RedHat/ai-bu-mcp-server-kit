#!/usr/bin/env bash
#
# setup.sh - Configure MCP servers for Claude Code
#
# After setup, Claude Code will be able to search your GitHub repos,
# fetch web pages, query databases, and read your local files.
#
# Usage:
#   ./setup.sh              Interactive mode with workflow selection
#   ./setup.sh --all        Install every available server
#   ./setup.sh --minimal    Install only the essentials (GitHub, Fetch, Filesystem)
#   ./setup.sh --list       Show available servers and exit
#   ./setup.sh --restore    Restore the most recent settings backup
#   ./setup.sh --yes, -y    Skip confirmation prompts
#   ./setup.sh --help, -h   Show this help

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
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
NC='\033[0m'

# Progress indicators
CHECKMARK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${CYAN}▸${NC}"
WARN="${YELLOW}!${NC}"
INFO="${BLUE}i${NC}"
WORKING="${MAGENTA}○${NC}"
DOT="${DIM}·${NC}"
DIAMOND="${CYAN}◆${NC}"

info()    { echo -e "  ${CHECKMARK}  $1"; }
warn()    { echo -e "  ${WARN}  $1"; }
fail()    { echo -e "  ${CROSS}  $1"; }
step()    { echo -e "  ${ARROW}  $1"; }
note()    { echo -e "  ${INFO}  $1"; }
working() { echo -e "  ${WORKING}  $1"; }

divider() {
    echo -e "  ${DIM}$(printf '%.0s─' $(seq 1 62))${NC}"
}

header() {
    echo ""
    echo -e "  ${BOLD}${CYAN}$1${NC}"
    divider
}

phase_header() {
    local step_num="$1"
    local total="$2"
    local label="$3"
    echo ""
    echo -e "  ${BOLD}${WHITE}Step ${step_num} of ${total}${NC}  ${DIM}│${NC}  ${BOLD}${label}${NC}"
    divider
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
            echo ""
            echo -e "${BOLD}MCP Server Kit for Claude Code${NC}"
            echo ""
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
            echo ""
            echo "Examples:"
            echo "  ./setup.sh               # Walk through interactive setup"
            echo "  ./setup.sh --minimal -y  # Quick install of core servers, no prompts"
            echo "  ./setup.sh --restore     # Undo the last setup by restoring backup"
            echo ""
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
        echo ""
        fail "No backup directory found at $BACKUP_DIR"
        echo ""
        echo -e "  ${DIM}This means setup.sh has never been run, or backups were deleted.${NC}"
        echo -e "  ${DIM}Run ./setup.sh to create a fresh configuration.${NC}"
        echo ""
        exit 1
    fi

    local latest
    latest=$(ls -1t "$BACKUP_DIR"/settings.backup.*.json 2>/dev/null | head -1)

    if [[ -z "$latest" ]]; then
        echo ""
        fail "No backups found in $BACKUP_DIR"
        echo ""
        echo -e "  ${DIM}The backup directory exists but contains no backup files.${NC}"
        echo -e "  ${DIM}Run ./setup.sh to create a fresh configuration.${NC}"
        echo ""
        exit 1
    fi

    echo ""
    echo -e "  ${BOLD}Available backups (most recent first):${NC}"
    echo ""
    ls -1t "$BACKUP_DIR"/settings.backup.*.json 2>/dev/null | head -5 | while read -r f; do
        local ts
        ts=$(basename "$f" | sed 's/settings.backup.\(.*\).json/\1/')
        echo -e "    ${DOT}  $(basename "$f")  ${DIM}($(date -r "$f" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ts"))${NC}"
    done
    echo ""

    cp "$latest" "$SETTINGS_FILE"
    info "Restored settings from $(basename "$latest")"
    echo ""
    echo -e "  ${DIM}Restart Claude Code to pick up the restored settings.${NC}"
    echo ""
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
        info "Claude Code installed ${DIM}($version)${NC}"
    else
        fail "Claude Code is not installed"
        echo ""
        echo -e "    ${BOLD}To install:${NC}"
        echo "      npm install -g @anthropic-ai/claude-code"
        echo ""
        echo -e "    ${BOLD}Full guide:${NC}"
        echo "      https://docs.anthropic.com/en/docs/claude-code"
        echo ""
        preflight_passed=false
    fi
}

check_npx() {
    if command -v npx &> /dev/null; then
        info "npx available ${DIM}($(npx --version 2>/dev/null))${NC}"
    else
        fail "npx is not installed"
        echo ""
        echo -e "    ${BOLD}npx comes with Node.js. Install Node.js v18 or later:${NC}"
        echo ""
        echo "      macOS:       brew install node"
        echo "      Fedora/RHEL: dnf install nodejs"
        echo "      Ubuntu:      apt install nodejs npm"
        echo ""
        echo -e "    ${DIM}After installing, close and reopen your terminal, then try again.${NC}"
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
        info "JSON processing: python3 ${DIM}(install jq for faster runs)${NC}"
    elif command -v python &> /dev/null; then
        JSON_TOOL="python"
        info "JSON processing: python ${DIM}(install jq for faster runs)${NC}"
    else
        fail "Neither jq nor python3 is available"
        echo ""
        echo -e "    ${BOLD}Install jq (recommended):${NC}"
        echo ""
        echo "      macOS:       brew install jq"
        echo "      Fedora/RHEL: dnf install jq"
        echo "      Ubuntu:      apt install jq"
        echo ""
        echo -e "    ${DIM}Alternatively, install Python 3 and the script will use that instead.${NC}"
        echo ""
        preflight_passed=false
    fi
}

detect_environment() {
    phase_header "$CURRENT_STEP" "$TOTAL_STEPS" "Detecting your environment"
    CURRENT_STEP=$((CURRENT_STEP + 1))

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
    echo -e "  ${BOLD}Available MCP Servers${NC}"
    divider

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
            echo -e "    ${BOLD}${cat_label}${NC}"
        fi

        local env_note=""
        if [[ -n "${SERVER_ENV[$key]}" ]]; then
            env_note=" ${DIM}(requires API key)${NC}"
        fi
        echo -e "      ${DIAMOND} ${GREEN}${SERVER_NAMES[$key]}${NC}  ${SERVER_DESCS[$key]}${env_note}"
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
        info "Settings backed up to ${DIM}$BACKUP_FILE${NC}"
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
    local server_num="$2"
    local server_total="$3"
    local package="${SERVER_PACKAGES[$key]}"
    local extra_args="${SERVER_ARGS[$key]}"
    local env_vars="${SERVER_ENV[$key]}"

    # Check if already configured
    local already_exists=false
    for existing in "${EXISTING_SERVERS[@]}"; do
        if [[ "$existing" == "$key" ]]; then
            already_exists=true
            break
        fi
    done

    local action_verb="Adding"
    if $already_exists; then
        action_verb="Updating"
    fi

    # Write the config
    merge_mcp_server "$key" "$package" "$extra_args" "$env_vars"

    # Validate: check that the npm package exists and get its version
    local pkg_version
    pkg_version=$(npm view "$package" version 2>/dev/null || echo "")

    if [[ -n "$pkg_version" ]]; then
        info "${action_verb} ${SERVER_NAMES[$key]}... done ${DIM}(${package}@${pkg_version})${NC}"
        return 0
    else
        warn "${action_verb} ${SERVER_NAMES[$key]}... wrote config, but npm verify failed"
        echo -e "     ${DIM}Check connectivity: npm view ${package} version${NC}"
        return 0
    fi
}

# -------------------------------------------------------------------
# Workflow-based interactive selection
# -------------------------------------------------------------------

interactive_select() {
    phase_header "$CURRENT_STEP" "$TOTAL_STEPS" "Choose your setup"
    CURRENT_STEP=$((CURRENT_STEP + 1))

    echo ""
    echo -e "  Pick a bundle that matches your workflow, or build your own."
    echo ""
    echo -e "    ${BOLD}1)${NC}  ${GREEN}Quick Start${NC}"
    echo -e "        ${DIM}GitHub, Fetch, Filesystem, Memory${NC}"
    echo -e "        ${DIM}The essentials for most developers.${NC}"
    echo ""
    echo -e "    ${BOLD}2)${NC}  ${GREEN}Full Stack Developer${NC}"
    echo -e "        ${DIM}Core + Brave Search, Context7, Sequential Thinking, Puppeteer${NC}"
    echo -e "        ${DIM}Web search, docs lookup, browser testing, and structured reasoning.${NC}"
    echo ""
    echo -e "    ${BOLD}3)${NC}  ${GREEN}Data and Backend${NC}"
    echo -e "        ${DIM}Core + Postgres, SQLite, Sequential Thinking${NC}"
    echo -e "        ${DIM}Query databases and reason through complex data problems.${NC}"
    echo ""
    echo -e "    ${BOLD}4)${NC}  ${GREEN}AI/ML Engineer${NC}"
    echo -e "        ${DIM}Core + Brave Search, Context7, Sequential Thinking, EverArt${NC}"
    echo -e "        ${DIM}Research papers, latest docs, image generation, deep reasoning.${NC}"
    echo ""
    echo -e "    ${BOLD}5)${NC}  ${GREEN}Everything${NC}"
    echo -e "        ${DIM}Install all ${#ALL_SERVER_KEYS[@]} available servers${NC}"
    echo ""
    echo -e "    ${BOLD}6)${NC}  ${GREEN}Custom${NC}"
    echo -e "        ${DIM}Pick exactly which servers you want from the full list${NC}"
    echo ""

    local choice
    read -rp "  Choose a setup (1-6): " choice

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
    echo -e "  ${BOLD}Available servers:${NC}"
    echo ""

    local i=1
    for key in "${ALL_SERVER_KEYS[@]}"; do
        local env_note=""
        if [[ -n "${SERVER_ENV[$key]}" ]]; then
            env_note=" ${DIM}(API key required)${NC}"
        fi
        printf "    ${BOLD}%2d)${NC}  %-22s %s%b\n" "$i" "${SERVER_NAMES[$key]}" "${SERVER_DESCS[$key]}" "$env_note"
        i=$((i + 1))
    done

    echo ""
    echo -e "  Enter the numbers of servers to install, separated by spaces."
    echo -e "  ${DIM}Example: 1 2 3 5 8${NC}"
    echo ""
    read -rp "  Your selections: " choices

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
        note "Based on what's installed on your machine, you might also want:"
        for s in "${suggestions[@]}"; do
            echo -e "       ${GREEN}+${NC} ${SERVER_NAMES[$s]}  ${DIM}${SERVER_DESCS[$s]}${NC}"
        done
        echo ""
        read -rp "  Add these servers too? (Y/n): " add_suggested
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
        echo -e "  ${BOLD}Filesystem server: which directory should Claude Code access?${NC}"
        echo -e "  ${DIM}This gives Claude Code read/write access to files in this folder.${NC}"
        echo -e "  ${DIM}Default: $HOME/projects${NC}"
        echo ""
        read -rp "  Path (press Enter for default): " fs_path

        if [[ -n "$fs_path" ]]; then
            # Expand ~ if used
            fs_path="${fs_path/#\~/$HOME}"
            if [[ -d "$fs_path" ]]; then
                SERVER_ARGS[filesystem]="$fs_path"
                info "Filesystem path set to: $fs_path"
            else
                warn "Directory $fs_path does not exist. Using default ($HOME/projects)."
                echo -e "     ${DIM}You can change this later in ~/.claude/settings.json${NC}"
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
        echo -e "  ${BOLD}PostgreSQL: enter your connection string${NC}"
        echo -e "  ${DIM}Format: postgresql://user:password@host:port/database${NC}"
        echo -e "  ${DIM}Default: postgresql://localhost:5432/mydb${NC}"
        echo ""
        echo -e "  ${DIM}Tip: if you're using a local Postgres with default settings,${NC}"
        echo -e "  ${DIM}just press Enter and update the database name later.${NC}"
        echo ""
        read -rp "  Connection string (press Enter for default): " pg_conn

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
        echo -e "  ${BOLD}SQLite: enter the path to your database file${NC}"
        echo -e "  ${DIM}Default: $HOME/data/my-database.db${NC}"
        echo ""
        echo -e "  ${DIM}Tip: you can point this at any .db or .sqlite file.${NC}"
        echo -e "  ${DIM}If the file doesn't exist yet, Claude Code will create it.${NC}"
        echo ""
        read -rp "  Database path (press Enter for default): " sqlite_path

        if [[ -n "$sqlite_path" ]]; then
            sqlite_path="${sqlite_path/#\~/$HOME}"
            SERVER_ARGS[sqlite]="$sqlite_path"
            info "SQLite path set to: $sqlite_path"
        fi
    fi
}

# -------------------------------------------------------------------
# API key prompts (with detailed guidance)
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
        phase_header "$CURRENT_STEP" "$TOTAL_STEPS" "API Keys"
        CURRENT_STEP=$((CURRENT_STEP + 1))

        echo ""
        echo -e "  Some of the servers you selected need API keys to work."
        echo -e "  You can enter them now or add them later to ~/.claude/settings.json."
        echo -e "  ${DIM}Press Enter on any prompt to skip it for now.${NC}"

        for key_server in "${keys_needed[@]}"; do
            echo ""
            divider
            case "$key_server" in
                brave-search)
                    echo ""
                    echo -e "  ${BOLD}Brave Search API Key${NC}"
                    echo ""
                    echo -e "  ${UNDERLINE}What this does:${NC} Claude Code can search the web in real time"
                    echo -e "  to find current docs, tutorials, Stack Overflow answers, and more."
                    echo ""
                    echo -e "  ${UNDERLINE}Where to get it:${NC}"
                    echo -e "    ${CYAN}https://brave.com/search/api/${NC}"
                    echo -e "    Sign up, then copy your API key from the dashboard."
                    echo -e "    ${DIM}The free tier gives you 2,000 searches per month.${NC}"
                    echo ""
                    read -rp "  BRAVE_API_KEY: " input_key
                    if [[ -n "$input_key" ]]; then
                        export BRAVE_API_KEY="$input_key"
                        info "Brave Search API key saved"
                    else
                        note "Skipped (you can add it later)"
                    fi
                    ;;
                google-maps)
                    echo ""
                    echo -e "  ${BOLD}Google Maps API Key${NC}"
                    echo ""
                    echo -e "  ${UNDERLINE}What this does:${NC} Claude Code can look up addresses, get"
                    echo -e "  directions, find nearby places, and calculate distances."
                    echo ""
                    echo -e "  ${UNDERLINE}Where to get it:${NC}"
                    echo -e "    ${CYAN}https://console.cloud.google.com/apis/credentials${NC}"
                    echo -e "    Create a project, enable the Maps JavaScript API,"
                    echo -e "    then generate an API key under Credentials."
                    echo -e "    ${DIM}Google gives you \$200/month in free Maps API usage.${NC}"
                    echo ""
                    read -rp "  GOOGLE_MAPS_API_KEY: " input_key
                    if [[ -n "$input_key" ]]; then
                        export GOOGLE_MAPS_API_KEY="$input_key"
                        info "Google Maps API key saved"
                    else
                        note "Skipped (you can add it later)"
                    fi
                    ;;
                slack)
                    echo ""
                    echo -e "  ${BOLD}Slack Bot Token${NC}"
                    echo ""
                    echo -e "  ${UNDERLINE}What this does:${NC} Claude Code can read and post messages"
                    echo -e "  in your Slack workspace channels."
                    echo ""
                    echo -e "  ${UNDERLINE}Where to get it:${NC}"
                    echo -e "    ${CYAN}https://api.slack.com/apps${NC}"
                    echo -e "    Create a new app, add Bot Token Scopes (channels:read,"
                    echo -e "    chat:write), install to your workspace, then copy the"
                    echo -e "    Bot User OAuth Token (starts with xoxb-)."
                    echo ""
                    read -rp "  SLACK_BOT_TOKEN: " input_key
                    if [[ -n "$input_key" ]]; then
                        export SLACK_BOT_TOKEN="$input_key"
                        info "Slack bot token saved"
                    else
                        note "Skipped (you can add it later)"
                    fi
                    echo ""
                    echo -e "  ${DIM}Your Team ID is in your Slack workspace URL or under${NC}"
                    echo -e "  ${DIM}Settings > About This Workspace.${NC}"
                    echo ""
                    read -rp "  SLACK_TEAM_ID: " input_key2
                    if [[ -n "$input_key2" ]]; then
                        export SLACK_TEAM_ID="$input_key2"
                        info "Slack team ID saved"
                    else
                        note "Skipped (you can add it later)"
                    fi
                    ;;
                everart)
                    echo ""
                    echo -e "  ${BOLD}EverArt API Key${NC}"
                    echo ""
                    echo -e "  ${UNDERLINE}What this does:${NC} Claude Code can generate images"
                    echo -e "  and train custom AI art models on your behalf."
                    echo ""
                    echo -e "  ${UNDERLINE}Where to get it:${NC}"
                    echo -e "    Check the EverArt documentation or your account dashboard"
                    echo -e "    for API access details."
                    echo ""
                    read -rp "  EVERART_API_KEY: " input_key
                    if [[ -n "$input_key" ]]; then
                        export EVERART_API_KEY="$input_key"
                        info "EverArt API key saved"
                    else
                        note "Skipped (you can add it later)"
                    fi
                    ;;
            esac
        done
    fi
}

# -------------------------------------------------------------------
# GitHub token prompt
# -------------------------------------------------------------------

prompt_github_token() {
    if [[ "${SERVER_SELECTED[github]}" == "true" ]] && [[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]] && ! $NONINTERACTIVE; then
        echo ""
        divider
        echo ""
        echo -e "  ${BOLD}GitHub Personal Access Token${NC} ${DIM}(optional but recommended)${NC}"
        echo ""
        echo -e "  ${UNDERLINE}What this does:${NC} Access to your private repos, higher rate limits"
        echo -e "  (5,000 requests/hour instead of 60), and the ability to create"
        echo -e "  issues and pull requests."
        echo ""
        echo -e "  ${UNDERLINE}Where to get it:${NC}"
        echo -e "    ${CYAN}https://github.com/settings/tokens/new${NC}"
        echo -e "    Select the ${BOLD}repo${NC} scope for private repo access."
        echo -e "    ${DIM}Without a token, you can still use public repos but will${NC}"
        echo -e "    ${DIM}hit rate limits after 60 requests per hour.${NC}"
        echo ""
        read -rp "  GITHUB_PERSONAL_ACCESS_TOKEN (press Enter to skip): " gh_token
        if [[ -n "$gh_token" ]]; then
            export GITHUB_PERSONAL_ACCESS_TOKEN="$gh_token"
            info "GitHub token saved"

            # Inject the env var into the github server config
            if [[ -z "${SERVER_ENV[github]}" ]]; then
                SERVER_ENV[github]="GITHUB_PERSONAL_ACCESS_TOKEN"
            fi
        else
            note "Skipped (public repos will still work)"
        fi
    fi
}

# -------------------------------------------------------------------
# Rollback on failure
# -------------------------------------------------------------------

rollback() {
    echo ""
    fail "Setup failed. See error above."
    echo ""
    if [[ -f "$BACKUP_FILE" ]]; then
        cp "$BACKUP_FILE" "$SETTINGS_FILE"
        info "Rolled back settings to pre-setup state"
    else
        echo -e "  ${DIM}No backup exists. Settings are unchanged.${NC}"
    fi
    echo ""
    echo -e "  ${BOLD}Next:${NC}"
    echo -e "    1. Read the error above"
    echo -e "    2. Check internet: curl -s https://registry.npmjs.org/ | head -1"
    echo -e "    3. Retry: ./setup.sh"
    echo ""
    exit 1
}

# -------------------------------------------------------------------
# Post-install health dashboard
# -------------------------------------------------------------------

show_health_dashboard() {
    local installed=("$@")

    echo ""
    echo ""
    echo -e "  ${BOLD}${GREEN}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}${GREEN}│                                                          │${NC}"
    echo -e "  ${BOLD}${GREEN}│     Done. ${#installed[@]} server(s) configured in settings.json.      │${NC}"
    echo -e "  ${BOLD}${GREEN}│                                                          │${NC}"
    echo -e "  ${BOLD}${GREEN}└──────────────────────────────────────────────────────────┘${NC}"

    # Health check table
    echo ""
    echo -e "  ${BOLD}Server Health${NC}"
    divider
    echo ""

    local all_healthy=true
    for key in "${installed[@]}"; do
        local status_icon="${CHECKMARK}"
        local status_text="${GREEN}ready${NC}"
        local env="${SERVER_ENV[$key]}"

        # Check if API keys are still placeholders
        if [[ -n "$env" ]]; then
            IFS=',' read -ra vars <<< "$env"
            for var in "${vars[@]}"; do
                local val="${!var:-}"
                if [[ -z "$val" || "$val" == *"<your-"* ]]; then
                    status_icon="${WARN}"
                    status_text="${YELLOW}needs API key${NC}"
                    all_healthy=false
                    break
                fi
            done
        fi

        printf "    %b  %-24s %b\n" "$status_icon" "${SERVER_NAMES[$key]}" "$status_text"
    done

    echo ""

    # Action items for missing API keys
    local needs_keys=false
    for key in "${installed[@]}"; do
        local env="${SERVER_ENV[$key]}"
        if [[ -n "$env" ]]; then
            IFS=',' read -ra vars <<< "$env"
            for var in "${vars[@]}"; do
                local val="${!var:-}"
                if [[ -z "$val" || "$val" == *"<your-"* ]]; then
                    if ! $needs_keys; then
                        echo -e "  ${BOLD}${YELLOW}Action needed: add API keys${NC}"
                        divider
                        echo ""
                        needs_keys=true
                    fi
                    case "$var" in
                        BRAVE_API_KEY)
                            echo -e "    ${WARN}  BRAVE_API_KEY"
                            echo -e "       Get one at: ${CYAN}https://brave.com/search/api/${NC}"
                            echo -e "       ${DIM}Free tier: 2,000 searches/month${NC}"
                            ;;
                        GOOGLE_MAPS_API_KEY)
                            echo -e "    ${WARN}  GOOGLE_MAPS_API_KEY"
                            echo -e "       Get one at: ${CYAN}https://console.cloud.google.com/apis/credentials${NC}"
                            echo -e "       ${DIM}Free tier: \$200/month in usage${NC}"
                            ;;
                        SLACK_BOT_TOKEN)
                            echo -e "    ${WARN}  SLACK_BOT_TOKEN"
                            echo -e "       Get one at: ${CYAN}https://api.slack.com/apps${NC}"
                            ;;
                        SLACK_TEAM_ID)
                            echo -e "    ${WARN}  SLACK_TEAM_ID"
                            echo -e "       ${DIM}Found in Slack workspace settings${NC}"
                            ;;
                        EVERART_API_KEY)
                            echo -e "    ${WARN}  EVERART_API_KEY"
                            echo -e "       ${DIM}Check your EverArt account dashboard${NC}"
                            ;;
                        GITHUB_PERSONAL_ACCESS_TOKEN)
                            echo -e "    ${WARN}  GITHUB_PERSONAL_ACCESS_TOKEN"
                            echo -e "       Get one at: ${CYAN}https://github.com/settings/tokens/new${NC}"
                            echo -e "       ${DIM}Select the 'repo' scope for private repos${NC}"
                            ;;
                    esac
                    echo ""
                fi
            done
        fi
    done
    if $needs_keys; then
        echo -e "  ${DIM}Add keys to ~/.claude/settings.json in each server's \"env\" block,${NC}"
        echo -e "  ${DIM}or export them as environment variables before starting Claude Code.${NC}"
        echo ""
    fi

    # What to try first
    echo -e "  ${BOLD}Try these in Claude Code${NC}"
    divider
    echo ""

    if [[ " ${installed[*]} " == *" github "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"List the open issues in my-org/my-repo\"${NC}"
    fi
    if [[ " ${installed[*]} " == *" fetch "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"Fetch https://httpbin.org/get and show me the response\"${NC}"
    fi
    if [[ " ${installed[*]} " == *" brave-search "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"Search the web for 'best practices for Python logging'\"${NC}"
    fi
    if [[ " ${installed[*]} " == *" memory "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"Remember that my preferred language is Python\"${NC}"
    fi
    if [[ " ${installed[*]} " == *" context7 "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"Use context7 to get the latest docs for FastAPI\"${NC}"
    fi
    if [[ " ${installed[*]} " == *" filesystem "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"List the files in my projects directory\"${NC}"
    fi
    if [[ " ${installed[*]} " == *" sequential-thinking "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"Think step by step about how to design a REST API for a todo app\"${NC}"
    fi
    if [[ " ${installed[*]} " == *" puppeteer "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"Take a screenshot of https://example.com\"${NC}"
    fi
    if [[ " ${installed[*]} " == *" postgres "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"Show me the tables in my PostgreSQL database\"${NC}"
    fi
    if [[ " ${installed[*]} " == *" sqlite "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"Show me the schema of my SQLite database\"${NC}"
    fi
    if [[ " ${installed[*]} " == *" slack "* ]]; then
        echo -e "    ${DIAMOND}  ${WHITE}\"List the recent messages in #general on Slack\"${NC}"
    fi

    echo ""

    # Verification and file locations
    echo -e "  ${BOLD}Verify${NC}"
    divider
    echo ""
    if [[ -f "$SCRIPT_DIR/verify.sh" ]]; then
        echo -e "    ${CYAN}./verify.sh${NC}    # full diagnostic"
    else
        echo -e "    Restart Claude Code to load the new servers."
    fi
    echo ""
    echo -e "  ${DIM}Settings file: $SETTINGS_FILE${NC}"
    echo -e "  ${DIM}Backup file:   $BACKUP_FILE${NC}"
    echo -e "  ${DIM}To undo:       ./setup.sh --restore${NC}"
    echo ""
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

main() {
    # Banner
    echo ""
    echo ""
    echo -e "  ${BOLD}${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}${CYAN}│                                                          │${NC}"
    echo -e "  ${BOLD}${CYAN}│           MCP Server Kit for Claude Code                 │${NC}"
    echo -e "  ${BOLD}${CYAN}│                                                          │${NC}"
    echo -e "  ${BOLD}${CYAN}│     Configure MCP servers for Claude Code.                │${NC}"
    echo -e "  ${BOLD}${CYAN}│                                                          │${NC}"
    echo -e "  ${BOLD}${CYAN}└──────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  This adds GitHub, web fetch, filesystem, database, and search"
    echo -e "  capabilities to Claude Code via MCP servers."
    echo ""

    # Calculate total steps based on mode
    TOTAL_STEPS=5
    CURRENT_STEP=1

    # Step 1: Preflight
    phase_header "$CURRENT_STEP" "$TOTAL_STEPS" "Checking prerequisites"
    CURRENT_STEP=$((CURRENT_STEP + 1))

    check_claude_code
    check_npx
    check_json_tool

    if ! $preflight_passed; then
        echo ""
        fail "Missing prerequisites. Fix the items marked ${CROSS} above and re-run ./setup.sh."
        echo ""
        exit 1
    fi

    # Ensure settings directory and file exist
    mkdir -p "$SETTINGS_DIR"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
        info "Created new settings file at ${DIM}$SETTINGS_FILE${NC}"
    fi

    # Step 2: Detect environment and existing config
    detect_environment
    check_existing_servers

    # Initialize server registry
    init_server_registry

    # Step 3: Determine what to install
    if $INSTALL_ALL; then
        for key in "${ALL_SERVER_KEYS[@]}"; do
            SERVER_SELECTED[$key]=true
        done
        phase_header "$CURRENT_STEP" "$TOTAL_STEPS" "Server selection"
        CURRENT_STEP=$((CURRENT_STEP + 1))
        note "Installing all ${#ALL_SERVER_KEYS[@]} servers (--all flag)"
    elif $INSTALL_MINIMAL; then
        for key in github fetch filesystem; do
            SERVER_SELECTED[$key]=true
        done
        phase_header "$CURRENT_STEP" "$TOTAL_STEPS" "Server selection"
        CURRENT_STEP=$((CURRENT_STEP + 1))
        note "Installing minimal set (--minimal flag): GitHub, Fetch, Filesystem"
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
        warn "No servers selected."
        echo ""
        echo -e "  ${DIM}Try: ./setup.sh --minimal${NC}"
        echo ""
        exit 0
    fi

    # Prompt for paths, connection strings, and API keys
    prompt_filesystem_path
    prompt_postgres_connection
    prompt_sqlite_path

    # Step 4 (conditional): API keys
    prompt_github_token
    prompt_api_keys

    # Confirmation
    if ! $NONINTERACTIVE; then
        echo ""
        divider
        echo ""
        echo -e "  ${BOLD}Ready to install ${selected_count} server(s):${NC}"
        echo ""
        for key in "${ALL_SERVER_KEYS[@]}"; do
            if [[ "${SERVER_SELECTED[$key]}" == "true" ]]; then
                echo -e "    ${GREEN}+${NC}  ${SERVER_NAMES[$key]}"
            fi
        done
        echo ""
        read -rp "  Proceed? (Y/n): " confirm
        if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
            echo ""
            echo "  Cancelled. No changes were made."
            echo ""
            exit 0
        fi
    fi

    # Backup before making changes
    backup_settings

    # Set trap for rollback on failure
    trap rollback ERR

    # Step 5: Install
    phase_header "$CURRENT_STEP" "$TOTAL_STEPS" "Installing and verifying servers"
    CURRENT_STEP=$((CURRENT_STEP + 1))

    local installed=()
    local install_failed=false
    local server_num=0

    for key in "${ALL_SERVER_KEYS[@]}"; do
        if [[ "${SERVER_SELECTED[$key]}" == "true" ]]; then
            server_num=$((server_num + 1))
            if install_single_server "$key" "$server_num" "$selected_count"; then
                installed+=("$key")
            else
                fail "${SERVER_NAMES[$key]} config written, but package verify failed"
                echo -e "     ${DIM}Check: npm view ${SERVER_PACKAGES[$key]} version${NC}"
                install_failed=true
            fi
        fi
    done

    # Remove trap after successful install
    trap - ERR

    if $install_failed; then
        echo ""
        warn "Some package verifications failed. Configs were still written."
        echo -e "     ${DIM}They may work once npm registry is reachable. Run ./verify.sh to recheck.${NC}"
    fi

    if [[ ${#installed[@]} -eq 0 ]]; then
        echo ""
        fail "No servers installed. Check internet and npm:"
        echo ""
        echo -e "    npm view @anthropic-ai/mcp-fetch version"
        echo -e "    ./setup.sh"
        echo ""
        exit 1
    fi

    show_health_dashboard "${installed[@]}"
}

main "$@"
