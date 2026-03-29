#!/usr/bin/env bash
#
# .operator/scripts/lib/services.sh
# Service management utilities
#
# This library provides standardized service management functions
# for consistent handling across different system configurations.

# Check if a service exists on the system
service_exists() {
    local service_name="$1"
    systemctl list-unit-files --type=service | grep -q "^${service_name}.service"
}

# Check if a service is currently active
service_is_active() {
    local service_name="$1"
    systemctl is-active --quiet "$service_name" 2>/dev/null
}

# Check if a service is enabled
service_is_enabled() {
    local service_name="$1"
    systemctl is-enabled --quiet "$service_name" 2>/dev/null
}

# Start and enable a service
start_and_enable_service() {
    local service_name="$1"
    
    if ! service_exists "$service_name"; then
        log_warn "Service $service_name does not exist on this system"
        return 1
    fi
    
    if ! service_is_active "$service_name"; then
        log_info "Starting $service_name service..."
        sudo systemctl start "$service_name"
    fi
    
    if ! service_is_enabled "$service_name"; then
        log_info "Enabling $service_name service..."
        sudo systemctl enable "$service_name"
    fi
    
    if service_is_active "$service_name"; then
        log_success "$service_name service is now active and enabled"
        return 0
    else
        log_error "Failed to start $service_name service"
        return 1
    fi
}

# Stop and disable a service
stop_and_disable_service() {
    local service_name="$1"
    
    if ! service_exists "$service_name"; then
        log_warn "Service $service_name does not exist on this system"
        return 1
    fi
    
    if service_is_active "$service_name"; then
        log_info "Stopping $service_name service..."
        sudo systemctl stop "$service_name"
    fi
    
    if service_is_enabled "$service_name"; then
        log_info "Disabling $service_name service..."
        sudo systemctl disable "$service_name"
    fi
    
    log_success "$service_name service is now stopped and disabled"
}

# Restart a service
restart_service() {
    local service_name="$1"
    
    if ! service_exists "$service_name"; then
        log_error "Service $service_name does not exist on this system"
        return 1
    fi
    
    log_info "Restarting $service_name service..."
    sudo systemctl restart "$service_name"
    
    if service_is_active "$service_name"; then
        log_success "$service_name service restarted successfully"
        return 0
    else
        log_error "Failed to restart $service_name service"
        return 1
    fi
}

# Reload service configuration
reload_service() {
    local service_name="$1"
    
    if ! service_exists "$service_name"; then
        log_error "Service $service_name does not exist on this system"
        return 1
    fi
    
    log_info "Reloading $service_name service configuration..."
    sudo systemctl reload "$service_name"
    log_success "$service_name service configuration reloaded"
}

# Get service status information
get_service_status() {
    local service_name="$1"
    
    if ! service_exists "$service_name"; then
        log_error "Service $service_name does not exist on this system"
        return 1
    fi
    
    echo "Status of $service_name:"
    systemctl status "$service_name" --no-pager --lines=5
}

# Wait for a service to become active
wait_for_service() {
    local service_name="$1"
    local timeout="${2:-30}"  # Default 30 seconds timeout
    local interval="${3:-2}"   # Default 2 seconds check interval
    
    local elapsed=0
    
    log_info "Waiting for $service_name to become active (timeout: ${timeout}s)..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if service_is_active "$service_name"; then
            log_success "$service_name is now active (took ${elapsed}s)"
            return 0
        fi
        
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    log_error "$service_name did not become active within ${timeout} seconds"
    return 1
}