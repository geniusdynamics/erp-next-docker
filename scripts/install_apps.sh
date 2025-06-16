#!/bin/bash
set -eo pipefail # Exit on error, treat unset variables as an error, and propagate pipeline failures

echo "Starting app installation script..."

# Default apps.json path
APPS_JSON_PATH="/home/frappe/frappe-bench/apps.json"
APPS_JSON_SRC_DIR="/opt/frappe/apps.json" # Path where APPS_JSON_BASE64 or APPS_JSON_URL would place the file

# Check if apps.json was populated by APPS_JSON_BASE64 or APPS_JSON_URL
if [ -f "$APPS_JSON_SRC_DIR" ]; then
    echo "Found apps.json at $APPS_JSON_SRC_DIR (from APPS_JSON_BASE64 or APPS_JSON_URL)."
    APPS_JSON_PATH="$APPS_JSON_SRC_DIR"
elif [ -f "$APPS_JSON_PATH" ]; then
    echo "Found apps.json at $APPS_JSON_PATH (copied from build context)."
else
    echo "apps.json not found at $APPS_JSON_PATH or $APPS_JSON_SRC_DIR. Skipping custom app installation."
    exit 0
fi

echo "Using apps.json from: $APPS_JSON_PATH"

if ! jq -e . "$APPS_JSON_PATH" > /dev/null; then
    echo "Error: Invalid JSON in $APPS_JSON_PATH. Skipping custom app installation."
    # Optionally, exit 1 to fail the build if apps.json is present but invalid
    # For now, we'll allow the build to continue without custom apps if JSON is malformed.
    exit 0
fi

# Ensure we are in the frappe-bench directory
if [ ! -d "/home/frappe/frappe-bench" ]; then
    echo "Error: /home/frappe/frappe-bench directory not found."
    exit 1
fi
cd /home/frappe/frappe-bench

# Check if bench is initialized
if [ ! -f "Procfile" ]; then # Procfile is a good indicator of an initialized bench
    echo "Warning: Bench does not appear to be initialized in /home/frappe/frappe-bench. Apps might not install correctly."
    # Consider if we should exit 1 here. For now, proceed with caution.
fi

echo "Installing apps specified in $APPS_JSON_PATH..."

# Loop through apps and install them
# Ensure jq is available (it's installed in the 'base' stage in the Dockerfile)
jq -r -c '.[]' "$APPS_JSON_PATH" | while IFS= read -r app_obj; do
    app_name=$(echo "$app_obj" | jq -r '.name // empty')
    app_url=$(echo "$app_obj" | jq -r '.url // empty')
    app_branch=$(echo "$app_obj" | jq -r '.branch // empty')

    if [ -z "$app_url" ]; then
        echo "Skipping app with missing URL: $app_obj"
        continue
    fi

    # If app_name is empty, try to derive it from the URL
    if [ -z "$app_name" ]; then
        app_name=$(basename "$app_url" .git)
        echo "Derived app name as '$app_name' from URL '$app_url'"
    fi

    if [ -z "$app_name" ]; then
        echo "Skipping app with missing name and could not derive from URL: $app_obj"
        continue
    fi

    echo "Processing app: Name='$app_name', URL='$app_url', Branch='$app_branch'"

    # Construct bench get-app command
    get_app_cmd="bench get-app"
    if [ -n "$app_branch" ]; then
        get_app_cmd="$get_app_cmd --branch $app_branch"
    fi
    get_app_cmd="$get_app_cmd $app_name $app_url" # Bench can also take just the URL if name is part of it

    echo "Executing: $get_app_cmd"
    if $get_app_cmd; then
        echo "Successfully installed app: $app_name"
        # Optional: Install app to a default site if one exists, though this is typically done at runtime
        # For example: bench --site default_site.localhost install-app "$app_name"
    else
        echo "Failed to install app: $app_name. Continuing with next app."
        # Decide if build should fail on app install failure. For now, it continues.
    fi
done

# After installing apps, it's often necessary to run a build
# bench build --app <app_name> or bench build
# This might be better suited for the end of the builder stage or even runtime,
# depending on how assets are managed. For now, let's include a general build.
# echo "Running bench build to compile assets for installed apps..."
# if bench build; then
#   echo "Bench build completed successfully."
# else
#   echo "Bench build failed. Check logs."
#   # exit 1 # Optional: fail build if assets don't compile
# fi


echo "App installation script finished."
