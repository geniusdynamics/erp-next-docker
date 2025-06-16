# ERPNext Docker Image by Genius Dynamics

This repository contains the Docker configuration for building a customizable ERPNext image, optimized for deployment, especially within NethServer 8 (NS8) modules, but also suitable for general Docker usage.

Key features include:
- Multi-stage Docker build for a lean runtime image.
- Dynamic installation of custom Frappe apps via `apps.json`.
- Optional multi-site creation and management using environment variables.
- NS8-compatible entrypoint for lifecycle management.
- Automated builds and version tagging via GitHub Actions.

## Environment Variables

The following environment variables can be used to configure the container at runtime:

### Site Creation & Management
-   `ENABLE_AUTO_SITE` (boolean): Set to `true` to enable automatic site creation and app installation on container start or when the `create-site` command is run. Defaults to `false` if not set.
-   `SITES` (string): A comma-separated list of site names to be created (e.g., `site1.localhost,site2.example.com`). Used when `ENABLE_AUTO_SITE` is `true`.
-   `ADMIN_PASS` (string): Sets the administrator password for newly created Frappe sites. Defaults to `admin` if not provided.

### Database Configuration (primarily for `common_site_config.json`)
These variables are typically used by NS8 or a configuration script to populate `sites/common_site_config.json`. The entrypoint script relies on this file being correctly configured before sites can be created or services started.
-   `DB_HOST`: Hostname or IP address of the MariaDB/PostgreSQL server.
-   `DB_PORT`: Port number of the database server (e.g., `3306` for MariaDB).
-   `DB_USER`: Database user for Frappe (bench usually creates this).
-   `DB_PASSWORD`: Password for the Frappe database user.

### Redis Configuration (primarily for `common_site_config.json`)
-   `REDIS_CACHE`: Redis connection string for caching (e.g., `redis://redis-cache:6379`).
-   `REDIS_QUEUE`: Redis connection string for background jobs and queues (e.g., `redis://redis-queue:6379`).
-   `REDIS_SOCKETIO`: Redis connection string for Socket.IO (usually the same as `REDIS_QUEUE`).

### Frappe/Webserver Configuration
-   `FRAPPE_SITE_NAME_HEADER` (string): The HTTP header Nginx/proxy should use to determine the site name for a request (e.g., `$$host`, `X-Frappe-Site-Name`). This is important for multi-site setups.
-   `SOCKETIO_PORT` (integer): The port on which the Frappe Socket.IO service will listen (e.g., `9000`).
-   `DEBUG_ENTRYPOINT` (boolean): If set to `true`, the main entrypoint script (`entrypoint.sh`) will run with `set -x` for verbose debug logging.

## Custom App Installation

This image supports installing custom Frappe applications at build time. Provide an `apps.json` file in the root of this repository or specify a URL.

**1. Using `apps.json` in the Repository:**
   Create an `apps.json` file in the root of this repository. The build process will automatically pick it up.

   Example `apps.json`:
   ```json
   [
     {
       "name": "erpnext",
       "url": "https://github.com/frappe/erpnext",
       "branch": "version-15"
     },
     {
       "name": "hrms",
       "url": "https://github.com/frappe/hrms",
       "branch": "version-15"
     },
     {
       "url": "https://github.com/my_custom_app_org/my_custom_app",
       "branch": "main"
     }
   ]
   ```
   *(Note: If `name` is omitted, it will be derived from the URL. Ensure URLs are accessible during the build.)*

**2. Using `APPS_JSON_URL` Build Argument:**
   You can specify a URL to an `apps.json` file during the Docker build:
   ```shell
   docker build --build-arg APPS_JSON_URL="https://example.com/path/to/your/apps.json" -t geniusdynamics/erpnext:latest .
   ```

**3. Using `APPS_JSON_BASE64` Build Argument (Legacy):**
   You can also pass the content of `apps.json` as a base64 encoded string (less common for manual builds):
   ```shell
   export APPS_JSON_BASE64=$(base64 -w 0 my_apps.json)
   docker build --build-arg APPS_JSON_BASE64=$APPS_JSON_BASE64 -t geniusdynamics/erpnext:latest .
   ```

The `scripts/install_apps.sh` script handles fetching and installing these apps using `bench get-app`. If `apps.json` is present but malformed, the build will fail.

## Entrypoint and Commands (`scripts/entrypoint.sh`)

The Docker image uses `scripts/entrypoint.sh` as its main entrypoint.

-   **Default Behavior:**
    -   On container start, it first checks if the Frappe instance is configured (i.e., if `sites/common_site_config.json` contains necessary DB and Redis details).
    -   If **not configured**, it will print a message and do nothing further, awaiting configuration (as per NS8 guidelines).
    -   If **configured**:
        -   If `ENABLE_AUTO_SITE=true` and `SITES` are defined, it will attempt to create the specified sites and install apps using `scripts/create_site.sh`.
        -   It then starts the Frappe services (typically `bench start`, which includes Gunicorn web server and background workers).
-   **Manual Site Creation:**
    You can manually trigger site creation/app installation using `docker exec`:
    ```shell
    docker exec <container_name_or_id> create-site
    ```
    This will use the `SITES` and `ADMIN_PASS` environment variables.
-   **Running `bench` Commands:**
    Execute any `bench` command like so:
    ```shell
    docker exec <container_name_or_id> bench version
    docker exec <container_name_or_id> bench backup --with-files
    docker exec <container_name_or_id> bench migrate
    ```
