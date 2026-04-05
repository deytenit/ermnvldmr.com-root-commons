#!/bin/bash
#
# scripts/lib/root_core.sh
# Core logging and environment validation
#

# --- Standard Settings ---
set -euo pipefail

# --- Logging/Messaging ---
_root_log() {
    local type="$1"
    local node_prefix="${ROOT_NODE:-global}"
    local action_prefix="${ROOT_ACTION_PATH:-core}"
    shift
    echo "[$node_prefix] [$action_prefix] [$type] $*"
}

root_log_info() { _root_log "INFO" "$@"; }
root_log_warn() { _root_log "WARN" "$@"; }
root_log_error() { _root_log "ERROR" "$@" >&2; }
root_log_success() { _root_log "SUCCESS" "$@"; }

# --- Environment Validation ---
root_ensure_env() {
    if [[ -z "${ROOT_SHARED:-}" ]]; then
        root_log_error "ROOT_SHARED environment variable is not set."
        exit 1
    fi
    if [[ -z "${ROOT_CONFIGS:-}" ]]; then
        root_log_error "ROOT_CONFIGS environment variable is not set."
        exit 1
    fi
}

# --- Node Validation Helper ---
root_require_node() {
    local node_name="$1"
    if [[ -z "$node_name" ]]; then
        root_log_error "Missing required NODE argument."
        exit 64
    fi

    local node_dir="$ROOT_CONFIGS/$node_name"
    if [[ ! -d "$node_dir" ]]; then
        root_log_error "Node directory not found: $node_dir"
        exit 1
    fi

    export ROOT_NODE="$node_name"
    export ROOT_NODE_DIR="$node_dir"
    export ROOT_TIER1="$node_dir/@tier1"
    export ROOT_TIER2="$node_dir/@tier2"
    export ROOT_TIER3="$node_dir/@tier3"
    
    root_log_info "Node context established: $ROOT_NODE"
}

# --- Utility Functions ---

# Get current timestamp in a standardized format
root_core_get_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# --- Telegram Notifications ---

# Send notification via Telegram bot webhook
root_core_telegram() {
    local title="$1"
    local bot_url="$2"
    local message="$3"
    local node="${4:-${ROOT_NODE:-global}}"
    local type="${5:-INFO}"

    if [[ -z "$bot_url" ]]; then
        root_log_warn "Telegram Bot URL not provided. Skipping Telegram notification."
        return 0
    fi

    local payload="[$node] [$type] $title"$'\n\n'"$message"
    
    root_log_info "Sending Telegram notification ($type): $title"
    
    # Send to Telegram (assuming bot_url is the full API URL including token)
    if ! curl -s -f -X POST "$bot_url" \
        -d "text=$(echo "$payload" | sed 's/"/\\"/g')" > /dev/null; then
        root_log_error "Failed to send Telegram notification."
        return 1
    fi
    return 0
}

root_core_telegram_success() { root_core_telegram "$1" "$2" "$3" "${4:-}" "SUCCESS"; }
root_core_telegram_error() { root_core_telegram "$1" "$2" "$3" "${4:-}" "ERROR"; }
root_core_telegram_info() { root_core_telegram "$1" "$2" "$3" "${4:-}" "INFO"; }
root_core_telegram_warn() { root_core_telegram "$1" "$2" "$3" "${4:-}" "WARN"; }

# --- Error Handling ---

# Setup an error trap that sends a Telegram notification on failure
root_core_setup_error_trap() {
    local title="$1"
    local bot_url="${2:-}"
    local node="${3:-${ROOT_NODE:-global}}"

    trap '
        EXIT_CODE=$?;
        root_log_error "Error occurred in $ROOT_ACTION_PATH at line $LINENO (exit code: $EXIT_CODE)";
        if [[ -n "$bot_url" ]]; then
            root_core_telegram_error "$title" "$bot_url" "Critical error occurred at line $LINENO (exit code: $EXIT_CODE)" "$node";
        fi
    ' ERR
}
