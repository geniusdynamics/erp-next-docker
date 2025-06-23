#!/bin/bash
set -eo pipefail

FRAPPE_BENCH_DIR="/home/frappe/frappe-bench"
SITES_DIR="${FRAPPE_BENCH_DIR}/sites"
APPS_DIR="${FRAPPE_BENCH_DIR}/apps"

echo "Multi-site creation script started."
echo "ENABLE_AUTO_SITE: ${ENABLE_AUTO_SITE}"
echo "SITES: ${SITES}"
echo "ADMIN_PASS: (hidden)" # Don't log admin_pass if set

# Ensure we are in the frappe-bench directory
cd "$FRAPPE_BENCH_DIR" || { echo "Failed to change to $FRAPPE_BENCH_DIR. Exiting."; exit 1; }

# Check if bench is initialized
if [ ! -f "Procfile" ]; then
    echo "Error: Bench does not appear to be initialized in $FRAPPE_BENCH_DIR. Cannot create sites."
    exit 1
fi

# Check if common_site_config.json exists and is populated, otherwise bench new-site might fail
if [ ! -f "${SITES_DIR}/common_site_config.json" ] || ! jq -e '.db_host?' "${SITES_DIR}/common_site_config.json" > /dev/null; then
    echo "Error: ${SITES_DIR}/common_site_config.json is missing or not configured with database details."
    echo "Please ensure the instance is configured before creating sites (e.g. db_host, redis_cache, redis_queue)."
    exit 1
fi

# Only proceed if SITES environment variable is set
if [ -z "$SITES" ]; then
    echo "SITES environment variable is not set. No sites to create."
    exit 0
fi

# Use ADMIN_PASS from environment or default to 'admin'
ADMIN_PASSWORD="${ADMIN_PASS:-admin}"

# Convert comma-separated SITES string to an array
IFS=',' read -r -a site_list <<< "$SITES"

echo "Found $(ls -1 "$APPS_DIR" | wc -l) apps in $APPS_DIR directory."
installed_apps_list=()
while IFS= read -r app_name; do
    # Skip 'frappe' itself if it's listed as a directory, as it's the framework
    if [[ "$app_name" == "frappe" ]]; then
        continue
    fi
    # Check if it's a directory (actual app)
    if [[ -d "$APPS_DIR/$app_name" ]]; then
        installed_apps_list+=("$app_name")
    fi
done < <(ls -1 "$APPS_DIR")


# Create a list of apps to install on new sites
# This should include erpnext by default, plus any other apps found in the apps directory
apps_to_install_on_site=("erpnext")
for app in "${installed_apps_list[@]}"; do
    if [[ "$app" != "erpnext" ]]; then # Avoid duplicate if erpnext is already in installed_apps_list
        apps_to_install_on_site+=("$app")
    fi
done
# Remove duplicates just in case (though above logic should prevent it for erpnext)
apps_to_install_on_site=($(echo "${apps_to_install_on_site[@]}" | tr ' ' '
' | sort -u | tr '
' ' '))


echo "Apps to install on each new site: ${apps_to_install_on_site[*]}"


for site_name in "${site_list[@]}"; do
    echo "Processing site: $site_name"

    if [ -d "${SITES_DIR}/${site_name}" ]; then
        echo "Site '$site_name' already exists. Checking if all apps are installed."
        # Ensure all apps are installed on the existing site
        for app_to_install in "${apps_to_install_on_site[@]}"; do
            if ! bench --site "$site_name" list-apps | grep -qw "$app_to_install"; then
                echo "App '$app_to_install' not found on existing site '$site_name'. Installing..."
                if bench --site "$site_name" install-app "$app_to_install"; then
                    echo "Successfully installed app '$app_to_install' on site '$site_name'."
                else
                    echo "Failed to install app '$app_to_install' on site '$site_name'. It might already be installed or an error occurred."
                fi
            else
                echo "App '$app_to_install' is already installed on site '$site_name'."
            fi
        done
    else
        echo "Site '$site_name' does not exist. Creating new site..."
        # Create new site, install erpnext first
        # --no-mariadb-socket might be needed if MariaDB is not on localhost or socket is not in default path.
        # Assuming DB is accessible via TCP as configured in common_site_config.json
        new_site_cmd="bench new-site "$site_name" --admin-password "$ADMIN_PASSWORD" --no-input"

        # Check if erpnext is in the list of apps to install. If so, it can be installed via --install-app
        erpnext_in_apps_list=false
        for app in "${apps_to_install_on_site[@]}"; do
            if [[ "$app" == "erpnext" ]]; then
                erpnext_in_apps_list=true
                break
            fi
        done

        if $erpnext_in_apps_list; then
            new_site_cmd="$new_site_cmd --install-app erpnext"
        fi

        echo "Executing: $new_site_cmd"
        if eval "$new_site_cmd"; then # Using eval to handle quotes in site_name if any (though generally not recommended)
            echo "Successfully created new site: $site_name"

            # Install other apps specified in apps_to_install_on_site (excluding erpnext if already installed by new-site)
            for app_to_install in "${apps_to_install_on_site[@]}"; do
                if [[ "$app_to_install" == "erpnext" && "$erpnext_in_apps_list" == "true" ]]; then
                    echo "erpnext already specified with --install-app during new-site creation for $site_name."
                    continue
                fi

                echo "Installing app '$app_to_install' on new site '$site_name'..."
                if bench --site "$site_name" install-app "$app_to_install"; then
                    echo "Successfully installed app '$app_to_install' on site '$site_name'."
                else
                    # Log error but continue; `bench install-app` can fail if already installed but not listed, etc.
                    echo "Failed to install app '$app_to_install' on site '$site_name'. It might already be installed or an error occurred."
                fi
            done

            # Set site as default if it's the first one in the SITES list (optional behavior)
            # if [ "$site_name" == "${site_list[0]}" ]; then
            #     echo "Setting $site_name as default site."
            #     bench use "$site_name"
            # fi

        else
            echo "Failed to create new site: $site_name"
            # Continue to the next site even if one fails
        fi
    fi
    echo "Finished processing site: $site_name"
done

# Optional: Run bench build if any new apps were installed to any site.
# This might be better done once after all sites and apps are processed.
# For now, this script focuses on site and app installation.
# echo "Running bench build if necessary..."
# bench build --force # Force build if assets might be stale

echo "Multi-site creation script finished."
