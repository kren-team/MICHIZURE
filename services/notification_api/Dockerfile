FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN pip install --no-cache-dir uv==0.7.13

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY notification_api ./notification_api

EXPOSE 8080

CMD ["sh", "-c", "uv run uvicorn notification_api.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
