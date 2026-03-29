#!/usr/bin/env bash
#
# .operator/scripts/lib/init.sh
# Declarative service initialization framework
#
# This library provides a standardized approach to service initialization that
# eliminates code duplication across node-specific init scripts.

# Declarative service initialization
# Usage: init_service "service_name" "packages" [custom_function]
init_service() {
	local service_name="$1"
	local packages="$2"        # space-separated package list
	local custom_setup="${3:-}" # optional custom setup function

	log_info "Starting $service_name initialization for $NODE node..."

	# Automatic package installation
	if [[ -n "$packages" ]]; then
		install_packages $packages
	fi

	# Standard environment setup
	setup_node_host_environment

	# Execute custom setup if provided (configuration should be handled here)
	if [[ -n "$custom_setup" ]] && declare -f "$custom_setup" >/dev/null; then
		"$custom_setup"
	fi

	# Automatic service management
	if command -v systemctl >/dev/null 2>&1; then
		ensure_service_running "$service_name"
	fi

	# Comprehensive health check
	if ! health_check_service "$service_name"; then
		log_error "$service_name initialization failed health check."
		exit 1
	fi

	log_success "$service_name initialization completed for $NODE node."
}

# Helper functions for common patterns
install_packages() {
	local packages=("$@")
	for package in "${packages[@]}"; do
		if ! command -v "$package" >/dev/null 2>&1; then
			log_info "Installing $package..."
			sudo apt-get update -y
			sudo apt-get install -y "$package"
			log_success "$package installed successfully."
		else
			log_info "$package already installed."
		fi
	done
}

ensure_service_running() {
	local service="$1"
	if ! systemctl is-active --quiet "$service" 2>/dev/null; then
		log_info "Starting $service service..."
		sudo systemctl enable --now "$service"
		log_success "$service service started."
	else
		log_info "$service service already running."
	fi
}

setup_node_host_environment() {
	export NODE="${NODE:-$(basename "$(pwd)")}"
	export TIER1="$REPO_ROOT/$NODE/@tier1"
	export TIER2="$REPO_ROOT/$NODE/@tier2"
	export TIER3="$REPO_ROOT/$NODE/@tier3"
	export SCRIPTS="$REPO_ROOT/.operator/shared/scripts"
}

health_check_service() {
	local service="$1"
	if ! systemctl is-active --quiet "$service" 2>/dev/null; then
		log_error "$service is not active after initialization"
		return 1
	fi
	log_success "$service health check passed"
	return 0
}

