# Start with the base image
FROM frappe/erpnext:v15.29.2

# Set the working directory
WORKDIR /home/frappe/frappe-bench

# Example: Copy additional configuration files or scripts if needed
COPY scripts/start-configurator.sh /usr/local/bin/start-configurator.sh
COPY scripts/start-scheduler.sh /usr/local/bin/start-scheduler.sh
COPY scripts/start-queue-long.sh /usr/local/bin/start-queue-long.sh
COPY scripts/start-queue-short.sh /usr/local/bin/start-queue-short.sh
COPY scripts/start-websocket.sh /usr/local/bin/start-websocket.sh
COPY scripts/start-create-site.sh /usr/local/bin/start-create-site.sh

# Example: Set environment variables if needed
ENV DB_HOST=db
ENV DB_PORT=3306
ENV REDIS_CACHE=redis-cache:6379
ENV REDIS_QUEUE=redis-queue:6379
ENV SOCKETIO_PORT=9000

# Example: Run additional commands during build if required
# RUN apt-get update && apt-get install -y <package-name>

# Example: Define the default command to run when the container starts
CMD ["/bin/bash", "-c", "start-configurator.sh && start-scheduler.sh && start-queue-long.sh && start-queue-short.sh && start-websocket.sh && start-create-site.sh && \
 /home/frappe/frappe-bench/env/bin/gunicorn --chdir=/home/frappe/frappe-bench/sites --bind=0.0.0.0:8000 --threads=4 --workers=2 --worker-class=gthread --worker-tmp-dir=/dev/shm --timeout=120 --preload frappe.app:application"]
