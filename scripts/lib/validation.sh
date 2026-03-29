#!/usr/bin/env bash
#
# .operator/scripts/lib/validation.sh
# Input validation helpers
#
# This library provides standardized validation functions for
# ensuring script inputs and system state meet requirements.

# Validate that a file exists and is readable
validate_file_exists() {
    local file_path="$1"
    local description="${2:-File}"
    
    if [[ ! -f "$file_path" ]]; then
        log_error "$description not found: $file_path"
        return 1
    fi
    
    if [[ ! -r "$file_path" ]]; then
        log_error "$description is not readable: $file_path"
        return 1
    fi
    
    return 0
}

# Validate that a directory exists and is accessible
validate_directory_exists() {
    local dir_path="$1"
    local description="${2:-Directory}"
    
    if [[ ! -d "$dir_path" ]]; then
        log_error "$description not found: $dir_path"
        return 1
    fi
    
    if [[ ! -r "$dir_path" ]]; then
        log_error "$description is not accessible: $dir_path"
        return 1
    fi
    
    return 0
}

# Validate that a command exists and is executable
validate_command_exists() {
    local command_name="$1"
    local description="${2:-Command}"
    
    if ! command -v "$command_name" >/dev/null 2>&1; then
        log_error "$description '$command_name' not found in PATH"
        return 1
    fi
    
    return 0
}

# Validate that required environment variables are set
validate_env_vars() {
    local vars=("$@")
    local missing_vars=()
    
    for var in "${vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    return 0
}

# Validate that a string matches a pattern
validate_pattern() {
    local value="$1"
    local pattern="$2"
    local description="${3:-Value}"
    
    if [[ ! "$value" =~ $pattern ]]; then
        log_error "$description '$value' does not match required pattern: $pattern"
        return 1
    fi
    
    return 0
}

# Validate that a number is within a range
validate_number_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local description="${4:-Number}"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        log_error "$description '$value' is not a valid number"
        return 1
    fi
    
    if [[ $value -lt $min || $value -gt $max ]]; then
        log_error "$description '$value' is not within range [$min, $max]"
        return 1
    fi
    
    return 0
}

# Validate that we're running as the expected user
validate_user() {
    local expected_user="$1"
    local current_user="$(whoami)"
    
    if [[ "$current_user" != "$expected_user" ]]; then
        log_error "Script must be run as user '$expected_user', currently running as '$current_user'"
        return 1
    fi
    
    return 0
}

# Validate that we have sudo privileges
validate_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_error "Script requires sudo privileges. Please run 'sudo -v' first or run with sudo."
        return 1
    fi
    
    return 0
}

# Validate network connectivity to a host
validate_network_connectivity() {
    local host="$1"
    local port="${2:-80}"
    local timeout="${3:-5}"
    
    if ! timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        log_error "Cannot connect to $host:$port (timeout: ${timeout}s)"
        return 1
    fi
    
    return 0
}

# Validate disk space availability
validate_disk_space() {
    local path="$1"
    local required_mb="$2"
    local description="${3:-Path}"
    
    # Get available space in MB
    local available_mb
    available_mb=$(df -m "$path" | awk 'NR==2 {print $4}')
    
    if [[ $available_mb -lt $required_mb ]]; then
        log_error "$description requires ${required_mb}MB but only ${available_mb}MB available at $path"
        return 1
    fi
    
    return 0
}

# Validate system architecture
validate_architecture() {
    local expected_arch="$1"
    local current_arch="$(uname -m)"
    
    if [[ "$current_arch" != "$expected_arch" ]]; then
        log_error "Script requires $expected_arch architecture, current: $current_arch"
        return 1
    fi
    
    return 0
}