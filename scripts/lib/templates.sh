#!/usr/bin/env bash
#
# .operator/scripts/lib/templates.sh
# Standardized template rendering utilities
#
# This library provides consistent template rendering functionality
# across all automation scripts using envsubst.

# Standardized template rendering
render_template() {
    local input_file="$1"
    local output_file="$2"
    
    validate_template_inputs "$input_file" "$output_file"
    
    # Use envsubst consistently for all template rendering
    if envsubst < "$input_file" > "$output_file.tmp"; then
        mv "$output_file.tmp" "$output_file"
        log_info "Template rendered: $input_file -> $output_file"
        return 0
    else
        rm -f "$output_file.tmp"
        log_error "Failed to render template: $input_file"
        return 1
    fi
}

# Batch template rendering for directories
render_template_directory() {
    local source_dir="$1"
    local target_dir="$2"
    
    find "$source_dir" -type f -name "*.template" | while read -r template; do
        local relative_path="${template#$source_dir/}"
        local target_file="$target_dir/${relative_path%.template}"
        
        mkdir -p "$(dirname "$target_file")"
        render_template "$template" "$target_file"
    done
}

validate_template_inputs() {
    local input_file="$1"
    local output_file="$2"
    
    require_arg "input_file" "$input_file"
    require_arg "output_file" "$output_file"
    
    if [[ ! -f "$input_file" ]]; then
        log_error "Template file not found: $input_file"
        exit 1
    fi
    
    if ! command -v envsubst >/dev/null 2>&1; then
        log_error "envsubst not available. Install gettext-base package."
        exit 1
    fi
}

# Enhanced render_template that supports custom variable sets
render_template_with_vars() {
    local input_file="$1"
    local output_file="$2"
    local vars_file="$3"  # File containing VAR=value pairs
    
    validate_template_inputs "$input_file" "$output_file"
    
    if [[ -n "$vars_file" && -f "$vars_file" ]]; then
        # Source the variables file and then render
        set -a  # Export all variables
        source "$vars_file"
        set +a
    fi
    
    render_template "$input_file" "$output_file"
}