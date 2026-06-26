#!/usr/bin/env bash
#
# verify.sh - Diagnose MCP server configuration
#
# Checks each configured MCP server: package exists, API keys set,
# paths valid. Reports what's broken and how to fix it.
#
# Usage:
#   ./verify.sh          Full diagnostic with per-server checks and fix suggestions
#   ./verify.sh --quick  Package-existence checks only (faster, no npx probe)
#   ./verify.sh --json   Output results as JSON (backward-compatible format)
#   ./verify.sh --fix    Automatically fix simple problems (missing dirs, npx cache, etc.)

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"

# -------------------------------------------------------------------
# Colors
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

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${BLUE}[INFO]${NC}"

# -------------------------------------------------------------------
# Parse flags
# -------------------------------------------------------------------

QUICK_MODE=false
JSON_MODE=false
FIX_MODE=false

for arg in "$@"; do
    case "$arg" in
        --quick) QUICK_MODE=true ;;
        --json)  JSON_MODE=true ;;
        --fix)   FIX_MODE=true ;;
        --help|-h)
            echo "Usage: ./verify.sh [--quick] [--json] [--fix]"
            echo ""
            echo "  --quick   Package-existence checks only (skips startup probe)"
            echo "  --json    Output results as JSON"
            echo "  --fix     Automatically fix simple problems"
            exit 0
            ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

# -------------------------------------------------------------------
# JSON tool selection
# -------------------------------------------------------------------

if command -v jq &> /dev/null; then
    JSON_TOOL="jq"
elif command -v python3 &> /dev/null; then
    JSON_TOOL="python3"
elif command -v python &> /dev/null; then
    JSON_TOOL="python"
else
    echo -e "$FAIL Neither jq nor python3 is available."
    echo ""
    echo "  Install jq to continue:"
    echo "    macOS:       brew install jq"
    echo "    Fedora/RHEL: dnf install jq"
    echo "    Ubuntu:      apt install jq"
    exit 1
fi

# -------------------------------------------------------------------
# Auto-fix tracking
# -------------------------------------------------------------------

declare -a FIXES_APPLIED=()
declare -a FIXES_AVAILABLE=()

apply_fix() {
    local description="$1"
    local command="$2"

    if $FIX_MODE; then
        if eval "$command" &>/dev/null 2>&1; then
            FIXES_APPLIED+=("$description")
            if ! $JSON_MODE; then
                echo -e "       ${GREEN}[FIXED]${NC} $description"
            fi
            return 0
        else
            if ! $JSON_MODE; then
                echo -e "       ${RED}[COULD NOT FIX]${NC} $description"
            fi
            return 1
        fi
    else
        FIXES_AVAILABLE+=("$description: $command")
        return 1
    fi
}

# -------------------------------------------------------------------
# Preflight checks
# -------------------------------------------------------------------

preflight_issues=()
preflight_fixes=()

