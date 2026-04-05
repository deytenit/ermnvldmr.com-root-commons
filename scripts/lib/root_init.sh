#!/usr/bin/env bash
#
# scripts/lib/root_init.sh
# Declarative service initialization framework
#
# This library provides a standardized approach to service initialization that
# eliminates code duplication across node-specific init scripts.

# Declarative service initialization
# Usage: root_init_service "service_name" "packages" [custom_function]
root_init_service() {
	local service_name="$1"
	local packages="$2"        # space-separated package list
	local custom_setup="${3:-}" # optional custom setup function

	root_log_info "Starting $service_name initialization for $ROOT_NODE node..."

	# Automatic package installation
	if [[ -n "$packages" ]]; then
		root_init_install_packages $packages
	fi

	# Standard environment setup
	root_init_setup_node_host_environment

	# Execute custom setup if provided (configuration should be handled here)
	if [[ -n "$custom_setup" ]] && declare -f "$custom_setup" >/dev/null; then
		"$custom_setup"
	fi

	# Automatic service management
	if command -v systemctl >/dev/null 2>&1; then
		root_init_ensure_service_running "$service_name"
	fi

	# Comprehensive health check
	if ! root_init_health_check_service "$service_name"; then
		root_log_error "$service_name initialization failed health check."
		exit 1
	fi

	root_log_success "$service_name initialization completed for $ROOT_NODE node."
}

# Helper functions for common patterns
root_init_install_packages() {
	local packages=("$@")
	for package in "${packages[@]}"; do
		if ! command -v "$package" >/dev/null 2>&1; then
			root_log_info "Installing $package..."
			sudo apt-get update -y
			sudo apt-get install -y "$package"
			root_log_success "$package installed successfully."
		else
			root_log_info "$package already installed."
		fi
	done
}

root_init_ensure_service_running() {
	local service="$1"
	if ! systemctl is-active --quiet "$service" 2>/dev/null; then
		root_log_info "Starting $service service..."
		sudo systemctl enable --now "$service"
		root_log_success "$service service started."
	else
		root_log_info "$service service already running."
	fi
}

root_init_setup_node_host_environment() {
	if [[ -z "${ROOT_NODE:-}" ]]; then
		export ROOT_NODE="$(basename "$(pwd)")"
	fi
	export TIER1="$ROOT_CONFIGS/$ROOT_NODE/@tier1"
	export TIER2="$ROOT_CONFIGS/$ROOT_NODE/@tier2"
	export TIER3="$ROOT_CONFIGS/$ROOT_NODE/@tier3"
	export SCRIPTS="$ROOT_SHARED/scripts"
}

root_init_health_check_service() {
	local service="$1"
	if ! systemctl is-active --quiet "$service" 2>/dev/null; then
		root_log_error "$service is not active after initialization"
		return 1
	fi
	root_log_success "$service health check passed"
	return 0
}
