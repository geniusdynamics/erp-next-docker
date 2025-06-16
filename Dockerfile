ARG PYTHON_VERSION=3.11.6
ARG DEBIAN_BASE=bookworm
ARG NODE_VERSION=18.18.2
ARG FRAPPE_BRANCH=version-15
ARG ERPNEXT_VERSION # Will be used by GitHub Actions

# Assets stage (Placeholder)
FROM node:${NODE_VERSION}-alpine as assets
WORKDIR /app
# COPY frontend/package.json frontend/yarn.lock ./
# RUN yarn install
# COPY frontend/ ./
# RUN yarn build

# Base stage
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS base
ENV NVM_DIR=/home/frappe/.nvm
ENV PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}
RUN useradd -ms /bin/bash frappe \
    && apt-get update \
    && apt-get install --no-install-recommends -y curl git vim nginx gettext-base file libpango-1.0-0 libharfbuzz0b libpangoft2-1.0-0 libpangocairo-1.0-0 restic gpg mariadb-client less libpq-dev postgresql-client wait-for-it jq \
    && mkdir -p /home/frappe/.nvm \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash \
    && export NVM_DIR="/home/frappe/.nvm" \
    && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && \
    nvm install ${NODE_VERSION} && \
    nvm use ${NODE_VERSION} && \
    npm install -g yarn && \
    nvm alias default ${NODE_VERSION} \
    && rm -rf /home/frappe/.nvm/.cache \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install frappe-bench

# Builder stage
FROM base AS builder
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y wget libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev libpq-dev libffi-dev liblcms2-dev libldap2-dev libmariadb-dev libsasl2-dev libtiff5-dev libwebp-dev redis-tools rlwrap tk8.6-dev cron libmagic1 gcc build-essential libbz2-dev \
    && rm -rf /var/lib/apt/lists/*

ARG APPS_JSON_BASE64
ARG APPS_JSON_URL
RUN mkdir -p /home/frappe/scripts /opt/frappe
COPY scripts/install_apps.sh /home/frappe/scripts/install_apps.sh
COPY scripts/create_site.sh /home/frappe/scripts/create_site.sh
RUN chmod +x /home/frappe/scripts/install_apps.sh
RUN chmod +x /home/frappe/scripts/create_site.sh

USER frappe
WORKDIR /home/frappe
ARG FRAPPE_PATH=https://github.com/frappe/frappe
RUN bench init frappe-bench \
    --frappe-branch=${FRAPPE_BRANCH} \
    --frappe-path=${FRAPPE_PATH} \
    --no-procfile \
    --no-backups \
    --skip-redis-config-generation \
    --verbose
RUN if [ -n "${APPS_JSON_BASE64}" ]; then echo "${APPS_JSON_BASE64}" | base64 -d > /opt/frappe/apps.json; fi
# In a real scenario, fetching from APPS_JSON_URL would happen here and place it in /opt/frappe/apps.json
# For now, we will copy it from context if not using base64
COPY apps.json /home/frappe/frappe-bench/apps.json
RUN /home/frappe/scripts/install_apps.sh

# Final runtime stage
FROM python:${PYTHON_VERSION}-slim-${DEBIAN_BASE} AS final
ENV PATH="/home/frappe/frappe-bench/env/bin:$PATH"
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV FRAPPE_DIR /home/frappe/frappe-bench
RUN apt-get update \
    && apt-get install --no-install-recommends -y curl git mariadb-client gettext-base nginx \
    && rm -rf /var/lib/apt/lists/*
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        ca-certificates \
        fontconfig \
        libxrender1 \
        libxtst6 \
        libx11-6 \
        xfonts-base \
        xfonts-75dpi && \
    ARCH="" && \
    if [ "$(uname -m)" = "aarch64" ]; then export ARCH=arm64; fi && \
    if [ "$(uname -m)" = "x86_64" ]; then export ARCH=amd64; fi && \
    if [ -z "$ARCH" ]; then echo "Unsupported architecture for wkhtmltopdf"; exit 1; fi && \
    downloaded_file="wkhtmltox_0.12.6.1-3.bookworm_${ARCH}.deb" && \
    echo "Downloading $downloaded_file for $ARCH architecture..." && \
    curl -sLO "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/$downloaded_file" && \
    echo "Installing $downloaded_file..." && \
    apt-get install -y ./"$downloaded_file" && \
    echo "Cleaning up $downloaded_file..." && \
    rm ./"$downloaded_file" && \
    rm -rf /var/lib/apt/lists/*
RUN useradd -ms /bin/bash -u 1000 frappe

COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench
COPY --from=builder --chown=frappe:frappe /home/frappe/scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/install_apps.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/create_site.sh


WORKDIR /home/frappe/frappe-bench
USER frappe
VOLUME ["/home/frappe/frappe-bench/sites","/home/frappe/frappe-bench/sites/assets","/home/frappe/frappe-bench/logs"]
EXPOSE 80

LABEL org.opencontainers.image.title="ERPNext NS8 Docker Image" \
      org.opencontainers.image.description="Customizable ERPNext Docker image designed for NethServer 8 (NS8) and general use, featuring multi-site support and dynamic app installation." \
      org.opencontainers.image.source="https://github.com/geniusdynamics/erp-next-docker" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Genius Dynamics" \
      maintainer="Genius Dynamics <info@geniusdynamics.com>"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["start"]
