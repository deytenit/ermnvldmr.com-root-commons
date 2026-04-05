#!/bin/bash

# --- Standard Settings ---
# Ensures scripts exit on error, undefined variables are errors,
# and errors in pipelines are caught.
set -euo pipefail

# --- Global Variables ---
# REPO_ROOT: Will be set by navigate_to_repo_root
# SCRIPT_NAME: Can be overridden by the calling script for custom log prefixes.
#              If not set, logging functions will attempt to derive it.

# --- Logging/Messaging ---
# Internal log function.
# Usage: _log "TYPE" "Message"
_log() {
    local type="$1"
    # SCRIPT_NAME_FOR_LOG tries to use SCRIPT_NAME if set by the caller,
    # otherwise defaults to the basename of the script that called the log function.
    # BASH_SOURCE[2] should point to the script calling log_info/log_error etc.
    local SCRIPT_NAME_FOR_LOG="${SCRIPT_NAME:-$(basename "${BASH_SOURCE[2]%.*}")}"
    shift
    echo "[$SCRIPT_NAME_FOR_LOG] [$type] $*"
}

log_info() {
    _log "INFO" "$@"
}

log_warn() {
    _log "WARN" "$@"
}

log_error() {
    _log "ERROR" "$@" >&2 # Send errors to stderr
}

log_success() {
    _log "SUCCESS" "$@"
}

# --- Repository Navigation ---
# Sets REPO_ROOT variable and changes the current directory to it. Exits on failure.
# Usage: navigate_to_repo_root
navigate_to_repo_root() {
    # If an argument is provided, use it to set the global NODE variable.
    if [[ -n "${1:-}" ]]; then
        NODE="$1"
    fi

    # If REPO_ROOT is already set and we are in a "warm" environment, trust it.
    if [[ "${ROOT_WARM:-}" != "true" ]] || [[ -z "${REPO_ROOT:-}" ]]; then
        local calling_script_path
        # BASH_SOURCE[1] should be the script that called this function (i.e., the main script).
        calling_script_path="${BASH_SOURCE[1]}"
        if [[ -z "$calling_script_path" ]]; then
            # Fallback if BASH_SOURCE[1] is not available (e.g. direct execution for testing common.sh itself)
            calling_script_path="${BASH_SOURCE[0]}"
        fi

        # Try to get repo root based on the calling script's directory
        REPO_ROOT="$(git -C "$(dirname "$calling_script_path")" rev-parse --show-toplevel 2>/dev/null)" || {
            log_error "Failed to find repository root from $(dirname "$calling_script_path"). Ensure you are in a git repository."
            exit 1
        }

        # If the found root is the shared submodule, the true REPO_ROOT is two levels up
        if [[ "$REPO_ROOT" == */.operator/shared ]]; then
            REPO_ROOT="$(cd "$REPO_ROOT/../.." >/dev/null 2>&1 && pwd)"
        fi
    fi

    cd "$REPO_ROOT" || {
        log_error "Failed to cd into repository root: $REPO_ROOT"
        exit 1
    }
    # log_info "Changed directory to repository root: $REPO_ROOT" # Uncomment for debugging
}

# --- Argument Validation ---
# Checks if a required argument is provided. Exits with error if not.
# Usage: require_arg "ARG_NAME" "$ARG_VALUE" ["Usage message part"]
require_arg() {
    local arg_name="$1"
    local arg_value="$2"
    local usage_hint="${3:-}"

    if [[ -z "$arg_value" ]]; then
        log_error "Missing required argument: $arg_name."
        if [[ -n "$usage_hint" ]]; then
            echo "Usage hint: $usage_hint" >&2
        fi
        exit 64 # Standard exit code for command line usage errors
    fi
}

# --- Timestamp ---
# Returns a standardized timestamp string.
# Usage: local timestamp=$(get_timestamp)
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S %Z"
}

# --- OS Detection ---
# Check if running Debian or Ubuntu and exit early if not
# Usage: ensure_debian_ubuntu
ensure_debian_ubuntu() {
    if ! grep -Ei 'debian|ubuntu' /etc/os-release >/dev/null 2>&1; then
        log_warn "This system is not running Debian or Ubuntu. Exiting early."
        exit 0
    fi
    log_info "Confirmed Debian/Ubuntu system."
}

# --- Template Rendering ---
# Universal template rendering using envsubst - supports ANY environment variables
# Usage: render_template <input_file> <output_file>
render_template() {
    local input_file="$1"
    local output_file="$2"
    
    require_arg "input_file" "$input_file" "Usage: render_template <input_file> <output_file>"
    require_arg "output_file" "$output_file" "Usage: render_template <input_file> <output_file>"
    
    if [[ ! -f "$input_file" ]]; then
        log_error "Template file not found: $input_file"
        return 1
    fi
    
    # Check if envsubst is available
    if ! command -v envsubst >/dev/null 2>&1; then
        log_error "envsubst is not available. Please install gettext-base package."
        return 1
    fi
    
    # Render template with all environment variables
    if envsubst < "$input_file" > "$output_file"; then
        log_info "Template rendered: $input_file -> $output_file"
        return 0
    else
        log_error "Failed to render template: $input_file"
        return 1
    fi
}

