#!/usr/bin/env bash
#
# setup.sh - Install and configure MCP servers for Claude Code
#
# This script adds MCP servers to your Claude Code settings.
# It is safe to run multiple times (idempotent).
#
# Usage:
#   ./setup.sh          Interactive mode: choose which servers to install
#   ./setup.sh --all    Non-interactive: install all servers

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
SETTINGS_DIR="$HOME/.claude"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d%H%M%S)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[SKIP]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
success() { echo -e "${GREEN}[DONE]${NC} $1"; }

# Parse flags
INSTALL_ALL=false
for arg in "$@"; do
    case "$arg" in
        --all) INSTALL_ALL=true ;;
        --help|-h)
            echo "Usage: ./setup.sh [--all]"
            echo ""
            echo "  --all    Install all MCP servers without prompting"
            echo "  (none)   Interactive mode: choose which servers to install"
            exit 0
            ;;
        *) echo "Unknown flag: $arg. Use --help for usage."; exit 1 ;;
    esac
done

# -------------------------------------------------------------------
# Preflight checks
# -------------------------------------------------------------------

check_claude_code() {
    if command -v claude &> /dev/null; then
        info "Claude Code is installed: $(claude --version 2>/dev/null || echo 'version unknown')"
    else
        echo ""
        echo -e "${RED}Claude Code is not installed.${NC}"
        echo ""
        echo "Install it first:"
        echo "  npm install -g @anthropic-ai/claude-code"
        echo ""
        echo "Or see: https://docs.anthropic.com/en/docs/claude-code"
        exit 1
    fi
}

check_npx() {
    if command -v npx &> /dev/null; then
        info "npx is available: $(npx --version 2>/dev/null)"
    else
        echo ""
        echo -e "${RED}npx is not installed.${NC}"
        echo ""
        echo "Install Node.js v18+ to get npx:"
        echo "  macOS:       brew install node"
        echo "  Fedora/RHEL: dnf install nodejs"
        echo "  Ubuntu:      apt install nodejs npm"
        echo ""
        exit 1
    fi
}

check_jq_or_python() {
    if command -v jq &> /dev/null; then
        JSON_TOOL="jq"
        info "Using jq for JSON processing"
    elif command -v python3 &> /dev/null; then
        JSON_TOOL="python3"
        info "Using python3 for JSON processing (install jq for faster runs)"
    elif command -v python &> /dev/null; then
        JSON_TOOL="python"
        info "Using python for JSON processing (install jq for faster runs)"
    else
        echo ""
        echo -e "${RED}Neither jq nor python3 is available.${NC}"
        echo ""
        echo "Install one of them:"
        echo "  macOS:       brew install jq"
        echo "  Fedora/RHEL: dnf install jq"
        echo "  Ubuntu:      apt install jq"
        echo ""
        exit 1
    fi
}

# -------------------------------------------------------------------
# Backup existing settings
# -------------------------------------------------------------------

backup_settings() {
    if [[ -f "$SETTINGS_FILE" ]]; then
        cp "$SETTINGS_FILE" "${SETTINGS_FILE}${BACKUP_SUFFIX}"
        info "Backed up settings to ${SETTINGS_FILE}${BACKUP_SUFFIX}"
    fi
}

# -------------------------------------------------------------------
# JSON merge logic
# -------------------------------------------------------------------

merge_mcp_config() {
    local name="$1"
    local command="$2"
    shift 2
    local args=("$@")

    # Build the args JSON array
    local args_json="["
    local first=true
    for arg in "${args[@]}"; do
        if $first; then
            first=false
        else
            args_json+=","
        fi
        args_json+="\"$arg\""
    done
    args_json+="]"

    local new_server
    new_server=$(cat <<SERVEREOF
{"command":"$command","args":$args_json}
SERVEREOF
)

    if [[ "$JSON_TOOL" == "jq" ]]; then
        local tmp
        tmp=$(mktemp)
        jq --arg name "$name" --argjson server "$new_server" '
            .mcpServers //= {} |
            .mcpServers[$name] = $server
        ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    else
        $JSON_TOOL - "$SETTINGS_FILE" "$name" "$new_server" <<'PYEOF'
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
# Server definitions
# -------------------------------------------------------------------

# Each server: KEY|DESCRIPTION|INSTALL_FUNCTION
declare -a SERVER_KEYS=()
declare -A SERVER_DESCS=()
declare -A SERVER_SELECTED=()

define_servers() {
    SERVER_KEYS=("github" "fetch" "filesystem" "brave-search" "memory")

    SERVER_DESCS=(
        ["github"]="GitHub - query repos, issues, PRs, and file contents"
        ["fetch"]="Fetch - read the contents of any URL"
        ["filesystem"]="Filesystem - controlled access to local directories"
        ["brave-search"]="Brave Search - web search via Brave Search API"
        ["memory"]="Memory - persistent key-value storage across sessions"
    )

    # Default: all selected
    for key in "${SERVER_KEYS[@]}"; do
        SERVER_SELECTED[$key]=true
    done
}

install_server() {
    local key="$1"
    case "$key" in
        github)
            info "Configuring GitHub MCP server..."
            merge_mcp_config "github" "npx" "-y" "@modelcontextprotocol/server-github"
            ;;
        fetch)
            info "Configuring Fetch MCP server..."
            merge_mcp_config "fetch" "npx" "-y" "@anthropic-ai/mcp-fetch"
            ;;
        filesystem)
            info "Configuring Filesystem MCP server..."
            merge_mcp_config "filesystem" "npx" "-y" "@modelcontextprotocol/server-filesystem" "$HOME/projects"
            ;;
        brave-search)
            info "Configuring Brave Search MCP server..."
            merge_mcp_config "brave-search" "npx" "-y" "@anthropic-ai/mcp-server-brave-search"
            ;;
        memory)
            info "Configuring Memory MCP server..."
            merge_mcp_config "memory" "npx" "-y" "@modelcontextprotocol/server-memory"
            ;;
    esac
}

