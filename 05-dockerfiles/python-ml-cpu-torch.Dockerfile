# Was two FROM lines: a dead `python:3.10` stage nothing copied from, then the real base
# `<REGISTRY_HOST>/...:pytest-coverage-latest` — a MUTABLE tag — with
# `pip install -r requirements.txt` commented out, so every dependency came from that tag and
# editing requirements.txt changed nothing. Same shape as C29. The dead stage also carried a
# commented-out AWS key pair (C47); it is gone from here but still in git history.
FROM python:3.10-slim AS builder

COPY requirements.txt .
# torch first, from the CPU index. The default PyPI wheel bundles CUDA and costs ~2GB in a
# service whose own code sets device="cpu" (main.py:54).
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip --no-cache-dir install -U pip && \
    /opt/venv/bin/pip --no-cache-dir install \
        --index-url https://download.pytorch.org/whl/cpu torch && \
    /opt/venv/bin/pip --no-cache-dir install -r requirements.txt


FROM python:3.10-slim

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" PYTHONUNBUFFERED=1

RUN useradd -u 1000 -m appuser

# The WORKDIR itself, not just its contents: Docker creates it root-owned, and --chown on the
# COPY only covers the copied files. Without this, anything resolving a RELATIVE path writes
# into a directory uid 1000 cannot write — main.py's os.makedirs("resources") is exactly that,
# and it fails at startup, after the image looks fine.
RUN mkdir -p /target && chown 1000:1000 /target
WORKDIR /target
COPY --chown=1000:1000 . .
RUN chmod +x /target/docker-entrypoint.sh

USER 1000

# 8080, not 80 — uid 1000 cannot bind a privileged port under the kubelet. install-log C1.
EXPOSE 8080

ENTRYPOINT ["/target/docker-entrypoint.sh"]
