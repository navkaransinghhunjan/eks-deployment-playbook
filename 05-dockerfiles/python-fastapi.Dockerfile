# medical-fraud-detection. See arch_knowlenge_base <NAMESPACE>/install-log.md §§ 16-28.
#
# Rebuilt from python:3.10-slim. The previous Dockerfile had two problems:
#   - a dead first stage (python:3.10-slim + curl/unzip) that nothing ever copied from
#   - `pip install -r requirements.txt` commented out, so every dependency came from the
#     mutable tag <REGISTRY_HOST>/...:pytest-coverage-latest. The build was not
#     reproducible and edits to requirements.txt had no effect at all.
FROM python:3.10-slim

WORKDIR /target

# Pure-Python deps (fastapi, langchain, openai, aiofiles); no compiler or system libs needed.
COPY requirements.txt .
RUN pip install --no-cache-dir --timeout 120 --retries 5 -r requirements.txt

COPY . .

# 8080, not 80: the pod runs as uid 1000, which cannot bind a port below 1024.
# Keep in step with docker-entrypoint.sh and containerPort in the manifest.
EXPOSE 8080

RUN useradd --uid 1000 --create-home app && chown -R app:app /target
USER 1000

ENTRYPOINT ["/target/docker-entrypoint.sh"]