# -------------------------------------------------------------------
# Interactive selection
# -------------------------------------------------------------------

interactive_select() {
    echo ""
    echo "Available MCP servers:"
    echo ""

    local i=1
    for key in "${SERVER_KEYS[@]}"; do
        echo "  $i) ${SERVER_DESCS[$key]}"
        i=$((i + 1))
    done

    echo ""
    echo "Enter the numbers of servers to install (e.g., 1 2 3), or press Enter for all:"
    read -r choices

    if [[ -z "$choices" ]]; then
        # Default: install all
        return
    fi

    # Deselect all, then select chosen ones
    for key in "${SERVER_KEYS[@]}"; do
        SERVER_SELECTED[$key]=false
    done

    for choice in $choices; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#SERVER_KEYS[@]} )); then
            local idx=$((choice - 1))
            SERVER_SELECTED[${SERVER_KEYS[$idx]}]=true
        else
            echo -e "${YELLOW}[WARN]${NC} Ignoring invalid selection: $choice"
        fi
    done
}

# -------------------------------------------------------------------
# Post-install summary
# -------------------------------------------------------------------

show_summary() {
    local installed=("$@")

    echo ""
    echo -e "${BOLD}=====================================${NC}"
    echo -e "${GREEN}${BOLD}  Setup Complete${NC}"
    echo -e "${BOLD}=====================================${NC}"
    echo ""
    echo -e "${BOLD}Installed servers:${NC}"
    for key in "${installed[@]}"; do
        echo -e "  ${GREEN}+${NC} ${SERVER_DESCS[$key]}"
    done

    echo ""
    echo -e "${BOLD}Verify your setup:${NC}"
    echo "  cat ~/.claude/settings.json"
    echo "  ./verify.sh"
    echo ""
    echo -e "${BOLD}Try these prompts in Claude Code:${NC}"
    echo ""

    for key in "${installed[@]}"; do
        case "$key" in
            github)
                echo "  GitHub:       \"List the open issues in MarkellR-RedHat/ai-bu-mcp-server-kit\""
                ;;
            fetch)
                echo "  Fetch:        \"Fetch https://httpbin.org/get and show me the response\""
                ;;
            filesystem)
                echo "  Filesystem:   \"List the files in my projects directory\""
                ;;
            brave-search)
                echo "  Brave Search: \"Search the web for 'MCP servers for Claude Code'\""
                ;;
            memory)
                echo "  Memory:       \"Remember that my preferred language is Python\""
                ;;
        esac
    done

    echo ""

    # Remind about tokens/keys if relevant servers were installed
    local needs_note=false
    for key in "${installed[@]}"; do
        if [[ "$key" == "github" ]]; then
            echo -e "${YELLOW}Note:${NC} For private repos or higher rate limits, set GITHUB_PERSONAL_ACCESS_TOKEN"
            echo "      before launching Claude Code. See configs/github-mcp.json for details."
            needs_note=true
        fi
        if [[ "$key" == "brave-search" ]]; then
            echo -e "${YELLOW}Note:${NC} Brave Search requires a BRAVE_API_KEY. Get one at https://brave.com/search/api/"
            echo "      Then add it to the brave-search env block in ~/.claude/settings.json"
            needs_note=true
        fi
    done

    if $needs_note; then
        echo ""
    fi

    # Filesystem path reminder
    for key in "${installed[@]}"; do
        if [[ "$key" == "filesystem" ]]; then
            echo "To change the filesystem path, edit the 'filesystem' entry"
            echo "in ~/.claude/settings.json and replace ~/projects with"
            echo "the directory you want Claude Code to access."
            echo ""
            break
        fi
    done
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

main() {
    echo ""
    echo -e "${BOLD}======================================${NC}"
    echo -e "${BOLD}  MCP Server Kit for Claude Code${NC}"
    echo -e "${BOLD}======================================${NC}"
    echo ""

    check_claude_code
    check_npx
    check_jq_or_python

    # Make sure the settings directory and file exist
    mkdir -p "$SETTINGS_DIR"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
        info "Created new settings file at $SETTINGS_FILE"
    fi

    backup_settings

    define_servers

    if ! $INSTALL_ALL; then
        interactive_select
    fi

    # Install selected servers
    local installed=()
    for key in "${SERVER_KEYS[@]}"; do
        if [[ "${SERVER_SELECTED[$key]}" == "true" ]]; then
            install_server "$key"
            installed+=("$key")
        else
            warn "Skipped ${SERVER_DESCS[$key]}"
        fi
    done

    if [[ ${#installed[@]} -eq 0 ]]; then
        echo ""
        echo "No servers were selected. Nothing to do."
        exit 0
    fi

    show_summary "${installed[@]}"
}

main "$@"
