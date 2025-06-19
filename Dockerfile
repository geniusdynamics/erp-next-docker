# ----------- Global Build Args ----------
ARG PYTHON_VERSION=3.11.6
ARG DEBIAN_BASE=bookworm
ARG NODE_VERSION=18.18.2
ARG FRAPPE_BRANCH=version-15
ARG ERPNEXT_VERSION

# ----------- Assets stage (static FROM needed) ----------
FROM node:18.18.2-alpine AS assets
WORKDIR /app
# Placeholder for future frontend asset build
# COPY frontend/package.json frontend/yarn.lock ./
# RUN yarn install
# COPY frontend/ ./
# RUN yarn build

# ----------- Base stage ----------
FROM python:3.11.6-slim-bookworm AS base

# Re-declare required args (not inherited automatically across stages)
ARG NODE_VERSION
ENV NVM_DIR=/home/frappe/.nvm
# Add NVM's bin to the PATH for subsequent RUN commands
ENV PATH=${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/:${PATH}

RUN useradd -ms /bin/bash frappe

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        curl git vim nginx gettext-base file \
        libpango-1.0-0 libharfbuzz0b libpangoft2-1.0-0 libpangocairo-1.0-0 \
        restic gpg mariadb-client less libpq-dev postgresql-client wait-for-it jq && \
    rm -rf /var/lib/apt/lists/*

# Install nvm, node, yarn
RUN mkdir -p ${NVM_DIR} && \
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash && \
    . ${NVM_DIR}/nvm.sh && \
    nvm install ${NODE_VERSION} && \
    nvm use v${NODE_VERSION} && \
    npm install -g yarn && \
    nvm alias default v${NODE_VERSION} && \
    rm -rf ${NVM_DIR}/.cache && \
    echo "export NVM_DIR=/home/frappe/.nvm" >> /home/frappe/.bashrc && \
    echo '[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"' >> /home/frappe/.bashrc && \
    echo '[ -s "${NVM_DIR}/bash_completion" ] && \. "${NVM_DIR}/bash_completion"' >> /home/frappe/.bashrc && \
    chown -R frappe:frappe ${NVM_DIR}

# ----------- Builder stage ----------
FROM base AS builder
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y     wget libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev libffi-dev liblcms2-dev     libldap2-dev libmariadb-dev libsasl2-dev libtiff5-dev libwebp-dev redis-tools rlwrap tk8.6-dev cron     libmagic1 gcc build-essential libbz2-dev pkg-config  && rm -rf /var/lib/apt/lists/*

RUN pip3 install frappe-bench

ARG APPS_JSON_BASE64
ARG APPS_JSON_URL
RUN mkdir -p /home/frappe/scripts /opt/frappe
COPY scripts/install_apps.sh /home/frappe/scripts/install_apps.sh
COPY scripts/create_site.sh /home/frappe/scripts/create_site.sh
RUN chmod +x /home/frappe/scripts/*.sh

USER frappe
WORKDIR /home/frappe
ARG FRAPPE_PATH=https://github.com/frappe/frappe
ARG FRAPPE_BRANCH
RUN bench init /home/frappe/frappe-bench     --frappe-branch=${FRAPPE_BRANCH}     --frappe-path=${FRAPPE_PATH}     --no-procfile     --no-backups     --skip-redis-config-generation     --verbose

# Handle apps.json
RUN if [ -n "${APPS_JSON_BASE64}" ]; then echo "${APPS_JSON_BASE64}" | base64 -d > /opt/frappe/apps.json; fi
COPY apps.json /home/frappe/frappe-bench/apps.json
RUN /home/frappe/scripts/install_apps.sh

# ----------- Final runtime stage ----------
FROM python:3.11.6-slim-bookworm AS final
ENV PATH="/home/frappe/frappe-bench/env/bin:$PATH"
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV FRAPPE_DIR /home/frappe/frappe-bench

RUN apt-get update && apt-get install --no-install-recommends -y       curl git mariadb-client gettext-base nginx  && apt-get install --no-install-recommends -y       ca-certificates fontconfig libxrender1 libxtst6 libx11-6 xfonts-base xfonts-75dpi  && ARCH=""  && [ "$(uname -m)" = "x86_64" ] && ARCH=amd64 || ARCH=arm64  && WKHTML="wkhtmltox_0.12.6.1-3.bookworm_${ARCH}.deb"  && curl -sLO "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/${WKHTML}"  && apt-get install -y ./${WKHTML}  && rm -f ${WKHTML}  && rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash -u 1000 frappe

COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench
COPY --from=builder --chown=frappe:frappe /home/frappe/scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

WORKDIR /home/frappe/frappe-bench
USER frappe

VOLUME ["/home/frappe/frappe-bench/sites", "/home/frappe/frappe-bench/sites/assets", "/home/frappe/frappe-bench/logs"]
EXPOSE 80

LABEL org.opencontainers.image.title="ERPNext NS8 Docker Image"       org.opencontainers.image.description="Customizable ERPNext Docker image for NS8 and multi-site deployments"       org.opencontainers.image.source="https://github.com/geniusdynamics/erp-next-docker"       org.opencontainers.image.licenses="MIT"       org.opencontainers.image.vendor="Genius Dynamics"       maintainer="Genius Dynamics <info@geniusdynamics.com>"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["start"]
