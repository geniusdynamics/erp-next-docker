# Start with the base image
FROM frappe/erpnext:v15.29.2

# Use the root user to copy files and change permissions
USER root

# Set the working directory
WORKDIR /home/frappe/frappe-bench

# Copy additional configuration files or scripts if needed
COPY scripts/start-configurator.sh /usr/local/bin/start-configurator.sh
COPY scripts/start-create-site.sh /usr/local/bin/start-create-site.sh

# Make sure the scripts are executable
RUN chmod +x /usr/local/bin/start-configurator.sh \
    /usr/local/bin/start-create-site.sh

# Set environment variables
ENV DB_HOST=db \
    DB_PORT=3306 \
    DB_PASSWORD=admin \
    DB_NAME=erpnext \
    REDIS_CACHE=redis-cache:6379 \
    REDIS_QUEUE=redis-queue:6379 \
    LETSENCRYPT_EMAIL=you@example.com \
    FRAPPE_SITE_NAME_HEADER=frontend \
    UPSTREAM_REAL_IP_ADDRESS=127.0.0.1 \
    UPSTREAM_REAL_IP_HEADER=X-Forwarded-For \
    UPSTREAM_REAL_IP_RECURSIVE=off \
    PROXY_READ_TIMEOUT=120 \
    CLIENT_MAX_BODY_SIZE=50m \
    SITES=/home/frappe/frappe-bench/sites

# Expose port 8000
EXPOSE 8000

# Switch back to the original non-root user (frappe)
USER frappe

# Use ENTRYPOINT to run initialization scripts
ENTRYPOINT ["/bin/sh", "-c", "/usr/local/bin/start-configurator.sh && /usr/local/bin/start-create-site.sh"]
