#!/usr/bin/env bash
#
# scripts/lib/root_template.sh
# Standardized template rendering utilities
#
# This library provides consistent template rendering functionality
# across all automation scripts using envsubst.

# Standardized template rendering
root_template_render() {
    local input_file="$1"
    local output_file="$2"
    
    root_template_validate_inputs "$input_file" "$output_file"
    
    # Use envsubst consistently for all template rendering
    if envsubst < "$input_file" > "$output_file.tmp"; then
        mv "$output_file.tmp" "$output_file"
        root_log_info "Template rendered: $input_file -> $output_file"
        return 0
    else
        rm -f "$output_file.tmp"
        root_log_error "Failed to render template: $input_file"
        return 1
    fi
}

# Batch template rendering for directories
root_template_render_directory() {
    local source_dir="$1"
    local target_dir="$2"
    
    find "$source_dir" -type f -name "*.template" | while read -r template; do
        local relative_path="${template#$source_dir/}"
        local target_file="$target_dir/${relative_path%.template}"
        
        mkdir -p "$(dirname "$target_file")"
        root_template_render "$template" "$target_file"
    done
}

root_template_validate_inputs() {
    local input_file="$1"
    local output_file="$2"
    
    if [[ -z "$input_file" ]]; then
        root_log_error "Missing required argument: input_file"
        exit 64
    fi

    if [[ -z "$output_file" ]]; then
        root_log_error "Missing required argument: output_file"
        exit 64
    fi
    
    if [[ ! -f "$input_file" ]]; then
        root_log_error "Template file not found: $input_file"
        exit 1
    fi
    
    if ! command -v envsubst >/dev/null 2>&1; then
        root_log_error "envsubst not available. Install gettext-base package."
        exit 1
    fi
}

# Enhanced render_template that supports custom variable sets
root_template_render_with_vars() {
    local input_file="$1"
    local output_file="$2"
    local vars_file="$3"  # File containing VAR=value pairs
    
    root_template_validate_inputs "$input_file" "$output_file"
    
    if [[ -n "$vars_file" && -f "$vars_file" ]]; then
        # Source the variables file and then render
        set -a  # Export all variables
        source "$vars_file"
        set +a
    fi
    
    root_template_render "$input_file" "$output_file"
}

# --- Templated Utility Functions ---

