#!/usr/bin/env bash
#
# scripts/lib/root_sys.sh
# Service management utilities
#
# This library provides standardized service management functions
# for consistent handling across different system configurations.

# Check if a service exists on the system
root_sys_service_exists() {
    local service_name="$1"
    systemctl list-unit-files --type=service | grep -q "^${service_name}.service"
}

# Check if a service is currently active
root_sys_service_is_active() {
    local service_name="$1"
    systemctl is-active --quiet "$service_name" 2>/dev/null
}

# Check if a service is enabled
root_sys_service_is_enabled() {
    local service_name="$1"
    systemctl is-enabled --quiet "$service_name" 2>/dev/null
}

# Start and enable a service
root_sys_start_and_enable_service() {
    local service_name="$1"
    
    if ! root_sys_service_exists "$service_name"; then
        root_log_warn "Service $service_name does not exist on this system"
        return 1
    fi
    
    if ! root_sys_service_is_active "$service_name"; then
        root_log_info "Starting $service_name service..."
        sudo systemctl start "$service_name"
    fi
    
    if ! root_sys_service_is_enabled "$service_name"; then
        root_log_info "Enabling $service_name service..."
        sudo systemctl enable "$service_name"
    fi
    
    if root_sys_service_is_active "$service_name"; then
        root_log_success "$service_name service is now active and enabled"
        return 0
    else
        root_log_error "Failed to start $service_name service"
        return 1
    fi
}

# Stop and disable a service
root_sys_stop_and_disable_service() {
    local service_name="$1"
    
    if ! root_sys_service_exists "$service_name"; then
        root_log_warn "Service $service_name does not exist on this system"
        return 1
    fi
    
    if root_sys_service_is_active "$service_name"; then
        root_log_info "Stopping $service_name service..."
        sudo systemctl stop "$service_name"
    fi
    
    if root_sys_service_is_enabled "$service_name"; then
        root_log_info "Disabling $service_name service..."
        sudo systemctl disable "$service_name"
    fi
    
    root_log_success "$service_name service is now stopped and disabled"
}

# Restart a service
root_sys_restart_service() {
    local service_name="$1"
    
    if ! root_sys_service_exists "$service_name"; then
        root_log_error "Service $service_name does not exist on this system"
        return 1
    fi
    
    root_log_info "Restarting $service_name service..."
    sudo systemctl restart "$service_name"
    
    if root_sys_service_is_active "$service_name"; then
        root_log_success "$service_name service restarted successfully"
        return 0
    else
        root_log_error "Failed to restart $service_name service"
        return 1
    fi
}

# Reload service configuration
root_sys_reload_service() {
    local service_name="$1"
    
    if ! root_sys_service_exists "$service_name"; then
        root_log_error "Service $service_name does not exist on this system"
        return 1
    fi
    
    root_log_info "Reloading $service_name service configuration..."
    sudo systemctl reload "$service_name"
    root_log_success "$service_name service configuration reloaded"
}

# Get service status information
root_sys_get_service_status() {
    local service_name="$1"
    
    if ! root_sys_service_exists "$service_name"; then
        root_log_error "Service $service_name does not exist on this system"
        return 1
    fi
    
    echo "Status of $service_name:"
    systemctl status "$service_name" --no-pager --lines=5
}

# Wait for a service to become active
root_sys_wait_for_service() {
    local service_name="$1"
    local timeout="${2:-30}"  # Default 30 seconds timeout
    local interval="${3:-2}"   # Default 2 seconds check interval
    
    local elapsed=0
    
    root_log_info "Waiting for $service_name to become active (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if root_sys_service_is_active "$service_name"; then
            root_log_success "$service_name is now active (took ${elapsed}s)"
            return 0
        fi
        
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    root_log_error "$service_name did not become active within ${timeout} seconds"
    return 1
}