check_preflight() {
    # 1. Claude Code installation
    if command -v claude &>/dev/null; then
        local claude_version
        claude_version=$(claude --version 2>/dev/null || echo "unknown")
        if ! $JSON_MODE; then
            echo -e "  $PASS Claude Code is installed ($claude_version)"
        fi
    else
        preflight_issues+=("Claude Code is not installed.")
        preflight_fixes+=("npm install -g @anthropic-ai/claude-code")
        if ! $JSON_MODE; then
            echo -e "  $FAIL Claude Code is not installed"
            echo -e "       ${BOLD}Fix:${NC} npm install -g @anthropic-ai/claude-code"
            echo -e "       ${DIM}Guide: https://docs.anthropic.com/en/docs/claude-code${NC}"
        fi
    fi

    # 2. Settings file exists
    if [[ -f "$SETTINGS_FILE" ]]; then
        if ! $JSON_MODE; then
            echo -e "  $PASS Settings file exists at $SETTINGS_FILE"
        fi

        # 3. Settings file is valid JSON
        local parse_error=""
        if [[ "$JSON_TOOL" == "jq" ]]; then
            parse_error=$(jq '.' "$SETTINGS_FILE" 2>&1 >/dev/null || true)
        else
            parse_error=$($JSON_TOOL -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        json.load(f)
except json.JSONDecodeError as e:
    print(str(e))
" "$SETTINGS_FILE" 2>/dev/null || true)
        fi

        if [[ -n "$parse_error" ]]; then
            preflight_issues+=("Settings file has invalid JSON: $parse_error")
            preflight_fixes+=("jq . ~/.claude/settings.json  # shows the exact parse error")
            if ! $JSON_MODE; then
                echo -e "  $FAIL Settings file has invalid JSON"
                echo -e "       ${BOLD}Parse error:${NC} $parse_error"
                echo -e "       ${BOLD}Fix:${NC} Open ~/.claude/settings.json in an editor and correct the syntax."
                if ls "$HOME/.claude/backups"/settings.backup.*.json &>/dev/null 2>&1; then
                    local latest_backup
                    latest_backup=$(ls -1t "$HOME/.claude/backups"/settings.backup.*.json 2>/dev/null | head -1)
                    if [[ -n "$latest_backup" ]]; then
                        echo -e "       ${BOLD}Or restore from backup:${NC} cp $latest_backup ~/.claude/settings.json"
                    fi
                fi
            fi
        else
            if ! $JSON_MODE; then
                echo -e "  $PASS Settings file is valid JSON"
            fi
        fi
    else
        preflight_issues+=("No settings file found at $SETTINGS_FILE.")
        preflight_fixes+=("./setup.sh")
        if ! $JSON_MODE; then
            echo -e "  $FAIL No settings file found at $SETTINGS_FILE"
            echo -e "       ${BOLD}Fix:${NC} Run ./setup.sh to configure MCP servers"
        fi
    fi

    # 4. Node.js version check
    if command -v node &>/dev/null; then
        local node_full_version
        node_full_version=$(node --version 2>/dev/null || echo "unknown")
        local node_major
        node_major=$(echo "$node_full_version" | sed 's/v//' | cut -d. -f1)
        if [[ -n "$node_major" ]] && (( node_major >= 18 )); then
            if ! $JSON_MODE; then
                echo -e "  $PASS Node.js $node_full_version (v18+ required)"
            fi
        elif [[ -n "$node_major" ]]; then
            preflight_issues+=("Node.js $node_full_version is below the minimum v18. MCP servers may fail to start.")
            preflight_fixes+=("brew install node  # or visit https://nodejs.org/")
            if ! $JSON_MODE; then
                echo -e "  $FAIL Node.js $node_full_version is too old (v18+ required)"
                echo -e "       ${BOLD}Fix:${NC} Upgrade Node.js to v18 or later"
                echo -e "       macOS:       brew install node"
                echo -e "       Fedora/RHEL: dnf install nodejs"
                echo -e "       Ubuntu:      apt install nodejs npm"
                echo -e "       nvm:         nvm install 22"
            fi
        fi
    else
        preflight_issues+=("Node.js is not installed. MCP servers require Node.js v18+.")
        preflight_fixes+=("brew install node  # or visit https://nodejs.org/")
        if ! $JSON_MODE; then
            echo -e "  $FAIL Node.js is not installed"
            echo -e "       ${BOLD}Fix:${NC} Install Node.js v18+"
            echo -e "       macOS:       brew install node"
            echo -e "       Fedora/RHEL: dnf install nodejs"
            echo -e "       Ubuntu:      apt install nodejs npm"
        fi
    fi

    # 5. npx available
    if command -v npx &>/dev/null; then
        local npx_path
        npx_path=$(which npx 2>/dev/null || echo "unknown")
        if ! $JSON_MODE; then
            echo -e "  $PASS npx available at $npx_path"
        fi
    else
        preflight_issues+=("npx is not installed. Install Node.js v18+ to get npx.")
        preflight_fixes+=("brew install node")
        if ! $JSON_MODE; then
            echo -e "  $FAIL npx is not installed"
            echo -e "       ${BOLD}Fix:${NC} Install Node.js v18+ (npx is included)"
        fi
    fi

    # 6. Internet connectivity to npm registry
    if curl -s --max-time 5 https://registry.npmjs.org/ &>/dev/null; then
        if ! $JSON_MODE; then
            echo -e "  $PASS npm registry is reachable"
        fi
    else
        preflight_issues+=("Cannot reach the npm registry. First-run package downloads will fail.")
        preflight_fixes+=("curl -s https://registry.npmjs.org/  # test connectivity")
        if ! $JSON_MODE; then
            echo -e "  $WARN Cannot reach npm registry (https://registry.npmjs.org/)"
            echo -e "       ${BOLD}If behind a proxy:${NC}"
            echo -e "       npm config set proxy http://proxy.example.com:8080"
            echo -e "       npm config set https-proxy http://proxy.example.com:8080"
        fi
    fi
}

# -------------------------------------------------------------------
# Server extraction
# -------------------------------------------------------------------

get_server_names() {
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r '.mcpServers // {} | keys[]' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for k in data.get('mcpServers', {}):
    print(k)
" "$SETTINGS_FILE" 2>/dev/null
    fi
}

get_server_field() {
    local name="$1" field="$2"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r --arg n "$name" --arg f "$field" '.mcpServers[$n][$f] // empty' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
val = data.get('mcpServers', {}).get(sys.argv[2], {}).get(sys.argv[3], '')
if isinstance(val, list):
    print(' '.join(str(v) for v in val))
elif val:
    print(val)
" "$SETTINGS_FILE" "$name" "$field" 2>/dev/null
    fi
}

get_server_args() {
    local name="$1"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r --arg n "$name" '.mcpServers[$n].args[]' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for a in data.get('mcpServers', {}).get(sys.argv[2], {}).get('args', []):
    print(a)
" "$SETTINGS_FILE" "$name" 2>/dev/null
    fi
}

get_server_env_keys() {
    local name="$1"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r --arg n "$name" '.mcpServers[$n].env // {} | keys[]' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
env = data.get('mcpServers', {}).get(sys.argv[2], {}).get('env', {})
for k in env:
    print(k)
" "$SETTINGS_FILE" "$name" 2>/dev/null
    fi
}

get_server_env_value() {
    local name="$1" var="$2"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r --arg n "$name" --arg v "$var" '.mcpServers[$n].env[$v] // empty' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
val = data.get('mcpServers', {}).get(sys.argv[2], {}).get('env', {}).get(sys.argv[3], '')
if val:
    print(val)
" "$SETTINGS_FILE" "$name" "$var" 2>/dev/null
    fi
}

# -------------------------------------------------------------------
# Diagnostic functions
# -------------------------------------------------------------------

extract_package_name() {
    local name="$1"
    local args
    args=$(get_server_args "$name")
    local pkg=""
    while IFS= read -r arg; do
        if [[ "$arg" != -* && -n "$arg" ]]; then
            pkg="$arg"
            break
        fi
    done <<< "$args"
    echo "$pkg"
}

# Known API key info: where to get keys and what permissions are needed
get_api_key_info() {
    local key_name="$1"
    case "$key_name" in
        GITHUB_PERSONAL_ACCESS_TOKEN|GITHUB_TOKEN)
            echo "url=https://github.com/settings/tokens"
            echo "scopes=repo, read:org (minimum)"
            echo "note=Generate a classic Personal Access Token with repo and read:org scopes"
            ;;
        BRAVE_API_KEY)
            echo "url=https://brave.com/search/api/"
            echo "scopes=Free tier available (2,000 queries/month)"
            echo "note=Sign up and create an API key from the dashboard"
            ;;
        GOOGLE_MAPS_API_KEY)
            echo "url=https://console.cloud.google.com/apis/credentials"
            echo "scopes=Enable Places API and Geocoding API"
            echo "note=Create a project, enable APIs, then create an API key"
            ;;
        SLACK_BOT_TOKEN)
            echo "url=https://api.slack.com/apps"
            echo "scopes=channels:read, chat:write, users:read (minimum)"
            echo "note=Create a Slack App, add Bot Token Scopes, install to workspace"
            ;;
        SLACK_TEAM_ID)
            echo "url=https://api.slack.com/methods/auth.test"
            echo "scopes=none (it is a workspace identifier)"
            echo "note=Find your Team ID in Slack workspace settings or via auth.test API"
            ;;
        EVERART_API_KEY)
            echo "url=https://everart.ai"
            echo "scopes=API access"
            echo "note=Sign up at EverArt and generate an API key from your account settings"
            ;;
        *)
            echo "url=Check the server documentation"
            echo "scopes=Varies"
            echo "note=Consult the MCP server README for required credentials"
            ;;
    esac
}

