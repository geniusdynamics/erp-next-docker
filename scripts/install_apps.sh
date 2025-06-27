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
    echo "Error: Invalid JSON in $APPS_JSON_PATH. Custom app installation cannot proceed."
    exit 1 # Fail the build
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
        echo "Successfully got app: $app_name"

        # Install the app to a temporary site to resolve Python dependencies
        # This is memory intensive but necessary for dependencies to be installed by pip
        # We will remove this site later.
        # Note: A dummy site name is used. This site won't be part of the final image.
        # It's purely for triggering `pip install -e .` and other build steps for the app.
        # This also assumes that `bench new-site` is not required here,
        # as `bench install-app` should handle pip dependencies.
        # However, `bench install-app` requires a site.
        # For a build process, we often don't have a site.
        # `bench get-app` fetches the code. `pip install -e ./apps/$app_name` might be more direct for deps
        # but `bench install-app` is the more standard way to ensure all build steps are run.

        # Frappe/ERPNext often requires `bench setup requirements` or `bench build` after new apps.
        # Let's try to install dependencies directly if possible, or use a temp site.
        # The most direct way to install dependencies for a checked-out app is:
        echo "Installing Python dependencies for $app_name..."
        if [ -f "apps/$app_name/requirements.txt" ]; then
            echo "Found requirements.txt for $app_name. Installing..."
            pip install --no-cache-dir -r "apps/$app_name/requirements.txt" && rm -rf /home/frappe/.cache/pip
        else
            echo "No direct requirements.txt found for $app_name. Dependencies will be handled by 'bench setup requirements' or 'bench install-app' if applicable."
        fi

        # Attempt to install the app itself using pip in editable mode if a setup.py exists
        # This is what `bench setup requirements` would partially do.
        if [ -f "apps/$app_name/setup.py" ]; then
            echo "Found setup.py for $app_name. Installing with pip editable..."
            pip install --no-cache-dir -e "apps/$app_name" && rm -rf /home/frappe/.cache/pip
        fi

        echo "Cleaning up after $app_name installation..."
        # Clean .git directory
        if [ -d "apps/$app_name/.git" ]; then
            echo "Removing .git from apps/$app_name"
            rm -rf "apps/$app_name/.git"
        fi
        # Clean .github directory
        if [ -d "apps/$app_name/.github" ]; then
            echo "Removing .github from apps/$app_name"
            rm -rf "apps/$app_name/.github"
        fi
        # Clean app-level node_modules (less common for backend-focused apps, but good to check)
        if [ -d "apps/$app_name/node_modules" ]; then
            echo "Removing node_modules from apps/$app_name"
            rm -rf "apps/$app_name/node_modules"
        fi
        # Clean __pycache__ and .pyc files
        echo "Cleaning Python cache for apps/$app_name"
        find "apps/$app_name" -type d -name "__pycache__" -print0 | xargs -0 rm -rf
        find "apps/$app_name" -type f -name "*.pyc" -delete

        # Consolidate pip cache cleanup to once after the loop if preferred,
        # but doing it per app minimizes peak cache size.
        # rm -rf /home/frappe/.cache/pip # Moved into pip install commands

        echo "Successfully processed and cleaned app: $app_name"
    else
        echo "Failed to get app: $app_name. Continuing with next app."
        # Decide if build should fail on app install failure. For now, it continues.
        # Consider adding `exit 1` here if app installation is critical
    fi
done

# A single bench build at the end is usually more efficient than per-app builds
# if frontend assets are involved.
# However, if memory is extremely constrained, per-app builds (if apps have them)
# might be necessary, followed by cleanup.
# For now, the Dockerfile does a more comprehensive cleanup after this script.

# General cleanup of pip cache one last time
echo "Final cleanup of pip cache..."
rm -rf /home/frappe/.cache/pip

echo "App installation script finished."
