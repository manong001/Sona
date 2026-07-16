FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
    PIP_DEFAULT_TIMEOUT=180 \
    PIP_RETRIES=10 \
    HOME=/tmp

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py THIRD_PARTY_NOTICES.md ./

# compose can run this image with an arbitrary host PUID/PGID.  Keep the
# sidecar cache writable by that runtime UID rather than only by build-time
# user 10001.
RUN mkdir -p /music/download /tmp/sona-downloader \
    && chown -R 10001:10001 /app /music \
    && chmod 1777 /tmp/sona-downloader

USER 10001:10001
EXPOSE 6700

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:6700/health', timeout=3)"

ENTRYPOINT ["python", "/app/app.py"]
