FROM python:3.12-slim@sha256:2c941e860699f878900b0edc2403613c234d4b32eda3cc9fa7036991a2a63c4a

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CARDPRINTER_HOST=0.0.0.0 \
    CARDPRINTER_PORT=8000 \
    CARDPRINTER_COMPANION_HOST=0.0.0.0 \
    CARDPRINTER_COMPANION_PORT=8001

WORKDIR /srv/cardprinter

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin cardprinter

COPY --chown=cardprinter:cardprinter app ./app

USER cardprinter

EXPOSE 8000 8001

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).read()"]

CMD ["python", "-m", "app.server"]