root_template_crontab() {
    local TEMPLATE_FILE="$1"
    if [[ -z "$TEMPLATE_FILE" ]]; then
        root_log_error "Usage: root_template_crontab <template_file>"
        return 64
    fi

    # --- Resolve template path ---
    if [[ "$TEMPLATE_FILE" = /* ]]; then
        local FULL_TEMPLATE_PATH="$TEMPLATE_FILE"
    else
        local FULL_TEMPLATE_PATH="$ROOT_CONFIGS/$TEMPLATE_FILE"
    fi

    if [[ ! -f "$FULL_TEMPLATE_PATH" ]]; then
        root_log_error "Template not found: $FULL_TEMPLATE_PATH"
        return 66 # EX_NOINPUT
    fi

    root_log_info "Using template: $FULL_TEMPLATE_PATH"

    # --- Backup & create scratch files ---
    local TMP_CRONTAB=$(mktemp)
    local BACKUP_CRONTAB=$(mktemp)
    
    # Try to backup existing crontab, ignore error if no crontab exists
    if crontab -l >"$BACKUP_CRONTAB" 2>/dev/null; then
        root_log_info "Backed up current crontab to $BACKUP_CRONTAB"
    else
        root_log_info "No existing crontab to backup, or crontab is empty. Backup file $BACKUP_CRONTAB will be empty."
    fi

    # --- Render template using environment variables ---
    # All environment variables are available to the template automatically
    root_template_render "$FULL_TEMPLATE_PATH" "$TMP_CRONTAB"

    if [[ ! -s "$TMP_CRONTAB" ]]; then
        root_log_error "Rendered crontab is empty. Aborting and restoring previous version if any."
        # Attempt to restore, ignoring error if backup was empty or failed (e.g., no crontab before)
        crontab "$BACKUP_CRONTAB" 2>/dev/null || true
        rm -f "$TMP_CRONTAB" "$BACKUP_CRONTAB"
        return 65 # EX_DATAERR
    fi

    root_log_info "Rendered crontab preview:"
    cat "$TMP_CRONTAB" # Show what will be installed

    # --- Install and rollback if invalid ---
    if crontab "$TMP_CRONTAB"; then
        root_log_success "Crontab for '$ROOT_NODE' installed successfully from $FULL_TEMPLATE_PATH."
        rm -f "$TMP_CRONTAB" "$BACKUP_CRONTAB"
    else
        root_log_error "Failed to install crontab – restoring previous version."
        if crontab "$BACKUP_CRONTAB" 2>/dev/null; then
            root_log_info "Restored previous crontab from $BACKUP_CRONTAB."
        else
            root_log_error "Failed to restore previous crontab (it may have been empty or restoration failed)."
        fi
        rm -f "$TMP_CRONTAB" "$BACKUP_CRONTAB"
        return 1 # General error
    fi
}

root_template_directory() {
    local source_dir="${1:-}"
    local destination_dir="${2:-}"

    if [[ -z "$source_dir" ]]; then
        root_log_error "Usage: root_template_directory <source_dir> <destination_dir>"
        return 64
    fi
    if [[ -z "$destination_dir" ]]; then
        root_log_error "Usage: root_template_directory <source_dir> <destination_dir>"
        return 64
    fi

    # --- Validate directories ---
    if [[ ! -d "$source_dir" ]]; then
        root_log_error "Source directory not found or is not a directory: $source_dir"
        return 66 # EX_NOINPUT
    fi

    # Ensure the destination directory exists, creating it if necessary
    root_log_info "Ensuring destination directory exists: $destination_dir"
    mkdir -p "$destination_dir"

    # --- Process Files ---
    root_log_info "Starting to render templates from '$source_dir' to '$destination_dir'..."

    find "$source_dir" -type f -printf "%P\n" | while IFS= read -r relative_path; do
        local source_file="$source_dir/$relative_path"
        local dest_file="$destination_dir/$relative_path"
        local dest_sub_dir=$(dirname "$dest_file")

        root_log_info "Processing: $relative_path"

        # Ensure the subdirectory structure exists in the destination
        if [[ ! -d "$dest_sub_dir" ]]; then
            mkdir -p "$dest_sub_dir"
            root_log_info "Created subdirectory: $dest_sub_dir"
        fi

        # Backup existing file if it exists at the destination
        if [[ -f "$dest_file" ]]; then
            local safe_relative_path=$(echo "$relative_path" | tr '/' '_')
            local backup_file="/tmp/${safe_relative_path}.$(date +%s).bak"

            root_log_warn "Destination file exists: $dest_file. Backing up to $backup_file"
            if ! cp "$dest_file" "$backup_file"; then
                 root_log_error "Failed to create backup for $dest_file. Aborting this file."
                 continue # Skip to the next file
            fi
        fi

        # Render the template using the shared function
        root_template_render "$source_file" "$dest_file"
    done

    root_log_success "All template files have been rendered successfully."
}

root_template_ufw() {
    root_ensure_env
    local RULES_DIR="$1"
    local CONFIG_DIR="${2:-}" # Optional second argument

    if [[ -z "$RULES_DIR" ]]; then
        root_log_error "Usage: root_template_ufw <rules_dir> [config_dir]"
        return 64
    fi

    # --- Resolve paths ---
    if [[ "$RULES_DIR" != /* ]]; then
        RULES_DIR="$ROOT_CONFIGS/$RULES_DIR"
    fi

    if [[ ! -d "$RULES_DIR" ]]; then
        root_log_error "Rules directory does not exist: $RULES_DIR"
        return 66 # EX_NOINPUT
    fi

    if [[ -n "$CONFIG_DIR" && "$CONFIG_DIR" != /* ]]; then
        CONFIG_DIR="$ROOT_CONFIGS/$CONFIG_DIR"
    fi

    if [[ -n "$CONFIG_DIR" && ! -d "$CONFIG_DIR" ]]; then
        root_log_error "Config directory does not exist: $CONFIG_DIR"
        return 66 # EX_NOINPUT
    fi

    root_log_info "Using rules directory: $RULES_DIR"
    if [[ -n "$CONFIG_DIR" ]]; then
        root_log_info "Using config directory: $CONFIG_DIR"
    fi

    # --- Ensure required tools ---
    if ! sudo ufw --version >/dev/null 2>&1; then
        root_log_error "ufw is not installed or not working via sudo. Please run configure <node> base first."
        return 1
    fi

    local UFW_DOCKER_BIN="$HOME/.local/bin/ufw-docker"
    if [[ ! -x "$UFW_DOCKER_BIN" ]]; then
        root_log_error "ufw-docker not found at $UFW_DOCKER_BIN. Please run configure <node> base first."
        return 1
    fi

    root_log_info "Using ufw-docker: $UFW_DOCKER_BIN"

    # --- Function to inject rules into UFW config files ---
    _root_template_inject_rules_to_ufw_file() {
        local SOURCE_FILE="$1"
        local TARGET_FILE="$2"
        local ANCHOR_LINE="$3"

        if [[ ! -f "$SOURCE_FILE" ]]; then
            return 0
        fi

        root_log_info "Processing rules from $SOURCE_FILE to $TARGET_FILE"

        if ! sudo test -f "$TARGET_FILE"; then
            root_log_error "Target file does not exist: $TARGET_FILE"
            return 1
        fi

        if ! sudo grep -q "$ANCHOR_LINE" "$TARGET_FILE"; then
            root_log_warn "Anchor line '$ANCHOR_LINE' not found in $TARGET_FILE, skipping"
            return 0
        fi

        sudo sed -i '/# START ROOT.ERMNVLDMR.COM RULES/,/# END ROOT.ERMNVLDMR.COM RULES/d' "$TARGET_FILE"

        local TEMP_RULES=$(mktemp)
        echo "# START ROOT.ERMNVLDMR.COM RULES" > "$TEMP_RULES"
        awk '
            {
                gsub(/^[ \t]+/, "", $0);
                gsub(/[ \t]+$/, "", $0);
                if ($0 == "" || $0 ~ /^#/) next;
                print
            }
        ' "$SOURCE_FILE" >> "$TEMP_RULES"
        echo "# END ROOT.ERMNVLDMR.COM RULES" >> "$TEMP_RULES"

        sudo sed -i "/$ANCHOR_LINE/r $TEMP_RULES" "$TARGET_FILE"

        rm "$TEMP_RULES"
        root_log_success "Rules injected into $TARGET_FILE"
    }

    if [[ -n "$CONFIG_DIR" ]]; then
        local HOST_RULES_FILE="$CONFIG_DIR/host.rules"
        if [[ -f "$HOST_RULES_FILE" ]]; then
            root_log_info "Processing host UFW rules from $HOST_RULES_FILE"
            awk '
                {
                    gsub(/^[ \t]+/, "", $0);
                    gsub(/[ \t]+$/, "", $0);
                    if ($0 == "" || $0 ~ /^#/) next;
                    print
                }
            ' "$HOST_RULES_FILE" | while IFS= read -r HOST_RULE; do
                root_log_info "Applying host ufw rule: $HOST_RULE"
                if bash -c "sudo ufw $HOST_RULE"; then
                    root_log_success "Host rule applied: $HOST_RULE"
                else
                    root_log_error "Failed to apply host rule: $HOST_RULE"
                    return 1
                fi
            done
        fi
        
        local BEFORE_RULES_FILE="$CONFIG_DIR/before.rules"
        _root_template_inject_rules_to_ufw_file "$BEFORE_RULES_FILE" "/etc/ufw/before.rules" "# End required lines"
        
        local AFTER_RULES_FILE="$CONFIG_DIR/after.rules"
        _root_template_inject_rules_to_ufw_file "$AFTER_RULES_FILE" "/etc/ufw/after.rules" "# End required lines"
    fi

    local RULE_FILES=( "$RULES_DIR"/*.rules )
    if [[ ! -e ${RULE_FILES[0]} ]]; then
        root_log_warn "No .rules files found in $RULES_DIR, nothing to apply."
        if [[ ! -d "$CONFIG_DIR" ]]; then
            return 0
        fi
    fi

    if [[ -e ${RULE_FILES[0]} ]]; then
        for RULE_FILE in "${RULE_FILES[@]}"; do
            local RULE_BASENAME="$(basename "$RULE_FILE")"

            root_log_info "Processing rules from: $RULE_FILE"

            awk '
                {
                    gsub(/^[ \t]+/, "", $0);
                    gsub(/[ \t]+$/, "", $0);
                    if ($0 == "" || $0 ~ /^#/) next;
                    print
                }
            ' "$RULE_FILE" | while IFS= read -r RULE_CMD; do
                root_log_info "Applying rule from ${RULE_BASENAME}: $RULE_CMD"
                if sudo "$UFW_DOCKER_BIN" $RULE_CMD; then
                    root_log_success "Rule applied: $RULE_CMD"
                else
                    root_log_error "Failed to apply rule: $RULE_CMD (from $RULE_BASENAME)"
                    return 1
                fi
            done
        done
    fi

    root_log_success "All rules applied for node '$ROOT_NODE'."
    root_log_info "Run \`sudo systemctl restart ufw\` to apply rules."
    root_log_warn "Note that reload might disrupt the active connections (such as ssh) - allow ssh's port via plain ufw!"
    return 0
}