# --- Telegram Notifications ---
# Internal core function to send Telegram messages.
# Usage: _telegram "STATUS_TYPE" "Title Prefix" "$TELEGRAM_BOT_URL" "Actual message" ["$NODE_NAME"]
_telegram() {
    local status_type="$1" # e.g., "SUCCESS", "ERROR", "INFO"
    local title_prefix="$2"
    local bot_url="$3"
    local message_content="$4"
    local node_name="${5:-}" # Optional node name

    require_arg "Telegram Bot URL for _telegram" "$bot_url"

    local timestamp
    timestamp=$(get_timestamp)

    local text_payload_parts=()
    text_payload_parts+=("*${title_prefix}*")
    text_payload_parts+=("") # Extra newline
    if [[ -n "$node_name" ]]; then
        text_payload_parts+=("*Node*: ${node_name}")
    fi
    text_payload_parts+=("*Timestamp*: ${timestamp}")
    text_payload_parts+=("*Status*: ${status_type}") # Use the passed status_type
    text_payload_parts+=("") # Extra newline
    text_payload_parts+=("${message_content}")

    local final_text_payload
    final_text_payload=$(printf "%s\n" "${text_payload_parts[@]}")

    if curl -s -X POST "$bot_url" \
         --data-urlencode "parse_mode=Markdown" \
         --data-urlencode "text=${final_text_payload}" > /dev/null; then
        # log_info "Telegram notification ($status_type) sent successfully for '$title_prefix'." # Optional
        return 0
    else
        log_warn "Failed to send Telegram notification ($status_type) for '$title_prefix'."
        return 1 # Indicate failure
    fi
}

# Wrapper functions for different Telegram notification statuses
# Usage: telegram_success "Title Prefix" "$TELEGRAM_BOT_URL" "Actual message" ["$NODE_NAME"]
telegram_success() {
    _telegram "#success" "$@"
}

telegram_error() {
    _telegram "#error" "$@"
}

telegram_info() {
    _telegram "#info" "$@"
}

telegram_warn() {
    _telegram "#warning" "$@"
}

# --- Common Error Trap Handler ---
# Sets up an ERR trap to call telegram_error on script errors.
# Usage: setup_error_trap "Title Prefix for Error" "$TELEGRAM_BOT_URL" ["$NODE_NAME"]
setup_error_trap() {
    local error_title_prefix="$1"
    local error_bot_url="$2"
    local error_node_name="${3:-}" # Optional node name

    declare -g __COMMON_ERR_TRAP_TITLE_PREFIX="$error_title_prefix"
    declare -g __COMMON_ERR_TRAP_BOT_URL="$error_bot_url"
    declare -g __COMMON_ERR_TRAP_NODE_NAME="$error_node_name"

    _common_error_trap_handler() {
        local SCRIPT_NAME_FOR_TRAP="${SCRIPT_NAME:-$(basename "${BASH_SOURCE[1]%.*}")}"
        local line_no="$1"
        local failed_command="$2"
        local error_message="An unexpected error occurred in script '$SCRIPT_NAME_FOR_TRAP' at line $line_no."
        error_message+=$'\n'"Last command: $failed_command"$'\n'"Manual intervention may be required."

        log_error "$error_message" # Log to console as well

        if [[ -n "$__COMMON_ERR_TRAP_BOT_URL" ]]; then
            # Call the new telegram_error wrapper
            telegram_error \
                "$__COMMON_ERR_TRAP_TITLE_PREFIX" \
                "$__COMMON_ERR_TRAP_BOT_URL" \
                "$error_message" \
                "$__COMMON_ERR_TRAP_NODE_NAME"
        else
            log_warn "Telegram Bot URL not configured for error trap; cannot send notification."
        fi
        # Script will exit due to 'set -e'
    }
    trap '_common_error_trap_handler $LINENO "$BASH_COMMAND"' ERR
}

# --- Source this file in other scripts like this: ---
# SCRIPT_DIR_COMMON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source "$SCRIPT_DIR_COMMON/common.sh"
#
# # Optional: Set SCRIPT_NAME for custom log prefixes, otherwise it's derived.
# SCRIPT_NAME="my_cool_script"
#
# # Example usage:
# # navigate_to_repo_root
# # log_info "Now in $REPO_ROOT"
# # require_arg "MY_VAR" "$MY_VAR_VALUE"
# # setup_error_trap "My Script Error" "$MY_TELEGRAM_URL" "$MY_NODE"
# # telegram_info "My Script" "$MY_TELEGRAM_URL" "Script starting..." "$MY_NODE"
# # my_timestamp=$(get_timestamp)
