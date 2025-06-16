#!/bin/bash
set -eo pipefail

# Default bench command if nothing specific is requested
DEFAULT_COMMAND="start"
FRAPPE_BENCH_DIR="/home/frappe/frappe-bench"
COMMON_SITE_CONFIG="${FRAPPE_BENCH_DIR}/sites/common_site_config.json"

echo "NS8 Entrypoint started. Arguments: $@"
echo "User: $(id -u -n)"
echo "Group: $(id -g -n)"
echo "UID: $(id -u)"
echo "GID: $(id -g)"
echo "Working directory: $(pwd)"

# Ensure we are in the frappe-bench directory for bench commands
cd "$FRAPPE_BENCH_DIR" || { echo "Failed to change to $FRAPPE_BENCH_DIR. Exiting."; exit 1; }

# Function to check if Frappe is configured (basic check)
is_configured() {
    if [ -f "$COMMON_SITE_CONFIG" ] && [ -s "$COMMON_SITE_CONFIG" ] && jq -e '.db_host?' "$COMMON_SITE_CONFIG" > /dev/null; then
        return 0 # True, configured
    else
        return 1 # False, not configured
    fi
}

# Function to handle site creation
# This will call the create_site.sh script (to be implemented in the next plan step)
run_site_creation() {
    echo "Attempting site creation/update..."
    if [ -x "/usr/local/bin/create_site.sh" ]; then
        # Pass current arguments to create_site.sh in case it needs them, though it primarily uses ENV vars
        /usr/local/bin/create_site.sh "$@"
    else
        echo "WARNING: /usr/local/bin/create_site.sh not found or not executable."
    fi
}

# Main logic based on arguments
if [ $# -eq 0 ]; then
    # No arguments provided, use default behavior
    echo "No command provided. Checking configuration..."
    if is_configured; then
        echo "Instance is configured."
        if [ "$ENABLE_AUTO_SITE" = "true" ] && [ -n "$SITES" ]; then
            echo "ENABLE_AUTO_SITE is true and SITES is set. Triggering auto site creation/update."
            run_site_creation
        fi
        echo "Executing default command: bench $DEFAULT_COMMAND"
        exec bench $DEFAULT_COMMAND
    else
        echo "Instance is not configured (common_site_config.json missing or incomplete)."
        echo "Doing nothing as per NS8 guidelines for unconfigured instances on first run."
        echo "Please configure the instance (e.g., using 'docker exec <container> configure <options>') or run 'docker exec <container> create-site' explicitly."
        # Exit gracefully or sleep indefinitely to keep container running for inspection/exec
        # For NS8, it's often better to exit if nothing to do, so orchestration can detect it.
        # However, sometimes keeping it running is useful for `docker exec`. Let's log and exit.
        exit 0
    fi
elif [ "$1" = "create-site" ]; then
    echo "Command: create-site"
    shift # Remove 'create-site' from arguments
    if ! is_configured; then
        echo "Warning: Instance does not appear to be fully configured (common_site_config.json). Site creation might fail or be incomplete."
        echo "Proceeding with site creation attempt..."
    fi
    run_site_creation "$@" # Pass remaining arguments
    echo "Site creation process finished."
    # Decide if to exit or continue. Typically, `docker exec` commands complete.
    exit 0
elif [ "$1" = "configure" ]; then
    # This is a placeholder for NS8's configure lifecycle.
    # Actual configuration (like setting db_host in common_site_config.json)
    # is often done by a separate script/command that MODIFIES common_site_config.json,
    # which this entrypoint then reads.
    # For example, `bench set-config ...` commands would be run by NS8.
    echo "Command: configure"
    echo "This entrypoint itself doesn't perform configuration but acknowledges the step."
    echo "Configuration should be done by NS8 lifecycle scripts that modify common_site_config.json."
    # Example: bench set-config -g db_host "$DB_HOST"
    #          bench set-config -gp db_port "$DB_PORT"
    # These would be run via `docker exec <container_id> bench set-config ...`
    # For now, just echo and exit.
    echo "Configure command received. Arguments: $@"
    # You might want to run a specific configuration script here if needed.
    exit 0
elif [ "$1" = "start" ]; then
    echo "Command: start"
    if ! is_configured; then
        echo "Instance is not configured. Cannot start."
        exit 1
    fi
    if [ "$ENABLE_AUTO_SITE" = "true" ] && [ -n "$SITES" ]; then
        echo "ENABLE_AUTO_SITE is true and SITES is set. Triggering auto site creation/update before starting."
        run_site_creation
    fi
    echo "Starting Frappe/ERPNext services using 'bench start'..."
    exec bench start
elif [ "$1" = "gunicorn" ]; then
    echo "Command: gunicorn"
     if ! is_configured; then
        echo "Instance is not configured. Cannot start gunicorn."
        exit 1
    fi
    if [ "$ENABLE_AUTO_SITE" = "true" ] && [ -n "$SITES" ]; then
        echo "ENABLE_AUTO_SITE is true and SITES is set. Triggering auto site creation/update before starting gunicorn."
        run_site_creation
    fi
    echo "Starting Gunicorn directly..."
    exec gunicorn --chdir=/home/frappe/frappe-bench/sites \
        --bind=0.0.0.0:8000 \
        --threads=4 \
        --workers=2 \
        --worker-class=gthread \
        --worker-tmp-dir=/dev/shm \
        --timeout=120 \
        --preload \
        frappe.app:application "$@" # Pass any additional gunicorn args
else
    # Default to running bench commands if not a special keyword
    echo "Command: bench $@"
    if ! is_configured && [[ "$1" != "init"* && "$1" != "set-config"* && "$1" != "new-site"* ]]; then
        # Allow certain commands like init, set-config, new-site even if not fully configured
        echo "Warning: Instance is not fully configured. Command '$1' might not work as expected."
    fi
    exec bench "$@"
fi
