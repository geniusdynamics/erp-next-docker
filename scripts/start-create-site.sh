#!/bin/bash

# Wait for services to be available
# shellcheck disable=SC2086
wait-for-it -t 120 "$DB_HOST":$DB_PORT
# shellcheck disable=SC2086
wait-for-it -t 120 $REDIS_CACHE:6379
wait-for-it -t 120 "$REDIS_QUEUE":6379

# Check for common_site_config.json
export start=$(date +%s)
until [[ -n $(grep -hs ^ sites/common_site_config.json | jq -r ".db_host // empty") ]] && \
  [[ -n $(grep -hs ^ sites/common_site_config.json | jq -r ".redis_cache // empty") ]] && \
  [[ -n $(grep -hs ^ sites/common_site_config.json | jq -r ".redis_queue // empty") ]]; do
  echo "Waiting for sites/common_site_config.json to be created"
  sleep 5
  if [ $(($(date +%s)-start)) -gt 120 ]; then
    echo "Could not find sites/common_site_config.json with required keys"
    exit 1
  fi
done
echo "sites/common_site_config.json found"

# Create a new ERPNext site
bench new-site --no-mariadb-socket --admin-password="$ADMIN_PASSWORD" --db-root-password="$DB_ROOT_PASSWORD" --install-app erpnext --set-default frontend