-   **Starting Services Manually:**
    If you need to manually start the services (after configuration):
    ```shell
    docker exec <container_name_or_id> start
    ```
    Or to start Gunicorn directly:
    ```shell
    docker exec <container_name_or_id> gunicorn
    ```

## Building the Image

### Automated Builds (GitHub Actions)
This repository is configured with a GitHub Actions workflow (`.github/workflows/autobuild.yml`) that:
-   Triggers on pushes to `main` (for relevant files like Dockerfile, scripts, apps.json), daily schedules, or manual dispatch.
-   Fetches the latest official ERPNext release tag from GitHub.
-   Builds multi-platform Docker images (`linux/amd64`, `linux/arm64`).
-   Tags images with the ERPNext version (e.g., `15.1.0`, `v15`) and pushes them to Docker Hub (`geniusdynamics/erpnext`) and/or GitHub Container Registry (`ghcr.io/geniusdynamics/erpnext`), depending on configured secrets.

### Manual Builds
To build the image manually:
```shell
docker build -t geniusdynamics/erpnext:custom .
```
You can use build arguments to customize the build:
-   `FRAPPE_BRANCH`: Specify the Frappe branch to initialize bench with (e.g., `version-15`). Defaults to `version-15`.
-   `ERPNEXT_VERSION`: Informational argument, often set to the ERPNext tag being targeted. Used by GitHub Actions.
-   `APPS_JSON_URL`: URL to an external `apps.json` file.
-   `APPS_JSON_BASE64`: Base64 encoded content of an `apps.json` file.

Example with build arguments:
```shell
docker build \
  --build-arg FRAPPE_BRANCH="version-15" \
  --build-arg ERPNEXT_VERSION="v15.10.0" \
  --build-arg APPS_JSON_URL="https_url_to_your_apps.json" \
  -t geniusdynamics/erpnext:latest .
```

## Running the Container

Example `docker run` command (ensure you have a running MariaDB and Redis accessible):
```shell
docker run -d \
  --name my-erpnext-app \
  -p 8000:8000 \
  -e ENABLE_AUTO_SITE=true \
  -e SITES="myerp.localhost" \
  -e ADMIN_PASS="securepassword" \
  -e DB_HOST="your_db_host" \
  -e DB_PORT="3306" \
  -e REDIS_CACHE="redis://your_redis_cache_host:6379" \
  -e REDIS_QUEUE="redis://your_redis_queue_host:6379" \
  -e SOCKETIO_PORT="9000" \
  -e FRAPPE_SITE_NAME_HEADER="myerp.localhost" \
  -v erpnext_sites:/home/frappe/frappe-bench/sites \
  -v erpnext_logs:/home/frappe/frappe-bench/logs \
  geniusdynamics/erpnext:latest
```
*(Note: For a complete setup, you'll need a database (MariaDB/PostgreSQL) and Redis instances. The `docker-compose.yml` in this repository provides a full example.)*

## Docker Compose Example

This repository includes a `docker-compose.yml` file for a multi-container setup, ideal for development and testing. It orchestrates the ERPNext application container along with MariaDB and Redis services.

To use it:
1.  Ensure you have Docker and Docker Compose installed.
2.  Create a `.env` file from `example.env` and customize the variables as needed (e.g., `SITES`, `ADMIN_PASS`, `MYSQL_ROOT_PASSWORD`).
    ```shell
    cp example.env .env
    # Edit .env with your preferred settings
    ```
3.  Run Docker Compose:
    ```shell
    docker-compose up -d
    ```
4.  **Important First Time Setup (if not using NS8 to pre-configure `common_site_config.json`):**
    The `erpnext` container's entrypoint expects `sites/common_site_config.json` to be populated with database and Redis details *before* it can create sites or start services.
    If this file is empty or missing these details, you need to set them using `bench set-config`:
    ```shell
    # Wait for the container to start
    docker-compose exec erpnext bench set-config -g db_host db
    docker-compose exec erpnext bench set-config -gp db_port 3306 # Ensure this is an integer
    # For MariaDB, bench new-site will typically ask for root DB password to create user/db.
    # Ensure common_site_config.json has necessary details if you are not creating site interactively.
    # For non-interactive setup, you might need to manually set db_name, db_password if bench new-site requires it and can't derive it.
    # However, bench new-site usually handles this if it can connect to the DB server with root credentials.
    docker-compose exec erpnext bench set-config -g redis_cache redis://redis-cache:6379
    docker-compose exec erpnext bench set-config -g redis_queue redis://redis-queue:6379
    docker-compose exec erpnext bench set-config -g redis_socketio redis://redis-queue:6379 # Or your specific socketio redis
    docker-compose exec erpnext bench set-config -gp socketio_port 9000 # Ensure this is an integer
    ```
    After this, you can trigger site creation (if `ENABLE_AUTO_SITE` wasn't already effective or if you want to re-run):
    ```shell
    docker-compose exec erpnext create-site
    ```
    Or, if sites are created and you need to restart services:
    ```shell
    docker-compose restart erpnext
    ```

Refer to the `docker-compose.yml` and `example.env` files for more details on service configuration.

## Image Tagging

Images pushed to Docker Hub/GHCR by the CI workflow are tagged as:
-   `geniusdynamics/erpnext:<version>` (e.g., `geniusdynamics/erpnext:15.1.0`)
-   `geniusdynamics/erpnext:<major_version>` (e.g., `geniusdynamics/erpnext:v15`)

Replace `geniusdynamics/erpnext` with `ghcr.io/geniusdynamics/erpnext` for the GitHub Container Registry.