check_api_keys() {
    local name="$1"
    local issues=()

    local env_keys
    env_keys=$(get_server_env_keys "$name")

    if [[ -z "$env_keys" ]]; then
        return 0
    fi

    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        local val
        val=$(get_server_env_value "$name" "$key")
        if [[ -z "$val" || "$val" == *"<your-"* || "$val" == *"your_"* || "$val" == *"-here>"* ]]; then
            issues+=("$key is not set (still has placeholder value)")
        fi
    done <<< "$env_keys"

    if [[ ${#issues[@]} -gt 0 ]]; then
        for issue in "${issues[@]}"; do
            echo "  $issue"
        done
        return 1
    fi
    return 0
}

check_path_args() {
    local name="$1"
    local args
    args=$(get_server_args "$name")
    local issues=()

    # Check for path-like arguments (filesystem, sqlite, etc.)
    while IFS= read -r arg; do
        if [[ "$arg" == /* || "$arg" == ~* ]]; then
            local expanded="${arg/#\~/$HOME}"
            if [[ ! -e "$expanded" ]]; then
                issues+=("Path does not exist: $arg")
            elif [[ -d "$expanded" && ! -r "$expanded" ]]; then
                issues+=("Path is not readable: $arg (check permissions)")
            fi
        fi
    done <<< "$args"

    if [[ ${#issues[@]} -gt 0 ]]; then
        for issue in "${issues[@]}"; do
            echo "  $issue"
        done
        return 1
    fi
    return 0
}

verify_package_exists() {
    local pkg="$1"
    if npm view "$pkg" version &>/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

verify_package_runs() {
    local pkg="$1"
    # Try to run with --help, give it a short timeout
    if timeout 15 npx -y "$pkg" --help &>/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# -------------------------------------------------------------------
# Common failure pattern detection
# -------------------------------------------------------------------

check_spawn_npx_enoent() {
    # Detect if npx command is relative (just "npx") vs absolute path
    # and whether the absolute path actually resolves
    local name="$1"
    local cmd
    cmd=$(get_server_field "$name" "command")

    if [[ "$cmd" == "npx" ]]; then
        # Relative "npx" can cause "spawn npx ENOENT" in GUI-launched environments
        local npx_path
        npx_path=$(which npx 2>/dev/null || echo "")
        if [[ -n "$npx_path" ]]; then
            echo "relative_npx|$npx_path"
        else
            echo "npx_missing|"
        fi
    elif [[ "$cmd" == /* ]]; then
        # Absolute path: verify it exists
        if [[ ! -x "$cmd" ]]; then
            echo "bad_absolute|$cmd"
        else
            echo "ok|$cmd"
        fi
    fi
}

detect_placeholder_keys() {
    # Returns a list of all placeholder API keys across all servers
    local servers="$1"
    local placeholders=()

    while IFS= read -r server_name; do
        [[ -z "$server_name" ]] && continue
        local env_keys
        env_keys=$(get_server_env_keys "$server_name")
        [[ -z "$env_keys" ]] && continue

        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            local val
            val=$(get_server_env_value "$server_name" "$key")
            if [[ -z "$val" || "$val" == *"<your-"* || "$val" == *"your_"* || "$val" == *"-here>"* ]]; then
                placeholders+=("$server_name: $key")
            fi
        done <<< "$env_keys"
    done <<< "$servers"

    if [[ ${#placeholders[@]} -gt 0 ]]; then
        printf '%s\n' "${placeholders[@]}"
    fi
}

# -------------------------------------------------------------------
# Main verification loop
# -------------------------------------------------------------------

run_checks() {
    if ! $JSON_MODE; then
        echo ""
        echo -e "${BOLD}${CYAN}========================================================${NC}"
        echo -e "${BOLD}${CYAN}  MCP Server Diagnostics                                ${NC}"
        echo -e "${BOLD}${CYAN}========================================================${NC}"
        echo ""
    fi

    # ---------------------------------------------------------------
    # Preflight Diagnostics
    # ---------------------------------------------------------------

    if ! $JSON_MODE; then
        echo -e "${BOLD}Preflight${NC}"
        echo -e "${DIM}System requirements for MCP servers${NC}"
        echo ""
    fi

    check_preflight

    if ! $JSON_MODE; then
        echo ""
    fi

    if [[ ${#preflight_issues[@]} -gt 0 ]]; then
        if ! $JSON_MODE; then
            echo -e "  ${YELLOW}${BOLD}${#preflight_issues[@]} preflight issue(s) found.${NC}"
            echo ""
        fi
    fi

    # Bail if settings file is missing or unparseable
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        if $JSON_MODE; then
            echo '{"status":"error","message":"No settings file found","servers":[]}'
        else
            echo -e "  $FAIL Cannot continue without a settings file."
            echo ""
            echo -e "  ${BOLD}To create one, run:${NC}"
            echo "    ./setup.sh"
            echo ""
        fi
        exit 1
    fi

    # Check JSON validity before proceeding
    local settings_valid=true
    if [[ "$JSON_TOOL" == "jq" ]]; then
        if ! jq '.' "$SETTINGS_FILE" &>/dev/null 2>&1; then
            settings_valid=false
        fi
    else
        if ! $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    json.load(f)
" "$SETTINGS_FILE" &>/dev/null 2>&1; then
            settings_valid=false
        fi
    fi

    if ! $settings_valid; then
        if $JSON_MODE; then
            echo '{"status":"error","message":"Settings file contains invalid JSON","servers":[]}'
        else
            echo -e "  $FAIL Settings file contains invalid JSON. Cannot read server config."
            echo ""
            echo -e "  ${BOLD}To find the error:${NC}"
            echo "    jq . ~/.claude/settings.json"
            echo ""
            echo -e "  ${BOLD}To start fresh:${NC}"
            echo "    echo '{}' > ~/.claude/settings.json && ./setup.sh"
            echo ""
        fi
        exit 1
    fi

    # Get servers
    local servers
    servers=$(get_server_names)

    if [[ -z "$servers" ]]; then
        if $JSON_MODE; then
            echo '{"status":"warning","message":"No MCP servers configured","servers":[]}'
        else
            echo -e "  $WARN No MCP servers configured in $SETTINGS_FILE"
            echo ""
            echo -e "  ${BOLD}To add servers, run:${NC}"
            echo "    ./setup.sh"
            echo ""
        fi
        exit 0
    fi

    # ---------------------------------------------------------------
    # Per-Server Diagnostics
    # ---------------------------------------------------------------

    local pass_count=0
    local fail_count=0
    local warn_count=0
    local total=0

    # JSON output accumulator
    local json_results="["
    local json_first=true

    # Dashboard accumulator for the final summary table
    declare -a dashboard_names=()
    declare -a dashboard_statuses=()
    declare -a dashboard_messages=()

    # Next-steps accumulator
    declare -a next_steps=()

    if ! $JSON_MODE; then
        echo -e "${BOLD}Per-Server Checks${NC}"
        echo ""
    fi

    while IFS= read -r server_name; do
        [[ -z "$server_name" ]] && continue
        total=$((total + 1))

        local cmd
        cmd=$(get_server_field "$server_name" "command")
        local pkg
        pkg=$(extract_package_name "$server_name")
        local status="pass"
        local status_msg=""
        local diagnostics=()

        if ! $JSON_MODE; then
            echo -e "  ${BOLD}${MAGENTA}--- $server_name ---${NC}"
        fi

        # Check 1: command exists
        if [[ -z "$cmd" || "$cmd" == "null" ]]; then
            status="fail"
            status_msg="No command configured"
            diagnostics+=("No \"command\" field in the \"$server_name\" entry.")
            diagnostics+=("Fix: Add \"command\": \"npx\" to the \"$server_name\" block in ~/.claude/settings.json")
            next_steps+=("Add \"command\": \"npx\" to the \"$server_name\" server in ~/.claude/settings.json")
        elif ! command -v "$cmd" &>/dev/null; then
            status="fail"
            status_msg="Command '$cmd' not found on PATH"
            diagnostics+=("\"$cmd\" not found on PATH.")
            if [[ "$cmd" == "npx" ]]; then
                diagnostics+=("Fix: Install Node.js v18+ (includes npx).")
                next_steps+=("Install Node.js v18+ (brew install node)")
            else
                diagnostics+=("Fix: Install $cmd, or use an absolute path in the command field.")
                next_steps+=("Install $cmd or update the command path for \"$server_name\" in ~/.claude/settings.json")
            fi
        fi

        # Check 1b: "spawn npx ENOENT" pattern detection
        if [[ "$status" == "pass" && "$cmd" == "npx" ]]; then
            local enoent_result
            enoent_result=$(check_spawn_npx_enoent "$server_name")
            local enoent_type="${enoent_result%%|*}"
            local enoent_path="${enoent_result#*|}"

            if [[ "$enoent_type" == "relative_npx" && -n "$enoent_path" ]]; then
                # Not a failure, but worth noting as a potential issue
                if ! $JSON_MODE; then
                    echo -e "       ${DIM}Tip: Using relative \"npx\". If you see \"spawn npx ENOENT\",${NC}"
                    echo -e "       ${DIM}change \"command\" to the absolute path: \"$enoent_path\"${NC}"
                fi
            elif [[ "$enoent_type" == "npx_missing" ]]; then
                status="fail"
                status_msg="npx cannot be found"
                diagnostics+=("npx not on PATH. Install Node.js v18+.")
                next_steps+=("Install Node.js v18+")
            elif [[ "$enoent_type" == "bad_absolute" ]]; then
                status="fail"
                status_msg="Command path does not exist: $enoent_path"
                diagnostics+=("Path \"$enoent_path\" does not exist or is not executable.")
                local correct_path
                correct_path=$(which npx 2>/dev/null || echo "")
                if [[ -n "$correct_path" ]]; then
                    diagnostics+=("Fix: Update the command to \"$correct_path\" in ~/.claude/settings.json")
                    next_steps+=("Change \"command\" from \"$enoent_path\" to \"$correct_path\" for \"$server_name\"")
                else
                    diagnostics+=("Fix: Install Node.js and update the command path.")
                    next_steps+=("Install Node.js and fix the command path for \"$server_name\"")
                fi
            fi
        fi

        # Check 2: for npx servers, verify the package
        if [[ "$status" == "pass" && "$cmd" == "npx" && -n "$pkg" ]]; then
            if $QUICK_MODE; then
                if verify_package_exists "$pkg"; then
                    status_msg="Package found in npm registry"
                else
                    status="fail"
                    status_msg="Package not found: $pkg"
                    diagnostics+=("Package \"$pkg\" not found in npm registry.")
                    diagnostics+=("Verify: npm view $pkg version")
                    next_steps+=("Check package name for \"$server_name\": npm view $pkg version")
                fi
            else
                if verify_package_exists "$pkg"; then
                    status_msg="Package verified ($pkg)"
                else
                    status="fail"
                    status_msg="Package not found: $pkg"
                    diagnostics+=("Package \"$pkg\" not found in npm registry.")
                    diagnostics+=("Verify: npm view $pkg version")
                    if ! curl -s --max-time 3 https://registry.npmjs.org/ &>/dev/null; then
                        diagnostics+=("npm registry unreachable. Check your network.")
                    fi
                    next_steps+=("Check package name for \"$server_name\": npm view $pkg version")
                fi
            fi
        elif [[ "$status" == "pass" && -z "$pkg" && "$cmd" == "npx" ]]; then
            status="fail"
            status_msg="No package specified in args"
            diagnostics+=("Server uses npx but no package name in \"args\".")
            diagnostics+=("Fix: \"args\": [\"-y\", \"@modelcontextprotocol/server-github\"]")
            next_steps+=("Add a package name to the \"args\" array for \"$server_name\"")
        fi

        # Check 3: API key validation
        if [[ "$status" == "pass" || "$status" == "warn" ]]; then
            local key_issues
            key_issues=$(check_api_keys "$server_name" 2>/dev/null || true)
            if [[ -n "$key_issues" ]]; then
                local prev_status="$status"
                status="warn"
                status_msg="${status_msg:+$status_msg, }missing API key(s)"

                # Collect the specific missing keys with actionable info
                local env_keys
                env_keys=$(get_server_env_keys "$server_name")
                while IFS= read -r key; do
                    [[ -z "$key" ]] && continue
                    local val
                    val=$(get_server_env_value "$server_name" "$key")
                    if [[ -z "$val" || "$val" == *"<your-"* || "$val" == *"your_"* || "$val" == *"-here>"* ]]; then
                        diagnostics+=("$key is a placeholder. Server starts but API calls will fail.")

                        # Get specific key info
                        local key_url="" key_scopes="" key_note=""
                        while IFS= read -r info_line; do
                            case "$info_line" in
                                url=*)    key_url="${info_line#url=}" ;;
                                scopes=*) key_scopes="${info_line#scopes=}" ;;
                                note=*)   key_note="${info_line#note=}" ;;
                            esac
                        done <<< "$(get_api_key_info "$key")"

                        diagnostics+=("To fix:")
                        if [[ -n "$key_url" && "$key_url" != "Check the server documentation" ]]; then
                            diagnostics+=("  1. Get your key at: $key_url")
                        fi
                        if [[ -n "$key_scopes" && "$key_scopes" != "Varies" ]]; then
                            diagnostics+=("  2. Required permissions: $key_scopes")
                        fi
                        if [[ -n "$key_note" ]]; then
                            diagnostics+=("  3. $key_note")
                        fi
                        diagnostics+=("  4. Set it in ~/.claude/settings.json under \"$server_name\" > \"env\" > \"$key\"")

                        next_steps+=("Set $key for \"$server_name\" in ~/.claude/settings.json (get key at ${key_url:-the server docs})")
                    fi
                done <<< "$env_keys"
            fi
        fi

        # Check 4: path validation
        if [[ "$status" == "pass" || "$status" == "warn" ]]; then
            local path_issues
            path_issues=$(check_path_args "$server_name" 2>/dev/null || true)
            if [[ -n "$path_issues" ]]; then
                if [[ "$status" == "pass" ]]; then
                    status="warn"
                fi

                while IFS= read -r pi; do
                    [[ -z "$pi" ]] && continue

                    # Extract the path from the issue message
                    local missing_path=""
                    if [[ "$pi" == *"Path does not exist:"* ]]; then
                        missing_path=$(echo "$pi" | sed 's/.*Path does not exist: *//')
                        local expanded_missing="${missing_path/#\~/$HOME}"
                        diagnostics+=("$pi")

                        # Determine if it looks like a directory or file
                        if [[ "$missing_path" != *.* ]]; then
                            diagnostics+=("Fix: Create the directory by running:")
                            diagnostics+=("  mkdir -p $expanded_missing")
                            next_steps+=("mkdir -p $expanded_missing")
                            apply_fix "Create missing directory $expanded_missing" "mkdir -p '$expanded_missing'" || true
                        else
                            diagnostics+=("Fix: Create the parent directory and the file:")
                            diagnostics+=("  mkdir -p $(dirname "$expanded_missing")")
                            next_steps+=("mkdir -p $(dirname "$expanded_missing")")
                            apply_fix "Create missing parent directory $(dirname "$expanded_missing")" "mkdir -p '$(dirname "$expanded_missing")'" || true
                        fi
                    else
                        diagnostics+=("$pi")
                    fi
                done <<< "$path_issues"
            fi
        fi

        # Count results
        case "$status" in
            pass) pass_count=$((pass_count + 1)) ;;
            fail) fail_count=$((fail_count + 1)) ;;
            warn) warn_count=$((warn_count + 1)) ;;
        esac

        # Track for dashboard
        dashboard_names+=("$server_name")
        dashboard_statuses+=("$status")
        dashboard_messages+=("$status_msg")

        # Output
        if $JSON_MODE; then
            if ! $json_first; then json_results+=","; fi
            json_first=false
            local diag_json="[]"
            if [[ ${#diagnostics[@]} -gt 0 ]]; then
                diag_json="["
                local d_first=true
                for d in "${diagnostics[@]}"; do
                    if ! $d_first; then diag_json+=","; fi
                    d_first=false
                    # Escape quotes in diagnostic messages
                    d="${d//\"/\\\"}"
                    diag_json+="\"$d\""
                done
                diag_json+="]"
            fi
            json_results+="{\"name\":\"$server_name\",\"package\":\"$pkg\",\"status\":\"$status\",\"message\":\"$status_msg\",\"diagnostics\":$diag_json}"
        else
            case "$status" in
                pass)
                    echo -e "  $PASS ${BOLD}$server_name${NC} - $status_msg"
                    ;;
                fail)
                    echo -e "  $FAIL ${BOLD}$server_name${NC} - $status_msg"
                    for d in "${diagnostics[@]}"; do
                        echo -e "       ${DIM}$d${NC}"
                    done
                    ;;
                warn)
                    echo -e "  $WARN ${BOLD}$server_name${NC} - $status_msg"
                    for d in "${diagnostics[@]}"; do
                        echo -e "       ${DIM}$d${NC}"
                    done
                    ;;
            esac
            echo ""
        fi

    done <<< "$servers"

    json_results+="]"

    # ---------------------------------------------------------------
    # Health Score
    # ---------------------------------------------------------------

    local score=0
    if [[ $total -gt 0 ]]; then
        score=$(( (pass_count * 100 + warn_count * 50) / total ))
    fi

    local grade grade_letter
    if (( score >= 90 )); then
        grade="${GREEN}Excellent${NC}"
        grade_letter="A"
    elif (( score >= 80 )); then
        grade="${GREEN}Good${NC}"
        grade_letter="B"
    elif (( score >= 70 )); then
        grade="${YELLOW}Good${NC}"
        grade_letter="B-"
    elif (( score >= 60 )); then
        grade="${YELLOW}Fair${NC}"
        grade_letter="C"
    elif (( score >= 50 )); then
        grade="${YELLOW}Fair${NC}"
        grade_letter="C-"
    else
        grade="${RED}Needs Attention${NC}"
        grade_letter="F"
    fi

    if $JSON_MODE; then
        # Build fixes_applied JSON array
        local fixes_json="[]"
        if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
            fixes_json="["
            local fx_first=true
            for fx in "${FIXES_APPLIED[@]}"; do
                if ! $fx_first; then fixes_json+=","; fi
                fx_first=false
                fx="${fx//\"/\\\"}"
                fixes_json+="\"$fx\""
            done
            fixes_json+="]"
        fi

        echo "{\"status\":\"complete\",\"total\":$total,\"passed\":$pass_count,\"warned\":$warn_count,\"failed\":$fail_count,\"score\":$score,\"grade\":\"$grade_letter\",\"fixes_applied\":$fixes_json,\"servers\":$json_results}"
    else
        # ---------------------------------------------------------------
        # Final Dashboard
        # ---------------------------------------------------------------

        echo -e "${BOLD}${CYAN}========================================================${NC}"
        echo -e "${BOLD}${CYAN}  Summary                                               ${NC}"
        echo -e "${BOLD}${CYAN}========================================================${NC}"
        echo ""

        # Server status table
        echo -e "  ${BOLD}Server                          Status${NC}"
        echo -e "  ${DIM}----------------------------------------------${NC}"

        for i in "${!dashboard_names[@]}"; do
            local srv_name="${dashboard_names[$i]}"
            local srv_status="${dashboard_statuses[$i]}"
            local srv_msg="${dashboard_messages[$i]}"
            local status_icon

            case "$srv_status" in
                pass) status_icon="${GREEN}PASS${NC}" ;;
                fail) status_icon="${RED}FAIL${NC}" ;;
                warn) status_icon="${YELLOW}WARN${NC}" ;;
            esac

            printf "  %-32s %b\n" "$srv_name" "$status_icon"
        done

        echo ""
        echo -e "  ${BOLD}Health Score: ${score}% (Grade: ${grade_letter}) - ${grade}${NC}"
        echo ""
        echo -e "  ${GREEN}Passed:${NC}   $pass_count"
        echo -e "  ${YELLOW}Warnings:${NC} $warn_count"
        echo -e "  ${RED}Failed:${NC}   $fail_count"
        echo -e "  ${DIM}Total:${NC}    $total"
        echo ""

        # ---------------------------------------------------------------
        # Auto-fix report
        # ---------------------------------------------------------------

        if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
            echo -e "${BOLD}${GREEN}Auto-fixed:${NC}"
            for fx in "${FIXES_APPLIED[@]}"; do
                echo -e "  ${GREEN}*${NC} $fx"
            done
            echo ""
        fi

        if [[ ${#FIXES_AVAILABLE[@]} -gt 0 ]] && ! $FIX_MODE; then
            echo -e "  ${DIM}Run with --fix to auto-fix simple issues (missing dirs, cache).${NC}"
            echo ""
        fi

        # ---------------------------------------------------------------
        # Next Steps (when something is wrong)
        # ---------------------------------------------------------------

        if [[ $fail_count -gt 0 || $warn_count -gt 0 ]]; then
            echo -e "${BOLD}Next Steps${NC}"
            echo -e "${DIM}Fix these, then re-run ./verify.sh:${NC}"
            echo ""

            local step_num=1

            # Deduplicate next_steps
            declare -A seen_steps
            for ns in "${next_steps[@]}"; do
                if [[ -z "${seen_steps[$ns]:-}" ]]; then
                    seen_steps[$ns]=1
                    echo -e "  ${BOLD}${step_num}.${NC} $ns"
                    step_num=$((step_num + 1))
                fi
            done

            # Add general advice if there were failures
            if [[ $fail_count -gt 0 ]]; then
                echo ""
                echo -e "  ${BOLD}${step_num}.${NC} Re-run: ./verify.sh"
                step_num=$((step_num + 1))
                echo -e "  ${BOLD}${step_num}.${NC} Restart Claude Code: exit and run 'claude'"
                step_num=$((step_num + 1))
            fi

            if [[ $fail_count -gt 0 ]]; then
                echo ""
                echo -e "  ${DIM}Servers broke suddenly? Try: npx clear-npx-cache${NC}"
            fi

            echo ""
        fi

        # ---------------------------------------------------------------
        # All healthy message
        # ---------------------------------------------------------------

        if [[ $pass_count -eq $total ]]; then
            echo -e "  ${GREEN}${BOLD}All $total server(s) healthy.${NC}"
            echo ""
            echo -e "  Try in Claude Code:"
            echo ""

            # Show example prompts based on configured servers
            local example_shown=false
            while IFS= read -r sn; do
                [[ -z "$sn" ]] && continue
                case "$sn" in
                    github*)
                        echo "    \"List the open PRs in this repo\""
                        example_shown=true
                        ;;
                    fetch*)
                        if ! $example_shown; then
                            echo "    \"Fetch https://httpbin.org/get and show me the response\""
                            example_shown=true
                        fi
                        ;;
                    brave-search*)
                        echo "    \"Search the web for MCP server best practices\""
                        example_shown=true
                        ;;
                    memory*)
                        echo "    \"Remember that my preferred language is Python\""
                        ;;
                    context7*)
                        echo "    \"Use context7 to get the latest docs for FastAPI\""
                        ;;
                esac
            done <<< "$servers"

            if ! $example_shown; then
                echo "    \"What MCP tools do I have available?\""
            fi
            echo ""
        fi

        if [[ $warn_count -gt 0 && $fail_count -eq 0 ]]; then
            echo -e "  ${YELLOW}$warn_count warning(s): servers start but need real API keys for full functionality.${NC}"
            echo ""
        fi
    fi

    # Exit with error if any servers failed
    if [[ $fail_count -gt 0 ]]; then
        exit 1
    fi
}

run_checks
