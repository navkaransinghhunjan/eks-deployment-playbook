# Two stages so the compiler and the -dev headers never reach the runtime image. The old
# single stage also installed nginx, vim, htop, telnet and unzip — none of which this service
# uses. install-log C51.
FROM python:3.10-slim-bookworm AS builder

ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

RUN printf 'APT::Acquire::Retries "3";\nAcquire::http::Timeout "60";\n' > /etc/apt/apt.conf.d/90retries

# Build-time only: cairocffi and WeasyPrint compile against these headers.
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential libcairo2-dev libffi-dev libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip --no-cache-dir install -U pip && \
    /opt/venv/bin/pip --no-cache-dir install -r requirements.txt


FROM python:3.10-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=claim_engine.settings \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright

RUN printf 'APT::Acquire::Retries "3";\nAcquire::http::Timeout "60";\n' > /etc/apt/apt.conf.d/90retries

# Runtime libraries only, in two groups:
#   WeasyPrint/CairoSVG render PDFs  -> cairo, pango, gdk-pixbuf, shared-mime-info, fonts
#   playwright drives headless chromium -> the nss/atk/cups/gbm/gtk set
# Dropped: nginx (see below), vim, htop, telnet, unzip, curl, gnupg, apt-transport-https,
# libpq-dev (psycopg2-binary bundles libpq) and the two -dev packages, now builder-only.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf-2.0-0 \
      shared-mime-info fonts-dejavu-core fonts-liberation \
      libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
      libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 \
      libasound2 libgtk-3-0 libx11-xcb1 libxcb1 libxext6 \
      libxrender1 libxi6 libxtst6 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Into PLAYWRIGHT_BROWSERS_PATH, not root's ~/.cache — the runtime user is uid 1000 and would
# not find a browser installed into another user's home.
RUN playwright install chromium && chmod -R a+rX /opt/playwright

RUN useradd -u 1000 -m appuser

# The WORKDIR itself, not just its contents: Docker creates it root-owned and --chown on the
# COPY covers only the copied files, so anything writing a relative path fails as uid 1000.
RUN mkdir -p /target /target/media && chown -R 1000:1000 /target
WORKDIR /target
COPY --chown=1000:1000 . .
RUN chmod +x docker-entrypoint.sh

USER 1000

EXPOSE 8080

# Web only. The worker and beat used to start from this same script with `&`, which made one
# container four processes: nothing could be scaled or restarted on its own, and a crashed
# worker left a healthy-looking pod (C2). They are separate Deployments now and override
# `command`, so this file is the web process and nothing else.
ENTRYPOINT ["./docker-entrypoint.sh"]
